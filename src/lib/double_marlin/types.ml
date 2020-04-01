open Rugelach_types
open Core_kernel

let index_to_field_elements ({row; col; value} : _ Abc.t Matrix_evals.t)
    ~g:g_to_field_elements =
  Array.concat_map [|row; col; value|] ~f:(fun {a; b; c} ->
      Array.concat_map [|a; b; c|] ~f:(fun g ->
          Array.of_list (g_to_field_elements g) ) )

module Dlog_based = struct
  module Proof_state = struct
    module Deferred_values = struct
      module Marlin = struct
        type ('challenge, 'fp) t =
          { sigma_2: 'fp
          ; sigma_3: 'fp
          ; alpha: 'challenge
          ; eta_a: 'challenge
          ; eta_b: 'challenge
          ; eta_c: 'challenge
          ; beta_1: 'challenge
          ; beta_2: 'challenge
          ; beta_3: 'challenge }
        [@@deriving bin_io]

        let map_challenges
            { sigma_2
            ; sigma_3
            ; alpha
            ; eta_a
            ; eta_b
            ; eta_c
            ; beta_1
            ; beta_2
            ; beta_3 } ~f =
          { sigma_2
          ; sigma_3
          ; alpha= f alpha
          ; eta_a= f eta_a
          ; eta_b= f eta_b
          ; eta_c= f eta_c
          ; beta_1= f beta_1
          ; beta_2= f beta_2
          ; beta_3= f beta_3 }

        open Snarky.H_list

        let to_hlist
            { sigma_2
            ; sigma_3
            ; alpha
            ; eta_a
            ; eta_b
            ; eta_c
            ; beta_1
            ; beta_2
            ; beta_3 } =
          [sigma_2; sigma_3; alpha; eta_a; eta_b; eta_c; beta_1; beta_2; beta_3]

        let of_hlist
            ([ sigma_2
             ; sigma_3
             ; alpha
             ; eta_a
             ; eta_b
             ; eta_c
             ; beta_1
             ; beta_2
             ; beta_3 ] :
              (unit, _) t) =
          {sigma_2; sigma_3; alpha; eta_a; eta_b; eta_c; beta_1; beta_2; beta_3}

        let typ chal fp =
          Snarky.Typ.of_hlistable
            [fp; fp; chal; chal; chal; chal; chal; chal; chal]
            ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist
            ~value_to_hlist:to_hlist ~value_of_hlist:of_hlist
      end

      type ('challenge, 'fp, 'fq) t =
        { xi: 'challenge
        ; r: 'challenge
        ; r_xi_sum: 'fp
        ; marlin: ('challenge, 'fp) Marlin.t }
      [@@deriving bin_io]

      let map_challenges {xi; r; r_xi_sum; marlin} ~f =
        {xi= f xi; r= f r; r_xi_sum; marlin= Marlin.map_challenges marlin ~f}

      open Snarky.H_list

      let to_hlist {xi; r; r_xi_sum; marlin} = [xi; r; r_xi_sum; marlin]

      let of_hlist ([xi; r; r_xi_sum; marlin] : (unit, _) t) =
        {xi; r; r_xi_sum; marlin}

      let typ chal fp fq =
        Snarky.Typ.of_hlistable
          [chal; chal; fp; Marlin.typ chal fp]
          ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist
          ~value_to_hlist:to_hlist ~value_of_hlist:of_hlist
    end

    module Me_only = struct
      type ('g1, 'bulletproof_challenges) t =
        { pairing_marlin_index: 'g1 Abc.t Matrix_evals.t
        ; pairing_marlin_acc: 'g1 Pairing_marlin_types.Accumulator.t
        ; old_bulletproof_challenges: 'bulletproof_challenges }
      [@@deriving sexp_of]

      let to_field_elements_without_index
          { pairing_marlin_acc=
              { opening_check= {r_f_minus_r_v_plus_rz_pi; r_pi}
              ; degree_bound_checks=
                  {shifted_accumulator; unshifted_accumulators} }
          ; pairing_marlin_index= _
          ; old_bulletproof_challenges } ~g1:g1_to_field_elements =
        Array.concat
          [ Vector.to_array old_bulletproof_challenges
            |> Array.concat_map ~f:Vector.to_array
          ; Array.concat_map
              (Array.append
                 [|r_f_minus_r_v_plus_rz_pi; r_pi; shifted_accumulator|]
                 (Vector.to_array unshifted_accumulators))
              ~f:(fun g -> Array.of_list (g1_to_field_elements g)) ]

      let to_field_elements
          { pairing_marlin_acc=
              { opening_check= {r_f_minus_r_v_plus_rz_pi; r_pi}
              ; degree_bound_checks=
                  {shifted_accumulator; unshifted_accumulators} }
          ; pairing_marlin_index
          ; old_bulletproof_challenges } ~g1:g1_to_field_elements =
        Array.concat
          [ index_to_field_elements ~g:g1_to_field_elements pairing_marlin_index
          ; Vector.to_array old_bulletproof_challenges
            |> Array.concat_map ~f:Vector.to_array
          ; Array.concat_map
              (Array.append
                 [|r_f_minus_r_v_plus_rz_pi; r_pi; shifted_accumulator|]
                 (Vector.to_array unshifted_accumulators))
              ~f:(fun g -> Array.of_list (g1_to_field_elements g)) ]

      open Snarky.H_list

      let to_hlist
          {pairing_marlin_index; pairing_marlin_acc; old_bulletproof_challenges}
          =
        [pairing_marlin_index; pairing_marlin_acc; old_bulletproof_challenges]

      let of_hlist
          ([ pairing_marlin_index
           ; pairing_marlin_acc
           ; old_bulletproof_challenges ] :
            (unit, _) t) =
        {pairing_marlin_index; pairing_marlin_acc; old_bulletproof_challenges}

      let typ g1 chal ~length =
        Snarky.Typ.of_hlistable
          [ g1 |> Abc.typ |> Matrix_evals.typ
          ; Pairing_marlin_types.Accumulator.typ g1
          ; Vector.typ chal length ]
          ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist
          ~value_to_hlist:to_hlist ~value_of_hlist:of_hlist
    end

    type ('challenge, 'fp, 'bool, 'fq, 'me_only, 'digest) t =
      { deferred_values: ('challenge, 'fp, 'fq) Deferred_values.t
      ; was_base_case: 'bool
      ; sponge_digest_before_evaluations: 'digest
            (* Not needed by other proof system *)
      ; me_only: 'me_only }
    [@@deriving bin_io]

    open Snarky.H_list

    let to_hlist
        { deferred_values
        ; was_base_case
        ; sponge_digest_before_evaluations
        ; me_only } =
      [ deferred_values
      ; was_base_case
      ; sponge_digest_before_evaluations
      ; me_only ]

    let of_hlist
        ([ deferred_values
         ; was_base_case
         ; sponge_digest_before_evaluations
         ; me_only ] :
          (unit, _) t) =
      { deferred_values
      ; was_base_case
      ; sponge_digest_before_evaluations
      ; me_only }

    let typ chal fp bool fq me_only digest =
      Snarky.Typ.of_hlistable
        [Deferred_values.typ chal fp fq; bool; digest; me_only]
        ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist ~value_to_hlist:to_hlist
        ~value_of_hlist:of_hlist
  end

  module Pass_through = struct
    type ('g, 's, 'sg) t =
      {app_state: 's; dlog_marlin_index: 'g Abc.t Matrix_evals.t; sg: 'sg}

    let to_field_elements {app_state; dlog_marlin_index; sg}
        ~app_state:app_state_to_field_elements ~g =
      Array.concat
        [ index_to_field_elements ~g dlog_marlin_index
        ; Array.of_list (List.concat_map ~f:g (Vector.to_list sg))
        ; app_state_to_field_elements app_state ]

    let to_field_elements_without_index {app_state; dlog_marlin_index= _; sg}
        ~app_state:app_state_to_field_elements ~g =
      Array.concat
        [ Array.of_list (List.concat_map ~f:g (Vector.to_list sg))
        ; app_state_to_field_elements app_state ]

    open Snarky.H_list

    let to_hlist {app_state; dlog_marlin_index; sg} =
      [app_state; dlog_marlin_index; sg]

    let of_hlist ([app_state; dlog_marlin_index; sg] : (unit, _) t) =
      {app_state; dlog_marlin_index; sg}

    let typ g s branching =
      Snarky.Typ.of_hlistable
        [s; Matrix_evals.typ (Abc.typ g); Vector.typ g branching]
        ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist ~value_to_hlist:to_hlist
        ~value_of_hlist:of_hlist
  end

  module Statement = struct
    type ('challenge, 'fp, 'bool, 'fq, 'me_only, 'digest, 'pass_through) t =
      { proof_state:
          ('challenge, 'fp, 'bool, 'fq, 'me_only, 'digest) Proof_state.t
      ; pass_through: 'pass_through }
    [@@deriving bin_io]

    let spec =
      let open Spec in
      Struct
        [ Vector (B Bool, Nat.N1.n)
        ; Vector (B Field, Nat.N3.n)
        ; Vector (B Challenge, Nat.N9.n)
        ; Vector (B Digest, Nat.N3.n) ]

    let to_data
        { proof_state=
            { deferred_values=
                { xi
                ; r
                ; r_xi_sum
                ; marlin=
                    { sigma_2
                    ; sigma_3
                    ; alpha
                    ; eta_a
                    ; eta_b
                    ; eta_c
                    ; beta_1
                    ; beta_2
                    ; beta_3 } }
            ; was_base_case
            ; sponge_digest_before_evaluations
            ; me_only }
        ; pass_through } =
      let open Vector in
      let fp = [sigma_2; sigma_3; r_xi_sum] in
      let challenge =
        [xi; r; alpha; eta_a; eta_b; eta_c; beta_1; beta_2; beta_3]
      in
      let bool = [was_base_case] in
      let digest = [sponge_digest_before_evaluations; me_only; pass_through] in
      Hlist.HlistId.[bool; fp; challenge; digest]

    let of_data Hlist.HlistId.[bool; fp; challenge; digest] =
      let open Vector in
      let [sigma_2; sigma_3; r_xi_sum] = fp in
      let [xi; r; alpha; eta_a; eta_b; eta_c; beta_1; beta_2; beta_3] =
        challenge
      in
      let [was_base_case] = bool in
      let [sponge_digest_before_evaluations; me_only; pass_through] = digest in
      { proof_state=
          { was_base_case
          ; deferred_values=
              { xi
              ; r
              ; r_xi_sum
              ; marlin=
                  { sigma_2
                  ; sigma_3
                  ; alpha
                  ; eta_a
                  ; eta_b
                  ; eta_c
                  ; beta_1
                  ; beta_2
                  ; beta_3 } }
          ; sponge_digest_before_evaluations
          ; me_only }
      ; pass_through }
  end
end

module Pairing_based = struct
  module Marlin_polys = Vector.Nat.N20

  module Openings = struct
    module Evaluations = struct
      module By_point = struct
        type 'fq t = {beta_1: 'fq; beta_2: 'fq; beta_3: 'fq; g_challenge: 'fq}
      end

      type 'fq t = ('fq By_point.t, Marlin_polys.n Vector.s) Vector.t
    end

    module Bulletproof = struct
      include Dlog_marlin_types.Openings.Bulletproof

      module Advice = struct
        (* This is data that can be computed in linear time from the above plus the statement.
        
          It doesn't need to be sent on the wire, but it does need to be provided to the verifier
        *)
        type ('fq, 'g) t = {b: 'fq}

        open Snarky.H_list

        let to_hlist {b} = [b]

        let of_hlist ([b] : (unit, _) t) = {b}

        let typ fq g =
          let open Snarky.Typ in
          of_hlistable [fq] ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist
            ~value_to_hlist:to_hlist ~value_of_hlist:of_hlist
      end
    end

    type ('fq, 'g) t =
      {evaluations: 'fq Evaluations.t; proof: ('fq, 'g) Bulletproof.t}
  end

  module Proof_state = struct
    module Deferred_values = struct
      module Marlin = Dlog_based.Proof_state.Deferred_values.Marlin

      type ('challenge, 'fq, 'bulletproof_challenges) t =
        { marlin: ('challenge, 'fq) Marlin.t
        ; combined_inner_product: 'fq
        ; xi: 'challenge (* 128 bits *)
        ; r: 'challenge (* 128 bits *)
        ; bulletproof_challenges: 'bulletproof_challenges
        ; b: 'fq }
      [@@deriving bin_io]
    end

    module Pass_through = Dlog_based.Proof_state.Me_only
    module Me_only = Dlog_based.Pass_through

    let t =
      let open Spec in
      Struct [B Field; B Bool; Struct [Vector (B Digest, Nat.N10.n); B Field]]

    module Per_proof = struct
      type ('challenge, 'fq, 'bulletproof_challenges, 'digest) t =
        { deferred_values:
            ('challenge, 'fq, 'bulletproof_challenges) Deferred_values.t
        ; sponge_digest_before_evaluations: 'digest }
      [@@deriving bin_io]

      let spec bp_log2 =
        let open Spec in
        Struct
          [ Vector (B Field, Nat.N4.n)
          ; Vector (B Digest, Nat.N1.n)
          ; Vector (B Challenge, Nat.N9.n)
          ; Vector (B Bulletproof_challenge, bp_log2) ]

      let to_data
          { deferred_values=
              { xi
              ; r
              ; bulletproof_challenges
              ; b
              ; combined_inner_product
              ; marlin=
                  { sigma_2
                  ; sigma_3
                  ; alpha
                  ; eta_a
                  ; eta_b
                  ; eta_c
                  ; beta_1
                  ; beta_2
                  ; beta_3 } }
          ; sponge_digest_before_evaluations } =
        let open Vector in
        let fq = [sigma_2; sigma_3; combined_inner_product; b] in
        let challenge =
          [alpha; eta_a; eta_b; eta_c; beta_1; beta_2; beta_3; xi; r]
        in
        let digest = [sponge_digest_before_evaluations] in
        let open Hlist.HlistId in
        [fq; digest; challenge; bulletproof_challenges]

      open Hlist.HlistId

      let of_data
          [ Vector.[sigma_2; sigma_3; combined_inner_product; b]
          ; Vector.[sponge_digest_before_evaluations]
          ; Vector.[alpha; eta_a; eta_b; eta_c; beta_1; beta_2; beta_3; xi; r]
          ; bulletproof_challenges ] =
        { deferred_values=
            { xi
            ; r
            ; bulletproof_challenges
            ; b
            ; combined_inner_product
            ; marlin=
                { sigma_2
                ; sigma_3
                ; alpha
                ; eta_a
                ; eta_b
                ; eta_c
                ; beta_1
                ; beta_2
                ; beta_3 } }
        ; sponge_digest_before_evaluations }
    end

    type ('unfinalized_proofs, 'me_only, 'bool) t =
      { unfinalized_proofs: 'unfinalized_proofs
      ; me_only: 'me_only
      ; was_base_case: 'bool }
    [@@deriving bin_io]

    let spec unfinalized_proofs me_only =
      let open Spec in
      Struct [unfinalized_proofs; me_only; B Bool]

    open Hlist.HlistId

    let to_data {unfinalized_proofs; me_only; was_base_case} =
      [ Vector.map unfinalized_proofs ~f:Per_proof.to_data
      ; me_only
      ; was_base_case ]

    let of_data [unfinalized_proofs; me_only; was_base_case] =
      { unfinalized_proofs= Vector.map unfinalized_proofs ~f:Per_proof.of_data
      ; me_only
      ; was_base_case }

    let typ impl branching bp_log2 fq =
      spec (Vector (Per_proof.spec bp_log2, branching)) (B Spec.Digest)
      |> Spec.typ impl fq
      |> Snarky.Typ.transport ~there:to_data ~back:of_data
      |> Snarky.Typ.transport_var ~there:to_data ~back:of_data
  end

  module Statement = struct
    type ('unfinalized_proofs, 'me_only, 'bool, 'pass_through) t =
      { proof_state: ('unfinalized_proofs, 'me_only, 'bool) Proof_state.t
      ; pass_through: 'pass_through }
    [@@deriving bin_io]

    (* Basic types:
       - Boolean
       - Digest
       - Challenge
       - Field

       Compound
       - array
       - vector
    *)

    (*  Need:
        - a "type" for the data
          (essentially a big product type of all the basic inputs in order)
        - a function from the source type to that type
        - a typ value for that type
        - a funciton for laying it out into a bunch of bitstring/field elts

        want to simultaneously compute given (x : input)

        type data_var data_value

        val typ : (data_var, data_value)

        val pack : input -> data_var
    *)

    let to_data
        { proof_state= {unfinalized_proofs; me_only; was_base_case}
        ; pass_through } =
      let open Hlist.HlistId in
      [ Vector.map unfinalized_proofs ~f:Proof_state.Per_proof.to_data
      ; me_only
      ; was_base_case
      ; pass_through ]

    let of_data
        Hlist.HlistId.
          [unfinalized_proofs; me_only; was_base_case; pass_through] =
      { proof_state=
          { unfinalized_proofs=
              Vector.map unfinalized_proofs ~f:Proof_state.Per_proof.of_data
          ; me_only
          ; was_base_case }
      ; pass_through }

    let spec branching bp_log2 =
      let open Spec in
      Struct
        [ Vector (Proof_state.Per_proof.spec bp_log2, branching)
        ; B Digest
        ; B Bool
        ; Vector (B Digest, branching) ]
  end
end