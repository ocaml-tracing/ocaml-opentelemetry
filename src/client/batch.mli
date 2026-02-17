(** A thread-safe batch of resources, to be sent together when ready. *)

type 'a t

val make :
  ?batch:int ->
  ?high_watermark:int ->
  ?mtime:Mtime.t ->
  ?timeout:Mtime.span ->
  unit ->
  'a t
(** [make ()] is a new batch

    @param batch
      the number of elements after which the batch will be considered {b full},
      and ready to pop. It is required that [batch >= 0]. Default [100].

    @param high_watermark
      the batch size limit after which new elements will be [`Dropped] by
      {!push}. This prevents the queue from growing too fast for effective
      transmission in case of signal floods. Default
      [if batch = 1 then 100 else batch * 10].

    @param mtime the current time.

    @param timeout
      the time span after which a batch is ready to pop, whether or not it is
      {b full}. *)

val pop_if_ready : ?force:bool -> mtime:Mtime.t -> 'a t -> 'a list option
(** [pop_if_ready ~mtime b] is [Some xs], where is [xs] includes all the
    elements {!push}ed since the last batch, if the batch ready to be emitted.

    A batch is ready to pop if it contains some elements and

    - batching is disabled, and any elements have been batched, or batching was
      enabled and at least [batch] elements have been pushed, or
    - a [timeout] was provided, and more than a [timeout] span has passed since
      the last pop was ready, or
    - the pop is [force]d,

    @param mtime the current monotonic time

    @param force
      override the other batch conditions, for when when we just want to emit
      batches before exit or because the user asks for it *)

val push : 'a t -> 'a list -> [ `Dropped | `Ok ]
(** [push b xs] is [`Ok] if it succeeds in pushing the values in [xs] into the
    batch [b], or [`Dropped] if the current size of the batch has exceeded the
    high water mark determined by the [batch] argument to [{!make}]. ) *)

val push' : 'a t -> 'a list -> unit
(** Like {!push} but ignores the result *)

val cur_size : _ t -> int
(** Number of elements in the current batch *)

val n_dropped : _ t -> int
(** Number of elements dropped because the batch exceeded its high watermark *)

(**/**)

module Internal_ : sig
  val mtime_dummy_ : Mtime.t
end

(**/**)
