open struct
  let spf = Printf.sprintf
end

let int_to_hex (i : int) =
  if i < 10 then
    Char.chr (i + Char.code '0')
  else
    Char.chr (i - 10 + Char.code 'a')

(** Hex digit for bits 4-7 of [n] *)
let[@inline] hex_upper_nibble (n : int) : char = int_to_hex ((n lsr 4) land 0xf)

(** Hex digit for bits 0-3 of [n] *)
let[@inline] hex_lower_nibble (n : int) : char = int_to_hex (n land 0xf)

let bytes_to_hex_into b res off : unit =
  for i = 0 to Bytes.length b - 1 do
    let n = Char.code (Bytes.get b i) in
    Bytes.set res ((2 * i) + off) (hex_upper_nibble n);
    Bytes.set res ((2 * i) + 1 + off) (hex_lower_nibble n)
  done

let bytes_to_hex (b : bytes) : string =
  let res = Bytes.create (2 * Bytes.length b) in
  bytes_to_hex_into b res 0;
  Bytes.unsafe_to_string res

let int_of_hex = function
  | '0' .. '9' as c -> Char.code c - Char.code '0'
  | 'a' .. 'f' as c -> 10 + Char.code c - Char.code 'a'
  | c -> raise (Invalid_argument (spf "invalid hex char: %C" c))

let bytes_of_hex_substring (s : string) off len =
  if len mod 2 <> 0 then
    raise (Invalid_argument "hex sequence must be of even length");
  let res = Bytes.make (len / 2) '\x00' in
  for i = 0 to (len / 2) - 1 do
    let n1 = int_of_hex (String.get s (off + (2 * i))) in
    let n2 = int_of_hex (String.get s (off + (2 * i) + 1)) in
    let n = (n1 lsl 4) lor n2 in
    Bytes.set res i (Char.chr n)
  done;
  res

let bytes_of_hex (s : string) : bytes =
  bytes_of_hex_substring s 0 (String.length s)

let bytes_non_zero (self : bytes) : bool =
  try
    for i = 0 to Bytes.length self - 1 do
      if Char.code (Bytes.unsafe_get self i) <> 0 then raise_notrace Exit
    done;
    false
  with Exit -> true
