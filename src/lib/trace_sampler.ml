module Tracestate = Trace_context.Tracestate

type t =
  | Always_on
  | Always_off
  | Trace_id_ratio of float
  | Parent_based of t

let always_on = Always_on

let always_off = Always_off

let trace_id_ratio p = Trace_id_ratio p

let parent_based root = Parent_based root

type parent =
  | No_parent
  | Parent_sampled
  | Parent_not_sampled

let rec pp out = function
  | Always_on -> Format.fprintf out "always_on"
  | Always_off -> Format.fprintf out "always_off"
  | Trace_id_ratio p -> Format.fprintf out "traceidratio(%g)" p
  | Parent_based s -> Format.fprintf out "parentbased(%a)" pp s

let default = Parent_based Always_on

let of_env () : t =
  let ratio () =
    match Sys.getenv_opt "OTEL_TRACES_SAMPLER_ARG" with
    | None -> 1.
    | Some s ->
      (match float_of_string_opt s with
      | Some p when p >= 0. && p <= 1. -> p
      | _ ->
        Self_debug.log Warning (fun () ->
            Printf.sprintf "invalid OTEL_TRACES_SAMPLER_ARG %S, using 1.0" s);
        1.)
  in
  match Sys.getenv_opt "OTEL_TRACES_SAMPLER" with
  | None -> default
  | Some "always_on" -> Always_on
  | Some "always_off" -> Always_off
  | Some "traceidratio" -> Trace_id_ratio (ratio ())
  | Some "parentbased_always_on" -> Parent_based Always_on
  | Some "parentbased_always_off" -> Parent_based Always_off
  | Some "parentbased_traceidratio" -> Parent_based (Trace_id_ratio (ratio ()))
  | Some s ->
    Self_debug.log Warning (fun () ->
        Printf.sprintf
          "unknown OTEL_TRACES_SAMPLER %S, using parentbased_always_on" s);
    default

open struct
  let sampler : t option Atomic.t = Atomic.make None

  let n_sampled = Atomic.make 0

  let n_not_sampled = Atomic.make 0

  let max_threshold = Int64.shift_left 1L 56

  let random_bits_mask = Int64.pred max_threshold
end

let[@inline] get () = Atomic.get sampler

let[@inline] set s = Atomic.set sampler s

let warn_interval = Mtime.Span.(10 * s)

let default_on_non_random_parent : Trace_id.t -> unit =
  let limiter = Interval_limiter.create ~min_interval:warn_interval () in
  fun tid ->
    if Interval_limiter.make_attempt limiter then
      Printf.eprintf
        "opentelemetry: WARNING: trace %s does no have flag 0x2 (random) set.\n\
         We expect trace IDs to be random and marked as such in compliance \
         with W3C trace context lvl2.\n\
         %!"
        (Trace_id.to_hex tid)

open struct
  let on_non_random_parent : (Trace_id.t -> unit) Atomic.t =
    Atomic.make default_on_non_random_parent
end

let set_on_non_random_parent f = Atomic.set on_non_random_parent f

module Private_ = struct
  let threshold_of_ratio (p : float) : int64 =
    if p >= 1. then
      0L
    else if p <= 0. then
      max_threshold
    else
      Int64.of_float (Float.round (Float.ldexp (1. -. p) 56))

  let[@inline] randomness (tid : Trace_id.t) : int64 =
    Int64.logand (Bytes.get_int64_be (Trace_id.to_bytes tid) 8) random_bits_mask
end

let rec decide (self : t) ~(parent : parent) ~(random : bool)
    ~(trace_state : string) (tid : Trace_id.t) : bool * string =
  match self, parent with
  | Parent_based _, Parent_sampled -> true, trace_state
  | Parent_based _, Parent_not_sampled -> false, trace_state
  | Parent_based root, No_parent -> decide root ~parent ~random ~trace_state tid
  | Always_on, _ -> true, Tracestate.set_ot_th trace_state 0L
  | Always_off, _ -> false, trace_state
  | Trace_id_ratio p, _ ->
    (* we sample based on randomness of trace ID; check+warn if parent didn't
       set the random flag *)
    if parent <> No_parent && not random then
      (Atomic.get on_non_random_parent) tid;
    let th = Private_.threshold_of_ratio p in
    if Int64.compare (Private_.randomness tid) th >= 0 then
      (* sample, and publish sampling ratio in tracestate *)
      true, Tracestate.set_ot_th trace_state th
    else
      false, trace_state

let decide_current ~parent ~random ~trace_state (tid : Trace_id.t) :
    bool * string =
  let ((sampled, _) as r) =
    match get () with
    | Some s -> decide s ~parent ~random ~trace_state tid
    | None -> true, trace_state
  in
  Atomic.incr
    (if sampled then
       n_sampled
     else
       n_not_sampled);
  r

let self_metrics ~now : Metrics.t list =
  let m name a =
    Metrics.sum ~is_monotonic:true ~name [ Metrics.int ~now (Atomic.get a) ]
  in
  [
    m "otel.sdk.span.sampled" n_sampled;
    m "otel.sdk.span.not_sampled" n_not_sampled;
  ]
