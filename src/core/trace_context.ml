(** Implementation of the W3C Trace Context spec

    https://www.w3.org/TR/trace-context/ *)

(** The traceparent header
    https://www.w3.org/TR/trace-context/#traceparent-header *)
module Traceparent = struct
  let name = "traceparent"

  (** Parse the value of the traceparent header.

      The values are of the form:

      {[
        { version } - { trace_id } - { parent_id } - { flags }
      ]}

      For example:

      {[
        00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
      ]}

      Only the known bits of [{flags}] are kept (see {!Trace_flags}). The result
      is a {!Span_ctx.t} carrying [trace_state] (the [tracestate] header value).
      @since NEXT_RELEASE returns a {!Span_ctx.t} *)
  let of_value ?(trace_state = "") str : (Span_ctx.t, string) result =
    match Span_ctx.of_w3c_trace_context (Bytes.unsafe_of_string str) with
    | Ok sp ->
      let span_ctx =
        Span_ctx.make ~trace_flags:(Span_ctx.trace_flags sp) ~trace_state
          ~trace_id:(Span_ctx.trace_id sp) ~parent_id:(Span_ctx.parent_id sp) ()
      in
      Ok span_ctx
    | Error _ as e -> e

  (** @since NEXT_RELEASE takes a mandatory [~trace_flags] instead of

      [?sampled] *)
  let to_value ~(trace_flags : Trace_flags.t) ~(trace_id : Trace_id.t)
      ~(parent_id : Span_id.t) () : string =
    let span_ctx = Span_ctx.make ~trace_flags ~trace_id ~parent_id () in
    Bytes.unsafe_to_string @@ Span_ctx.to_w3c_trace_context span_ctx
end

(** The tracestate header, and the OpenTelemetry [ot=th:<hex>] threshold
    https://www.w3.org/TR/trace-context/#tracestate-header
    https://opentelemetry.io/docs/specs/otel/trace/tracestate-probability-sampling/
    @since NEXT_RELEASE *)
module Tracestate = struct
  let name = "tracestate"

  open struct
    let members (s : string) : string list =
      String.split_on_char ',' s |> List.map String.trim
      |> List.filter (fun m -> m <> "")

    let[@inline] has_ot (m : string) : bool =
      String.length m >= 3 && m.[0] = 'o' && m.[1] = 't' && m.[2] = '='

    let ot_value (m : string) : string option =
      if has_ot m then
        Some (String.sub m 3 (String.length m - 3))
      else
        None

    let is_th (kv : string) = String.length kv >= 3 && String.sub kv 0 3 = "th:"
  end

  (** 56-bit (7 bytes) rejection threshold from [ot=th:<hex>], if present and
      valid. [<hex>] has 1 to 14 digits, implicitly padded with trailing zeros.
  *)
  let get_ot_th (s : string) : int64 option =
    match List.find_map ot_value (members s) with
    | None -> None
    | Some v ->
      (match List.find_opt is_th (String.split_on_char ';' v) with
      | None -> None
      | Some kv ->
        let hex = String.sub kv 3 (String.length kv - 3) in
        let n = String.length hex in
        if n = 0 || n > 14 then
          None
        else (
          match Int64.of_string_opt ("0x" ^ hex) with
          | Some th -> Some (Int64.shift_left th (4 * (14 - n)))
          | None -> None
        ))

  (** Set [th] in the [ot] member, which is moved first. Other [ot] sub-keys and
      other members are kept in order. *)
  let set_ot_th (s : string) (th : int64) : string =
    let th =
      let hex = Printf.sprintf "%014Lx" th in
      let n = ref (String.length hex) in
      while !n > 1 && hex.[!n - 1] = '0' do
        decr n
      done;
      "th:" ^ String.sub hex 0 !n
    in
    let ms = members s in
    let ot_rest =
      match List.find_map ot_value ms with
      | None -> []
      | Some v ->
        String.split_on_char ';' v
        |> List.filter (fun kv -> kv <> "" && not (is_th kv))
    in
    let others =
      if List.exists has_ot ms then
        List.filter (fun m -> not (has_ot m)) ms
      else
        ms
    in
    let others =
      if List.length others > 31 then
        List.filteri (fun i _ -> i < 31) others
      else
        others
    in
    String.concat "," (("ot=" ^ String.concat ";" (th :: ot_rest)) :: others)
end

(** Headers to propagate this context: [traceparent], and [tracestate] if
    non-empty.
    @since NEXT_RELEASE *)
let headers_of_span_ctx (ctx : Span_ctx.t) : (string * string) list =
  let tp = Bytes.unsafe_to_string (Span_ctx.to_w3c_trace_context ctx) in
  match Span_ctx.trace_state ctx with
  | "" -> [ Traceparent.name, tp ]
  | ts -> [ Traceparent.name, tp; Tracestate.name, ts ]
