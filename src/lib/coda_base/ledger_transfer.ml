open Core_kernel

module type Base_ledger_intf =
  Merkle_ledger.Base_ledger_intf.S
  with type account := Account.t
   and type key := Signature_lib.Public_key.Compressed.t
   and type token_id := Token_id.t
   and type token_id_set := Token_id.Set.t
   and type account_id := Account_id.t
   and type account_id_set := Account_id.Set.t
   and type hash := Ledger_hash.t
   and type root_hash := Ledger_hash.t

module Make (Source : Base_ledger_intf) (Dest : Base_ledger_intf) : sig
  val transfer_accounts : src:Source.t -> dest:Dest.t -> Dest.t Or_error.t
end = struct
  let transfer_accounts ~src ~dest =
    let sorted =
      Source.foldi src ~init:[] ~f:(fun addr acc account ->
          (addr, account) :: acc )
      |> List.sort ~compare:(fun (addr1, _) (addr2, _) ->
             Source.Addr.compare addr1 addr2 )
    in
    List.iter sorted ~f:(fun (_addr, account) ->
        let key = Account.identifier account in
        ignore (Dest.get_or_create_account_exn dest key account) ) ;
    let src_hash = Source.merkle_root src in
    let dest_hash = Dest.merkle_root dest in
    if not (Ledger_hash.equal src_hash dest_hash) then
      Or_error.errorf
        "Merkle roots differ after transfer: expected %s, actual %s"
        (Ledger_hash.to_string src_hash)
        (Ledger_hash.to_string dest_hash)
    else Ok dest
end
