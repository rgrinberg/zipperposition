
(*
Zipperposition: a functional superposition prover for prototyping
Copyright (c) 2013, Simon Cruanes
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  Redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 Polynomes of order 1, over several variables}.

    Variables, in this module, are non-arithmetic terms, i.e. non-interpreted
    functions and predicates, that occur immediately under an arithmetic
    operator. For instance, in the term "f(X) + 1 + 3 × a", the variables
    are "f(X)" and "a", with coefficients "1" and "3".
*)

open Logtk

type term = FOTerm.t

type 'a t
(** A monome over terms, with coefficient of type 'a *)

type 'a monome = 'a t

val eq : 'n t -> 'n t -> bool       (* structural equality *)
val compare : 'n t -> 'n t -> int   (* arbitrary total order on monomes *)
val hash : _ t -> int

val ty : _ t -> Type.t   (** type of the monome (int or rat) *)

val const : 'a t -> 'a   (** constant *)
val coeffs : 'a t -> ('a * term) list  (** coefficients *)

val find : 'a t -> term -> 'a option
val find_exn : 'a t -> term -> 'a (** @raise Not_found if not present *)
val mem : _ t -> term -> bool     (** Is the term in the monome? *)

val add : 'a t -> 'a -> term -> 'a t  (** Add term with coefficient. Sums coeffs. *)
val add_const : 'a t -> 'a -> 'a t    (** Add given number to constant *)
val remove : 'a t -> term -> 'a t     (** Remove the term *)
val remove_const : 'a t -> 'a t       (** Remove the constant *)

val map : (term -> term) -> 'a t -> 'a t
val map_num : ('a -> 'a) -> 'a t -> 'a t

module Seq : sig
  val terms : _ t -> term Sequence.t
  val vars : _ t -> term Sequence.t
  val coeffs : 'a t -> ('a * term) Sequence.t
end

val is_const : _ t -> bool
  (** Returns [true] if the monome is only a constant *)

val sign : _ t -> int
  (** Assuming [is_constant m], [sign m] returns the sign of [m].
      @raise Invalid_argument if the monome is not a constant *)

val size : _ t -> int
  (** Number of distinct terms. 0 means that the monome is a constant *)

val terms : _ t -> term list
  (** List of terms that occur in the monome with non-nul coefficients *)

val var_occurs : var:term ->  _ t -> bool
  (** Does the variable occur in the monome? *)

val sum : 'a t -> 'a t -> 'a t
val difference : 'a t -> 'a t -> 'a t
val uminus : 'a t -> 'a t
val product : 'a t -> 'a -> 'a t  (** Product with constant *)
val succ : 'a t -> 'a t           (** +1 *)
val pred : 'a t -> 'a t           (** -1 *)

val sum_list : 'a t list -> 'a t
  (** Sum of a list.
      @raise Failure if the list is empty *)

val comparison : 'a t -> 'a t -> Comparison.t
  (** Try to compare two monomes. They may not be comparable (ie on some
      points, or in some models, one will be bigger), but some pairs of
      monomes are:
      for instance, 2X + 1 < 2X + 4  is always true *)

val dominates : 'a t -> 'a t -> bool
  (** [dominates m1 m2] is true if [m1] is always bigger or equal than
      [m2], in any model or variable valuation.
      if [dominates m1 m2 && dominates m2 m1], then [m1 = m2]. *)

val split : 'a t -> 'a t * 'a t
  (** [split m] splits into a monome with positive coefficients, and one
      with negative coefficients.
      @return [m1, m2] such that [m = m1 - m2] and [m1,m2] both have positive
        coefficients *)

val apply_subst : renaming:Substs.Renaming.t ->
                  Substs.t -> 'a t -> Substs.scope -> 'a t
  (** Apply a substitution to the monome's terms *)

val is_ground : _ t -> bool
  (** Are there no variables in the monome? *)

val pp : Buffer.t -> 'a t -> unit
val to_string : 'a t -> string
val fmt : Format.formatter -> 'a t -> unit

val pp_tstp : Buffer.t -> 'a t -> unit

exception NotLinear

module Int : sig
  type t = Z.t monome

  val const : Z.t -> t (** Empty monomial, from constant (decides type) *)
  val singleton : Z.t -> term -> t  (** One term. *)
  val of_list : Z.t -> (Z.t * term) list -> t

  val of_term : term -> t option

  val of_term_exn : term -> t
    (** try to get a monome from a term.
        @raise NotLinear if the term is not a proper monome. *)

  val to_term : t -> term
    (** convert back to a term *)

  val has_instances : t -> bool
    (** For real or rational, always true. For integers, returns true
        iff g divides [m.constant], where g is the
        GCD of [c] for [c] in [m.coeffs].

        The intuition is that this returns [true] iff the monome actually has
        some instances in its type. Trivially true in reals or rationals, this is
        only the case for integers if [m.coeffs + m.constant = 0] is a
        satisfiable diophantine equation. *)

  val quotient : t -> Z.t -> t option
    (** [quotient e c] tries to divide [e] by [c], returning [e/c] if
        it is still an integer expression.
        For instance, [quotient (2x + 4y) 2] will return [Some (x + 2y)] *)

  val divisible : t -> Z.t -> bool
    (** [divisible e n] returns true if all coefficients of [e] are
        divisible by [n] and n is an int >= 2 *)

  val factorize : t -> (t * Z.t) option
    (** Factorize [e] into [Some (e',s)] if [e = e' x s], None
        otherwise (ie if s=1) *)

  val normalize_wrt_zero : t -> t
    (** Allows to multiply or divide by any positive number since we consider
        that the monome is equal to (or compared with) zero.
        For integer monomes, the result will have co-prime coefficients. *)

  val reduce_same_factor : t -> t -> term -> t * t
    (** [reduce_same_factor m1 m2 t] multiplies [m1] and [m2] by
        some constants, so that their coefficient for [t] is the same.
        @raise Invalid_argument if [t] does not belong to [m1] or [m2] *)

  (** {2 Modular Computations} *)

  module Modulo : sig
    val modulo : n:Z.t -> Z.t -> Z.t
      (** Representative of the number in Z/nZ *)

    val sum : n:Z.t -> Z.t -> Z.t -> Z.t
      (** Sum in Z/nZ *)

    val uminus : n:Z.t -> Z.t -> Z.t
      (** Additive inverse in Z/nZ *)

    val inverse : n:Z.t -> Z.t -> Z.t
      (** Multiplicative inverse in Z/nZ.
          TODO (only works if [n] prime? or n^k where n prime?) *)
  end

  (** {2 Find Solutions} *)

  module Solve : sig
    type solution = (term * t) list
      (** List of constraints (term = monome). It means that
          if all those constraints are satisfied, then a solution
          to the given problem has been found *)

    val split_solution : solution -> Substs.t * solution
      (** Split the solution into a variable substitution, and a
          list of constraints on non-variable terms *)

    val diophant2 : Z.t -> Z.t -> Z.t -> Z.t * Z.t * Z.t
      (** Find the solution vector for this diophantine equation, or fails.
          @return a triple [u, v, gcd] such that for all int [k],
          [u + b * k, v - a * k] is solution of equation [a * x + b * y = const].
          @raise Failure if the equation is unsolvable *)

    val diophant_l : Z.t list -> Z.t -> Z.t list * Z.t
    (** generalize diophantine equation solving to a list of at least two
        coefficients.
        @return a list of Bezout coefficients, and the
          GCD of the input list, or fails
        @raise Failure if the equation is not solvable *)

    val coeffs_n : Z.t list -> Z.t -> (term list -> t list)
      (** [coeffs_n l gcd], if [length l = n], returns a function that
          takes a list of [n-1] terms [k1, ..., k(n-1)] and returns a list of
          monomes [m1, ..., mn] that depend on [k1, ..., k(n-1)] such that the sum
          [l1 * m1 + l2 * m2 + ... + ln * mn = 0].

          {b Note} that the input list of the solution must have [n-1] elements,
          but that it returns a list of [n] elements!

          @param gcd is the gcd of all members of [l].
          @param l is a list of at least 2 elements, none of which should be 0 *)

    val eq_zero : ?fresh_var:(Type.t -> term) -> t -> solution list
      (** Returns substitutions that make the monome always equal to zero.
          Fresh variables may be generated using [fresh_var],
          for diophantine equations. Returns the empty list if no solution is
          found.

          For instance, on the monome 2X + 3Y - 7, it may generate a new variable
          Z and return the substitution  [X -> 3Z - 7, Y -> 2Z + 7] *)

    val lower_zero : ?fresh_var:(Type.t -> term) -> strict:bool ->
                     t -> solution list
      (** Solve for the monome to be always lower than zero ([strict] determines
          whether the inequality is strict or not). This
          may not return all solutions, but a subspace of it
          @param fresh_var see {!solve_eq_zero} *)

    val lt_zero : ?fresh_var:(Type.t -> term) -> t -> solution list
      (** Shortcut for {!lower_zero} when [strict = true] *)

    val leq_zero : ?fresh_var:(Type.t -> term) -> t -> solution list
      (** Shortcut for {!lower_zero} when [strict = false] *)

    val neq_zero : ?fresh_var:(Type.t -> term) -> t -> solution list
      (** Find some solutions that negate the equation. For now it
          just takes solutions to [m < 0].  *)
  end
end

(** {2 For fields (Q,R)} *)

(*
val floor : t -> t
  (** Highest monome that is <= m, and that satisfies [has_instances]. *)

val ceil : t -> t
  (** Same as {!round_low} but rounds high *)

val exact_quotient : 'a t -> Symbol.t -> 'a t
  (** Division in a field.
      @raise Division_by_zero if the denominator is zero. *)
*)