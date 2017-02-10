
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Dismatching Constraint} *)

(** A constraint that specifies that a list of terms [t1, …, tn]
    must not match patterns [u1, …, un].
    Variables in the [u_i] live in a distinct scope than variables
    in the [t_i]. *)

open Libzipperposition

type term = FOTerm.t

type t

val make : (term * term) list -> t
(** [make [t_1,u_1; …; t_n,u_n]]
    makes a dismatching constraint that is satisfied for every
    ground substitution [sigma] such that at least one [t_i\sigma] does not
    match the pattern [u_i]. *)

val combine : t -> t -> t

val apply_subst :
  renaming:Subst.Renaming.t ->
  Subst.t ->
  t Scoped.t ->
  t
(** Apply a substitution [sigma] to the constraints. The constraint
    might become trivial as a result. *)

val is_trivial : t -> bool
(** Is the constraint trivially satisfied? (i.e. always true).
    That happens, for instance, for constraints such as [f x /< g y] *)

val is_absurd : t -> bool
(** Is the constraint never satisfied? (i.e. necessarily false).
    That happens if all RHS match their LHS already
    (will still hold for every instance). *)

include Interfaces.PRINT with type t := t
