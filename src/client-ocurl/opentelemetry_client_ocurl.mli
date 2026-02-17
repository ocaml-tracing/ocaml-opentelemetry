(*
   TODO: more options from
   https://opentelemetry.io/docs/reference/specification/protocol/exporter/
   *)

module Config = Config

val consumer :
  ?config:Config.t -> unit -> Opentelemetry_client.Consumer.any_signal_l_builder
(** Consumer that pulls from a queue *)

val create_exporter : ?config:Config.t -> unit -> Opentelemetry.Exporter.t
(** @since NEXT_RELEASE *)

val create_backend : ?config:Config.t -> unit -> Opentelemetry.Exporter.t
[@@deprecated "use create_exporter"]

val setup : ?config:Config.t -> ?enable:bool -> unit -> unit
(** Setup endpoint. This modifies {!Opentelemetry.Collector.backend}.
    @param enable
      actually setup the backend (default true). This can be used to
      enable/disable the setup depending on CLI arguments or environment.
    @param config configuration to use
    @param stop
      an atomic boolean. When it becomes true, background threads will all stop
      after a little while. *)

val remove_exporter : unit -> unit
(** @since NEXT_RELEASE *)

val remove_backend : unit -> unit
[@@deprecated "use remove_exporter"]
(** @since 0.12 *)

val with_setup :
  ?after_shutdown:(Opentelemetry.Exporter.t -> unit) ->
  ?config:Config.t ->
  ?enable:bool ->
  unit ->
  (unit -> 'a) ->
  'a
(** [with_setup () f] is like [setup(); f()] but takes care of cleaning up after
    [f()] returns See {!setup} for more details. *)
