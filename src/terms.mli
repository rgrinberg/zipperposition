(*
Zipperposition: a functional superposition prover for prototyping
Copyright (C) 2012 Simon Cruanes

This is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA.
*)

open Types

(** Functions on first-order terms *)

(** symbols that are symmetric (that is, order of arguments does not matter) *)
val is_symmetric_symbol : symbol -> bool

(* ----------------------------------------------------------------------
 * comparison, equality, containers
 * ---------------------------------------------------------------------- *)
val member_term : term -> term -> bool    (** [a] [b] checks if a subterm of b *)
val eq_term : term -> term -> bool        (** standard equality on terms *)
val compare_term : term -> term -> int    (** a simple order on terms *)

module TSet : Set.S with type elt = term
module TPairSet : Set.S with type elt = term * term
module THashtbl : Hashtbl.S with type key = term

(** Simple hashset for small sets of terms *)
module THashSet :
  sig
    type t
    val create : unit -> t
    val member : t -> term -> bool
    val iter : t -> (term -> unit) -> unit
    val add : t -> term -> unit
    val merge : t -> t -> unit              (** [merge s1 s2] adds elements of s2 to s1 *)
    val to_list : t -> term list            (** build a list from the set *)
    val from_list : term list -> t          (** build a set from the list *)
  end

(* ----------------------------------------------------------------------
 * access global terms table (hashconsing)
 * ---------------------------------------------------------------------- *)
val iter_terms : (term -> unit) -> unit       (** iterate through existing terms *)
val all_terms : unit -> term list             (** all currently existing terms *)
val stats : unit -> (int*int*int*int*int*int) (** hashcons stats *)

(* ----------------------------------------------------------------------
 * smart constructors, with a bit of type-checking
 * ---------------------------------------------------------------------- *)
val mk_var : int -> sort -> term
val mk_leaf : symbol -> sort -> term
val mk_node : term list -> term
val mk_apply : symbol -> sort -> term list -> term

val true_term : term                        (** tautology symbol *)
val false_term : term                       (** antilogy symbol *)

val mk_not : term -> term
val mk_and : term -> term -> term
val mk_or : term -> term -> term
val mk_imply : term -> term -> term
val mk_eq : term -> term -> term
val mk_lambda : term -> term
val mk_forall : term -> term
val mk_exists : term -> term

val cast : term -> sort -> term           (** cast (change sort) *)

(* ----------------------------------------------------------------------
 * examine term/subterms, positions...
 * ---------------------------------------------------------------------- *)
val is_var : term -> bool
val is_leaf : term -> bool
val is_node : term -> bool
val hd_term : term -> term option           (** the head of the term *)
val hd_symbol : term -> symbol option       (** the head of the term *)

val at_pos : term -> position -> term       (** retrieve subterm at pos, or
                                                  raise Invalid_argument
                                                  TODO also return a context? *)
val replace_pos : term -> position          (** replace t|_p by the second term *)
               -> term -> term

val vars_of_term : term -> varlist          (** free variables in the term *)
val is_ground_term : term -> bool           (** is the term ground? *)
val merge_varlist : varlist -> varlist -> varlist (** set union of variable list *)
val max_var : varlist -> int                (** find the maximum variable index *)
val min_var : varlist -> int

(* ----------------------------------------------------------------------
 * bindings and normal forms
 * ---------------------------------------------------------------------- *)
val set_binding : term -> term -> unit      (** [set_binding t d] set variable binding or normal form of t *)
val reset_binding : term -> unit            (** reset variable binding/normal form *)
val get_binding : term -> term              (** get the binding of variable/normal form of term *)
val expand_bindings : term -> term          (** replace variables by their bindings *)


(* ----------------------------------------------------------------------
 * De Bruijn terms, and dotted formulas
 * ---------------------------------------------------------------------- *)
val atomic : term -> bool                   (** atomic proposition, or term, at root *)
val atomic_rec : term -> bool               (** does not contain connectives/quantifiers *)
val db_closed : term -> bool                (** check whether the term is closed *)

(** Does t contains the De Bruijn variable of index n? *)
val db_contains : term -> int -> bool
(** Substitution of De Bruijn symbol by a term. [db_replace t s]
    replaces the De Bruijn symbol 0 by s in t *)
val db_replace : term -> term -> term
(** Create a De Bruijn variable of index n *)
val db_make : int -> sort -> term
(** Unlift the term (decrement indices of all De Bruijn variables inside *)
val db_unlift : term -> term
(** [db_from_var t v] replace v by a De Bruijn symbol in t *)
val db_from_var : term -> term -> term
(** index of the De Bruijn term *)
val db_depth : term -> int
(** [look_db_sort n t] find the sort of the De Bruijn index n in t *)
val look_db_sort : int -> term -> sort option

(* ----------------------------------------------------------------------
 * Pretty printing
 * ---------------------------------------------------------------------- *)

(** type of a pretty printer for symbols *)
class type pprinter_symbol =
  object
    method pp : Format.formatter -> symbol -> unit  (** pretty print a symbol *)
    method infix : symbol -> bool                   (** which symbol is infix? *)
  end

val pp_symbol : pprinter_symbol ref                 (** default pp for symbols *)
val pp_symbol_unicode : pprinter_symbol             (** print with unicode special symbols*)
val pp_symbol_tstp : pprinter_symbol                (** tstp convention (raw) *)

(** type of a pretty printer for terms *)
class type pprinter_term =
  object
    method pp : Format.formatter -> term -> unit  (** pretty print a term *)
  end

val pp_term : pprinter_term ref                     (** current choice *)
val pp_term_tstp : pprinter_term                    (** print term in TSTP syntax *)
val pp_term_debug :                                 (** print term in a nice syntax *)
  <
    pp : Format.formatter  -> term -> unit;
    sort : bool -> unit;                            (** print sorts of terms? *)
    skip_lambdas : bool -> unit;                    (** print lambdas after quantifiers? *)
    skip_db : bool -> unit;                         (** nice printing of De Bruijn terms *)
  >

val pp_signature : Format.formatter -> symbol list -> unit      (** print signature *)
