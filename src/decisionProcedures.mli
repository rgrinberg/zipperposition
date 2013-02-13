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

(** Decision procedures for theories *)

open Types
open Symbols

(** {2 General interface} *)

type dp = {
  dp_name : string;                 (** Theory this procedures decides *)
  dp_descr : string;                (** Description of the procedure *)
  dp_equal : term -> term -> bool;  (** Check whether two terms are equal *)
  dp_sig : SSet.t;                  (** Symbols of the theory *)
  dp_clauses : hclause list;        (** Clauses to add to the problem *)
  dp_canonize : term -> term;       (** Get a canonical form of the term *)
  dp_solve : (term -> term -> substitution) option;
}

val dp_compatible : dp -> dp -> bool
  (** Simple syntaxic criterion to decide whether two decision procedures
      are compatibles: check whether they have no symbol in common. *)

val dp_combine : dp -> dp -> dp
  (** Combine two decision procedures into a new one, that decides
      the combination of their theories, assuming they are compatible. *)

val dp_is_redundant : dp -> hclause -> bool
  (** Decide whether this clause is redundant *)

val dp_simplify : dp -> hclause -> hclause
  (** Simplify the clause *)

(** {2 Ground joinable sets of equations} *)

(** We use ground convergent sets of equations to decide some equational
    theories. See
    "On using ground joinable equations in equational theorem proving", by
    Avenhaus, Hillenbrand, Lochner *)

type gnd_convergent = {
  gc_ord : string;                    (** name of the ordering *)
  gc_prec : precedence;               (** Precedence *)
  gc_sig : SSet.t;                    (** Symbols of the theory *)
  gc_equations : literal array list;  (** Equations of the system *)
} (** A set of ground convergent equations, for some order+precedence *)

val mk_gc : ord:ordering -> hclause list -> gnd_convergent

val gc_to_dp : gnd_convergent -> dp
  (** From a set of ground convergent equations, make a decision
      procedure that can be used by the prover *)

val pp_gc : Format.formatter -> gnd_convergent -> unit
  (** Pretty-print the system of ground convergent equations *)

(** {3 JSON encoding} *)

val gc_to_json : gnd_convergent -> json
val gc_of_json : ctx:context -> json -> gnd_convergent

(** {2 Some builtin theories} *)

val ac : symbol -> dp
  (** Theory of Associative-Commutative symbols, for the given symbol *)

val assoc : symbol -> dp
  (** Theory of Associative symbols *)