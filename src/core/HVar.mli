
(* This file is free software, part of Logtk. See file "license" for more details. *)

(** {1 Hashconsed Variable}

    A variable for hashconsed terms, paired with a type.
*)

type +'a t = private {
  id: int;
  ty: 'a;
}
type 'a hvar = 'a t

val make : ty:'a -> int -> 'a t
val id : _ t -> int
val ty : 'a t -> 'a

val cast : 'a t -> ty:'b -> 'b t
val update_ty : 'a t -> f:('a -> 'b) -> 'b t

val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int
val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool
val hash : _ t -> int

val max : 'a t -> 'a t -> 'a t
val min : 'a t -> 'a t -> 'a t

val pp : _ t CCFormat.printer
val to_string : _ t -> string

(**/**)
val make_unsafe : ty:'a -> int -> 'a t
(** skip checks *)

val fresh : ty:'a -> unit -> 'a t
(** Magic: create a variable with a negative index, mostly for
    unification purpose *)

(**/**)

