include Generic_io.Direct_style

let sleep_s = Thread.delay

let[@inline] spawn f = ignore (Util_thread.start_bg_thread f : Thread.t)

(* background threads are already abandoned at process exit *)
let[@inline] spawn_daemon f = spawn f
