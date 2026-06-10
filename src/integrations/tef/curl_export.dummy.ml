(* Implementation selected when [curly] is NOT available (see dune). *)

type protocol =
  | Protobuf
  | Json

let available = false

let send ?endpoint:_ ?protocol:_ (_ : Convert.bundle) : (unit, string) result =
  Error
    "curl export unavailable: this build was compiled without the `curly` \
     library. Either install `curly`, or emit through the standard providers \
     (Opentelemetry_import_tef.Emit.via_providers)."
