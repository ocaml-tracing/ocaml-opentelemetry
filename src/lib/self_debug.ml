type level =
  | Debug
  | Info
  | Warning
  | Error

type logger = level -> (unit -> string) -> unit

let logger : logger ref = ref (fun _ _ -> ())

let[@inline] log level f = !logger level f

let string_of_level = function
  | Debug -> "debug"
  | Info -> "info"
  | Warning -> "warning"
  | Error -> "error"

open struct
  let[@inline] int_of_level_ = function
    | Debug -> 0
    | Info -> 1
    | Warning -> 2
    | Error -> 3
end

let level_above ~min_level level : bool =
  int_of_level_ level >= int_of_level_ min_level

let to_stderr ?(min_level = Warning) () : unit =
  logger :=
    fun level mk_msg ->
      if level_above ~min_level level then (
        let msg = mk_msg () in
        Printf.eprintf "[otel:%s] %s\n%!" (string_of_level level) msg
      )
