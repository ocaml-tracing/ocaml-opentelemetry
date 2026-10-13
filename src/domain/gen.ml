let domain_4 =
  {|
let cpu_relax = ignore
let relax_loop : int -> unit = ignore
let is_main_domain () = true

module DLS = struct
  type 'a key = { init: unit -> 'a; value: 'a option ref }
  let new_key ?split_from_parent:_ init = { init; value = ref None }
  let get key =
    match !(key.value) with
    | Some value -> value
    | None ->
      let value = key.init () in
      key.value := Some value;
      value
  let set key value = key.value := Some value
end
  |}

let domain_5 =
  {|
let cpu_relax = Domain.cpu_relax
let relax_loop i =
  for _j = 1 to i do cpu_relax () done
let is_main_domain = Domain.is_main_domain
module DLS = struct
  type 'a key = 'a Domain.DLS.key
  let new_key ?split_from_parent init = Domain.DLS.new_key ?split_from_parent init
  let get = Domain.DLS.get
  let set = Domain.DLS.set
end
|}

let write_file file s =
  let oc = open_out file in
  output_string oc s;
  close_out oc

let () =
  let version = Scanf.sscanf Sys.ocaml_version "%d.%d.%s" (fun x y _ -> x, y) in
  write_file "opentelemetry_domain.ml"
    (if version >= (5, 0) then
       domain_5
     else
       domain_4);
  ()
