type t = bytes

let[@inline] to_bytes self = self

let dummy : t = Bytes.make 16 '\x00'

let default_create_function () : t =
  let b = Rand_bytes.rand_bytes_16 () in
  assert (Bytes.length b = 16);
  (* make sure the identifier is not all 0, which is a dummy identifier. *)
  Bytes.set b 0 (Char.unsafe_chr (Char.code (Bytes.get b 0) lor 1));
  b

open struct
  let create_fun_ = ref default_create_function
end

let[@inline] create () =
  let id = !create_fun_ () in
  assert (Bytes.length id = 16);
  id

let set_create_function f = create_fun_ := f

let[@inline] of_bytes b =
  if Bytes.length b = 16 then
    b
  else
    invalid_arg "trace ID must be 16 bytes in length"

(* dark magic, woo. We have an [assert] below to do the bound checks once *)
external unsafe_b_get64 : bytes -> int -> int64 = "%caml_bytes_get64u"

let[@inline] is_zero (self : t) : bool =
  (* try to reduce branches *)
  assert (Bytes.length self = 16);
  let n1 = unsafe_b_get64 self 0 in
  let n2 = unsafe_b_get64 self 8 in
  n1 = 0L && n2 = 0L

let[@inline] is_valid self = not (is_zero self)

let to_hex = Util_bytes_.bytes_to_hex

let to_hex_into = Util_bytes_.bytes_to_hex_into

let[@inline] of_hex s = of_bytes (Util_bytes_.bytes_of_hex s)

let[@inline] of_hex_substring s off =
  of_bytes (Util_bytes_.bytes_of_hex_substring s off 32)

let pp fmt t = Format.fprintf fmt "%s" (to_hex t)

let compare = Bytes.compare

module Map = Map.Make (struct
  type nonrec t = t

  let compare = compare
end)

let k_trace_id : t Hmap.key = Hmap.Key.create ()
