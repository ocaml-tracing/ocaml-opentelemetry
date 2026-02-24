(** Add a batch in front of an emitter.

    The batch accumulates signals until it's full or too old, at which points
    all the accumulated signals are emitted at once. Pushing into a batch is
    generally very fast (amortized), in most cases; the slow path is only when
    the batch needs to be emitted.

    @since NEXT_RELEASE *)

open Opentelemetry_emitter

val wrap_emitter_with_batch : 'a Batch.t -> 'a Emitter.t -> 'a Emitter.t
(** [wrap_emitter_with_batch batch e] is an emitter that uses batch [batch] to
    gather signals into larger lists before passing them to [e]. *)

val add_batching :
  timeout:Mtime.span -> batch_size:int -> 'a Emitter.t -> 'a Emitter.t

val add_batching_opt :
  timeout:Mtime.span -> batch_size:int option -> 'a Emitter.t -> 'a Emitter.t
