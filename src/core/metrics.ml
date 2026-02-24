(** Metrics.

    See
    {{:https://opentelemetry.io/docs/reference/specification/overview/#metric-signal}
     the spec} *)

open Common_
open Proto
open Proto.Metrics

type t = Metrics.metric
(** A single metric, measuring some time-varying quantity or statistical
    distribution. It is composed of one or more data points that have precise
    values and time stamps. Each distinct metric should have a distinct name. *)

let pp = Proto.Metrics.pp_metric

(** Number data point, as a float *)
let float ?start_time_unix_nano ?(attrs = []) ~(now : Timestamp_ns.t)
    (d : float) : number_data_point =
  let attributes = attrs |> List.map Key_value.conv in
  make_number_data_point ?start_time_unix_nano ~time_unix_nano:now ~attributes
    ~value:(As_double d) ()

(** Number data point, as an int *)
let int ?start_time_unix_nano ?(attrs = []) ~(now : Timestamp_ns.t) (i : int) :
    number_data_point =
  let attributes = attrs |> List.map Key_value.conv in
  make_number_data_point ?start_time_unix_nano ~time_unix_nano:now ~attributes
    ~value:(As_int (Int64.of_int i))
    ()

(** Aggregation of a scalar metric, always with the current value *)
let gauge ~name ?description ?unit_ (l : number_data_point list) : t =
  let data = Gauge (make_gauge ~data_points:l ()) in
  make_metric ~name ?description ?unit_ ~data ()

type aggregation_temporality = Metrics.aggregation_temporality =
  | Aggregation_temporality_unspecified
  | Aggregation_temporality_delta
  | Aggregation_temporality_cumulative

(** Sum of all reported measurements over a time interval *)
let sum ~name ?description ?unit_
    ?(aggregation_temporality = Aggregation_temporality_cumulative)
    ?is_monotonic (l : number_data_point list) : t =
  let data =
    Sum (make_sum ~data_points:l ?is_monotonic ~aggregation_temporality ())
  in
  make_metric ~name ?description ?unit_ ~data ()

type histogram_data_point = Metrics.histogram_data_point

(** Histogram data
    @param count number of values in population (non negative)
    @param sum sum of values in population (0 if count is 0)
    @param now the timestamp for this data point
    @param bucket_counts
      count value of histogram for each bucket. Sum of the counts must be equal
      to [count]. length must be [1+length explicit_bounds] (unless both have
      length 0)
    @param explicit_bounds strictly increasing list of bounds for the buckets *)
let histogram_data_point ?start_time_unix_nano ?(attrs = []) ?(exemplars = [])
    ~explicit_bounds ?sum ~(now : Timestamp_ns.t) ~bucket_counts ~count () :
    histogram_data_point =
  let attributes = attrs |> List.map Key_value.conv in
  make_histogram_data_point ?start_time_unix_nano ~time_unix_nano:now
    ~attributes ~exemplars ~bucket_counts ~explicit_bounds ~count ?sum ()

let histogram ~name ?description ?unit_ ?aggregation_temporality
    (l : histogram_data_point list) : t =
  let data =
    Histogram (make_histogram ~data_points:l ?aggregation_temporality ())
  in
  make_metric ~name ?description ?unit_ ~data ()

let add_attrs (m : t) (attrs : Key_value.t list) : unit =
  let attrs = List.map Key_value.conv attrs in
  match m.data with
  | None -> ()
  | Some (Gauge g) ->
    List.iter
      (fun (dp : number_data_point) ->
        number_data_point_set_attributes dp (attrs @ dp.attributes))
      g.data_points
  | Some (Sum s) ->
    List.iter
      (fun (dp : number_data_point) ->
        number_data_point_set_attributes dp (attrs @ dp.attributes))
      s.data_points
  | Some (Histogram h) ->
    List.iter
      (fun (dp : histogram_data_point) ->
        histogram_data_point_set_attributes dp (attrs @ dp.attributes))
      h.data_points
  | Some (Exponential_histogram eh) ->
    List.iter
      (fun (dp : exponential_histogram_data_point) ->
        exponential_histogram_data_point_set_attributes dp
          (attrs @ dp.attributes))
      eh.data_points
  | Some (Summary s) ->
    List.iter
      (fun (dp : summary_data_point) ->
        summary_data_point_set_attributes dp (attrs @ dp.attributes))
      s.data_points

(* TODO: exponential history *)
(* TODO: summary *)
(* TODO: exemplar *)
