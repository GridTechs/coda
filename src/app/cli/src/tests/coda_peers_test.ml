open Core
open Async

let name = "coda-peers-test"

let runtime_config =
  lazy
    ( (* test_postake_split_snarkless *)
      {json|
  { "daemon":
      { "txpool_max_size": 3000 }
  , "genesis":
      { "k": 24
      , "delta": 3
      , "genesis_state_timestamp": "2019-01-30 12:00:00-08:00" }
  , "proof":
      { "level": "check"
      , "c": 8
      , "ledger_depth": 30
      , "work_delay": 1
      , "block_window_duration_ms": 10000
      , "transaction_capacity": {"2_to_the": 2}
      , "coinbase_amount": "20"
      , "account_creation_fee": "1" }
  , "ledger": { "name": "test_split_two_stakers" } }
      |json}
    |> Yojson.Safe.from_string |> Runtime_config.of_yojson
    |> Result.ok_or_failwith )

let main () =
  let logger = Logger.create () in
  let%bind precomputed_values, runtime_config =
    Genesis_ledger_helper.init_from_config_file ~logger ~may_generate:false
      ~proof_level:None
      (Lazy.force runtime_config)
    >>| Or_error.ok_exn
  in
  let consensus_constants = precomputed_values.consensus_constants in
  let%bind program_dir = Unix.getcwd () in
  let n = 3 in
  let block_production_interval =
    consensus_constants.block_window_duration_ms |> Block_time.Span.to_ms
    |> Int64.to_int_exn
  in
  let acceptable_delay =
    Time.Span.of_ms
      ( block_production_interval
        * Unsigned.UInt32.to_int consensus_constants.delta
      |> Float.of_int )
  in
  let work_selection_method =
    Cli_lib.Arg_type.Work_selection_method.Sequence
  in
  Coda_processes.init () ;
  let%bind configs =
    Coda_processes.local_configs n ~program_dir ~block_production_interval
      ~acceptable_delay ~chain_id:name ~snark_worker_public_keys:None
      ~block_production_keys:(Fn.const None) ~work_selection_method
      ~trace_dir:(Unix.getenv "CODA_TRACING")
      ~max_concurrent_connections:None ~runtime_config
  in
  let%bind workers = Coda_processes.spawn_local_processes_exn configs in
  let _, expected_peers = (List.hd_exn configs).net_configs in
  let%bind _ = after (Time.Span.of_sec 60.) in
  let%bind () =
    Deferred.all_unit
      (List.map2_exn workers expected_peers ~f:(fun worker expected_peers ->
           let expected_peer_ports =
             List.map expected_peers ~f:(fun p -> p.libp2p_port)
           in
           let%map peers = Coda_process.peers_exn worker in
           Logger.debug logger ~module_:__MODULE__ ~location:__LOC__
             ~metadata:
               [ ( "peers"
                 , `List (List.map ~f:Network_peer.Peer.to_yojson peers) )
               ; ( "expected_ports"
                 , `List (List.map ~f:(fun n -> `Int n) expected_peer_ports) )
               ]
             "got peers $peers $expected_ports" ;
           let module S = Int.Set in
           assert (
             S.is_subset
               ~of_:
                 (S.of_list
                    ( peers
                    |> List.map ~f:(fun p -> p.Network_peer.Peer.libp2p_port)
                    ))
               (S.of_list expected_peer_ports) ) ))
  in
  Deferred.List.iter workers ~f:(Coda_process.disconnect ~logger)

let command =
  Command.async
    ~summary:"integration test with two peers spawned alongside a seed"
    (Command.Param.return main)
