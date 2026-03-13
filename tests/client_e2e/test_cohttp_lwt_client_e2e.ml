open Clients_e2e_lib

(* NOTE: This port must be different from that used by other integration tests,
   to prevent socket binding clashes. *)
let port = 4338

let url = Printf.sprintf "http://localhost:%d" port

let () =
  Clients_e2e_lib.run_tests ~port
    [
      (* TODO: Running with batch sizes of 1 causes deadlocks *)
      (* ( "emit1_cohttp", *)
      (*   { *)
      (*     ipv6 = false; *)
      (*     jobs = 1; *)
      (*     iterations = 1; *)
      (*     batch_traces = 1; *)
      (*     batch_metrics = 1; *)
      (*     batch_logs = 1; *)
      (*   } ); *)
      ( "emit1_cohttp",
        {
          url;
          jobs = 1;
          procs = 1;
          n_outer = 1;
          iterations = 1;
          batch_traces = 2;
          batch_metrics = 2;
          batch_logs = 2;
        } );
      ( "emit1_cohttp",
        {
          url;
          jobs = 3;
          procs = 1;
          n_outer = 1;
          iterations = 1;
          batch_traces = 400;
          batch_metrics = 3;
          batch_logs = 400;
        } );
      ( "emit1_cohttp",
        {
          url;
          jobs = 3;
          procs = 1;
          n_outer = 5;
          iterations = 1;
          batch_traces = 400;
          batch_metrics = 3;
          batch_logs = 400;
        } );
    ]
