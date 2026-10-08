(** Head sampling of traces.

    Ratio sampling follows the OTEL consistent probability scheme: a trace is
    sampled iff the lower 56 bits (7 bytes) of its trace ID are [>=] the
    threshold derived from the ratio, which is recorded as [ot=th:<hex>] in
    tracestate.

    {{:https://opentelemetry.io/docs/specs/otel/trace/tracestate-probability-sampling/}
     spec}
    @since NEXT_RELEASE *)

type t

val always_on : t

val always_off : t

val trace_id_ratio : float -> t
(** Sample a ratio [p] (clamped to [[0, 1]]) of traces, by trace ID *)

val parent_based : t -> t
(** [parent_based root] follows the parent's sampled bit, and uses [root] for
    root spans *)

(** Sampling status of parent, if any *)
type parent =
  | No_parent
  | Parent_sampled
  | Parent_not_sampled

val pp : Format.formatter -> t -> unit

val default : t
(** [parent_based always_on], the OTEL spec default *)

val of_env : unit -> t
(** From [OTEL_TRACES_SAMPLER] (always_on, always_off, traceidratio,
    parentbased_always_on, parentbased_traceidratio) and
    [OTEL_TRACES_SAMPLER_ARG] (ratio, default 1.0). {!default} if unset or
    unknown. *)

val get : unit -> t option
(** Current global sampler. [None] (initial value) samples everything and leaves
    tracestate untouched. Client setups install {!of_env} by default. *)

val set : t option -> unit

val decide :
  t -> parent:parent -> trace_state:string -> Trace_id.t -> bool * string
(** [decide sampler ~parent ~trace_state trace_id] is [(sampled, trace_state')]
    where [trace_state] is the parent's (or an explicit) tracestate *)

val decide_current :
  parent:parent -> trace_state:string -> Trace_id.t -> bool * string
(** {!decide} with the current global sampler, counted in {!self_metrics} *)

val self_metrics : now:Timestamp_ns.t -> Metrics.t list
(** [otel.sdk.span.sampled] and [otel.sdk.span.not_sampled] *)

(**/**)

module Private_ : sig
  val threshold_of_ratio : float -> int64
  (** [round ((1 - p) * 2^56)], [p] clamped to [[0, 1]] *)

  val randomness : Trace_id.t -> int64
  (** Lower 56 bits of the trace ID (bytes 9..15, big-endian) *)
end

(**/**)
