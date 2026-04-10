(** Any kind of lists of signals *)

open Common_

type t =
  | Spans of Span.t list
  | Metrics of Metrics.t list
  | Logs of Log_record.t list

open struct
  let pp_sep out () = Format.fprintf out ";@ "

  let pp_list ppx out l =
    Format.fprintf out "[@[%a@]]" (Format.pp_print_list ~pp_sep ppx) l
end

let pp out = function
  | Spans s -> pp_list Proto.Trace.pp_span out s
  | Metrics m -> pp_list Proto.Metrics.pp_metric out m
  | Logs l -> pp_list Proto.Logs.pp_log_record out l

let length = function
  | Spans l -> List.length l
  | Metrics l -> List.length l
  | Logs l -> List.length l

let of_logs_or_empty = function
  | [] -> []
  | l -> [ Logs l ]

let of_metrics_or_empty = function
  | [] -> []
  | l -> [ Metrics l ]

let of_spans_or_empty = function
  | [] -> []
  | l -> [ Spans l ]
