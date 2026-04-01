(** Emergency diagnostic logger for the OpenTelemetry SDK itself.

    Bypasses the OTEL pipeline entirely. Defaults to silently discarding all
    messages. Use {!to_stderr} or set {!logger} to enable output.

    Usage:
    {[
      Self_debug.log Info (fun () -> Printf.sprintf "batch flushed %d items" n)
    ]}.

    @since 0.90 *)

type level =
  | Debug
  | Info
  | Warning
  | Error

type logger = level -> (unit -> string) -> unit
(** A logger, takes a level and a (lazy) message, and maybe emit the message *)

val logger : logger ref
(** The current log sink. Replace to redirect output. Default: no-op. *)

val string_of_level : level -> string
(** String representation of a level. *)

val log : level -> (unit -> string) -> unit
(** [log level mk_msg] emits a diagnostic message if the current logger is
    active. [mk_msg] is called lazily — only if the message will be emitted. *)

val to_stderr : ?min_level:level -> unit -> unit
(** Install a stderr logger. Messages below [min_level] (default: [Warning]) are
    suppressed. This is useful to help debug problems with this library itself
    (e.g. when nothing is emitted but the user expects something to be emitted)
*)
