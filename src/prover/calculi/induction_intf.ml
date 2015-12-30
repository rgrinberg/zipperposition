
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

open Libzipperposition

(** {2 Induction} *)

module type S = sig
  module Env : Env.S
  module Ctx : module type of Env.Ctx

  (* TODO: move most information into [ID.payload] *)

  type bool_lit = Bool_lit.t

  type constructor = ID.t * Type.t
  (** Constructor for an inductive type *)

  (** An inductive type, along with its set of constructors *)
  type inductive_type = private {
    pattern : Type.t; (* type, possibly with free variables *)
    constructors : constructor list;
  }

  val on_new_inductive_ty : inductive_type Signal.t
  (** Triggered every time a new inductive type is declared *)

  val inductive_ty_seq : inductive_type Sequence.t
  (** Sequence of all inductive types declared so far *)

  val declare_ty : Type.t -> constructor list -> inductive_type
  (** Declare the given inductive type.
      @raise Failure if the type is already declared
      @raise Invalid_argument if the list of constructors is empty. *)

  val is_inductive_type : Type.t -> bool
  (** [is_inductive_type ty] holds iff [ty] is an instance of some
      registered type (registered with {!declare_ty}). *)

  val is_constructor_sym : ID.t -> bool
  (** true if the symbol is an inductive constructor (zero, successor...) *)

  val contains_inductive_types : FOTerm.t -> bool
  (** [true] iff the term contains at least one subterm with
      an inductive type *)

  (** {6 Inductive Constants} *)

  type cst = private FOTerm.t
  (** A ground term of an inductive type. It must correspond to a
      term built with the corresponding {!inductive_type} only.
      For instance, a constant of type [nat] should be equal to
      [s^n(0)] in any model. *)

  module Cst : BBox_intf.TERM with type t = cst

  type case = private FOTerm.t
  (** A member of a coverset *)

  module Case : BBox_intf.TERM with type t = case

  type sub_cst = private FOTerm.t
  (** A subterm of some {!case} that has the same (inductive) type *)

  val is_blocked : FOTerm.t -> bool
  (** Some terms that could be inductive constants are {b blocked}. In
      particular, constructors, but also skolem constants introduced by
      calls to {!cover_set}. *)

  val set_blocked : FOTerm.t -> unit
  (** Declare that the given term cannot be candidate for induction *)

  val declare : FOTerm.t -> unit
  (** Check whether the  given term can be an inductive constant,
      and if possible, adds it to the set of inductive constants.
      Requirements: it must be ground, and its type must be a
      known {!inductive type}.

      @raise Invalid_argument if the parent isn't inductive or the
        term is non-ground *)

  val on_new_inductive : cst Signal.t
  (** Triggered with new inductive constants *)

  val as_inductive : FOTerm.t -> cst option
  val is_inductive : FOTerm.t -> bool
  (** Check whether the given constant is ready for induction, and
      downcast it if it's the case *)

  val is_inductive_symbol : ID.t -> bool
  (** Head symbol of some inductive (ground) term?*)

  module SubCstSet : Set.S with type elt = sub_cst

  type cover_set = {
    cases : case list; (* all cases *)
    rec_cases : case list; (* recursive cases *)
    base_cases : case list;  (* non-recursive (base) cases *)
    sub_constants : SubCstSet.t;  (* leaves of recursive cases *)
  }

  val as_sub_constant : FOTerm.t -> sub_cst option
  val is_sub_constant : FOTerm.t -> bool
  (** Is the term a constant that was created within a cover set? *)

  val is_sub_constant_of : FOTerm.t -> cst -> bool
  val as_sub_constant_of : FOTerm.t -> cst -> sub_cst option
  (** downcasts iff [t] is a sub-constant of [cst] *)

  val is_case : FOTerm.t -> bool
  val as_case : FOTerm.t -> case option

  val dominates : ID.t -> ID.t -> bool
  (** [dominates s1 s2] true iff s2 is one of the sub-cases of s1 *)

  val inductive_cst_of_sub_cst : sub_cst -> cst * case
  (** [inductive_cst_of_sub_cst t] finds a pair [c, t'] such
      that [c] is an inductive const, [t'] belongs to a coverset
      of [c], and [t] is a sub-constant within [t'].
      @raise Not_found if [t] isn't an inductive constant *)

  val cases : ?which:[`Rec|`Base|`All] -> cover_set -> case Sequence.t
  (** Cases of the cover set *)

  val sub_constants : cover_set -> sub_cst Sequence.t
  (** All sub-constants of a given inductive constant *)

  val sub_constants_case : case -> sub_cst Sequence.t
  (** All sub-constants that are subterms of a specific case *)

  val cover_set : ?depth:int -> cst -> cover_set * [`New|`Old]
  (** [cover_set t] gives a set of ground terms [[t1,...,tn]] with fresh
      constants inside (that are not declared as inductive!) such that
      [bigor_{i in 1...n} t=ti] is the skolemized version of the
      exhaustivity axiom on [t]'s type.
      @param depth (default 1) depth of cover terms; the deeper, the more
        covering terms there will be. *)

  val cover_sets : cst -> cover_set Sequence.t
  (** All current cover sets of [cst] *)

  val on_new_cover_set : (cst * cover_set) Signal.t
  (** triggered with [t, set] when [set] is a new cover set for [t] *)

  module Set : Sequence.Set.S with type elt = cst
  (** Set of constants *)

  module Seq : sig
    val ty : inductive_type Sequence.t
    val cst : cst Sequence.t

    val constructors : ID.t Sequence.t
    (** All known constructors *)
  end

  module Meta : sig
    (** An inductive type *)
    type ty = {
      ty : Type.t;
      cstors : (ID.t * Type.t) list;
    }

    val t : ty Plugin.t
    (** Plugin that encodes the fact that a type is inductive, together
        with the list of its constructor symbols.
        Example: [nat, [succ; zero]] *)
  end

  val register : unit -> unit
end