type t = int

let none = 0

let sampled_bit = 0x01

let random_bit = 0x02

let sampled = sampled_bit

let default = sampled_bit lor random_bit

external int_of_bool : bool -> int = "%identity"

let[@inline] make ~sampled ~random =
  int_of_bool sampled lor (int_of_bool random lsl 1)

let[@inline] of_int i = i land (sampled_bit lor random_bit)

let[@inline] to_int self = self

let[@inline] of_int32 i = of_int (Int32.to_int i)

let[@inline] to_int32 self = Int32.of_int self

let[@inline] is_sampled self = self land sampled_bit <> 0

let[@inline] is_random self = self land random_bit <> 0

let[@inline] set_ bit b self =
  if b then
    self lor bit
  else
    self land lnot bit

let[@inline] with_sampled b self = set_ sampled_bit b self

let[@inline] with_random b self = set_ random_bit b self

let pp out self = Format.fprintf out "%02x" self
