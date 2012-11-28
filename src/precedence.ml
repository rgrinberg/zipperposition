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
open Symbols

module T = Terms
module C = Clauses
module Utils = FoUtils

(** Precedence on symbols *)

(** compute the current signature: existing symbols,
    with their arities and sorts *)
let compute_signature () =
  let sorts, arities, symbols = base_signature () in
  let symbols = ref symbols in
  T.iter_terms
    (fun t -> match t.term with
     | Var _ -> ()
     | Node (s, l) ->
       begin
         (* update the arity only if not already found *)
         if not (SHashtbl.mem arities s) then SHashtbl.replace arities s (List.length l);
         (* update sort only if it is not already bool *)
         (if (try SHashtbl.find sorts s == bool_sort with Not_found -> false)
           then ()
           else SHashtbl.replace sorts s t.sort);
         if not (List.mem s !symbols) then symbols := s::!symbols
       end);
  sorts, arities, !symbols

let sig_version = ref 0  (* version of signature that is computed *)

let current_signature =
  (* store the signature, to avoid recomputing it all the time *)
  let cached_signature = ref (compute_signature ()) in
  fun () ->
    assert (!sig_version <= !Symbols.sig_version);
    (if !sig_version < !Symbols.sig_version
      then(* recompute signature, it did change *)
        cached_signature := compute_signature ());
    !cached_signature

(* ----------------------------------------------------------------------
 * hard constraints on the ordering
 * ---------------------------------------------------------------------- *)

let cluster_constraint clusters =
  let table = SHashtbl.create 17
  and cluster_num = ref 0 in
  (* for each cluster, assign it a (incremented) number, and
     remember symbol->number for every symbol of the cluster *)
  List.iter
    (fun cluster ->
      let num = !cluster_num in
      incr cluster_num;
      List.iter (fun symb -> SHashtbl.add table symb num) cluster)
    clusters;
  (* compare symbols by their number, if they have. Smaller numbers are bigger symbols *)
  let compare s1 s2 =
    try
      let s1_num = SHashtbl.find table s1
      and s2_num = SHashtbl.find table s2 in
      s2_num - s1_num
    with Not_found -> 0 (* at least one is not in the table, we do not order *)
  in compare

let list_constraint l =
  let num = ref  0
  and table = SHashtbl.create 13 in
  (* give a number to every symbol *)
  List.iter
    (fun symb ->
      let symb_num = !num in
      assert (symb == mk_symbol (name_symbol symb));
      incr num;
      SHashtbl.add table symb symb_num)
    l;
  (* compare symbols by number. Smaller symbols have bigger number *)
  let compare s1 s2 =
    try
      let s1_num = SHashtbl.find table s1
      and s2_num = SHashtbl.find table s2 in
      s2_num - s1_num
    with Not_found -> 0 (* at least one is not in the table, we do not order *)
  in compare

let ordering_to_constraint so =
  list_constraint so#signature 

let arity_constraint arities =
  let compare s1 s2 =
    try
      let s1_arity = SHashtbl.find arities s1
      and s2_arity = SHashtbl.find arities s2 in
      s1_arity - s2_arity  (* bigger arity is bigger *)
    with Not_found -> 0
  in compare

let max_constraint symbols =
  let table = SHashtbl.create 11
  and num = ref 0 in
  (* give number to symbols *)
  List.iter
    (fun symb -> let n = !num in
      incr num; SHashtbl.add table symb n)
    symbols;
  let compare a b =
    (* not found implies the symbol is smaller than maximal symbols *)
    let a_n = try SHashtbl.find table a with Not_found -> !num
    and b_n = try SHashtbl.find table b with Not_found -> !num in
    b_n - a_n  (* if a > b then a_n < b_n *)
  in compare
  
let min_constraint symbols =
  let table = SHashtbl.create 11
  and num = ref 0 in
  (* give number to symbols *)
  List.iter
    (fun symb -> let n = !num in
      incr num; SHashtbl.add table symb n)
    symbols;
  let compare a b =
    (* not found implies the symbol is bigger than minimal symbols *)
    let a_n = try SHashtbl.find table a with Not_found -> -1
    and b_n = try SHashtbl.find table b with Not_found -> -1 in
    b_n - a_n  (* if a > b then a_n < b_n *)
  in compare

(* regular string ordering *)
let alpha_constraint a b = compare_symbols a b

let compose_constraints c1 c2 =
  (* first we compare using c2, then using c1 if needed, because
     c2 is prioritary *)
  let compare a b =
    let c2_ab = c2 a b in
    if c2_ab <> 0 then c2_ab  (* c2 has decided *)
    else c1 a b               (* let c1 decide *)
  in compare

let check_constraint signature constr =
  (* check whether a list is sorted in decreasing order w.r.t constraint *)
  let rec is_sorted l = match l with
  | [] | [_] -> true
  | x::((y::_) as l') ->
    let cmp_xy = constr x y in
    if cmp_xy >= 0 then is_sorted l'
    else false
  in
  is_sorted signature

(* ----------------------------------------------------------------------
 * Creation of a precedence (symbol_ordering) from constraints
 * ---------------------------------------------------------------------- *)

(* build an ordering from a constraint *)
let make_ordering constr =
  (* references that hold current state *)
  let cur_signature = ref []
  and cmp = ref (fun x y -> 0)
  and multiset_pred = ref (fun s -> s == eq_symbol) in
  (* the object itself *)
  let obj = object (self)
    (* refresh computes a new ordering based on the current signature *)
    method refresh () =
      (* the constraint is: keep the current signature in the same order *)
      assert (check_constraint !cur_signature !cmp);
      let keep_constr = compose_constraints constr !cmp in
      (* the new signature, possibly with more symbols*)
      let _, _, symbols = current_signature () in
      (* sort according to the constraint *)
      Utils.debug 3 (lazy (Utils.sprintf "%% old signature %a" T.pp_signature self#signature));
      cur_signature := List.sort (fun x y -> -(keep_constr x y)) symbols;
      (* comparison function is given by the place in the ordered signature *)
      assert (check_constraint !cur_signature !cmp);
      cmp := list_constraint !cur_signature;
      Utils.debug 3 (lazy (Utils.sprintf "%% new signature %a" T.pp_signature self#signature));
      (* assert (check_constraint self (list_constraint old_signature)) *)
    method signature = !cur_signature
    method compare a b = !cmp a b
    method multiset_status s = !multiset_pred s
    method set_multiset f = multiset_pred := f
  end
  in
  (* do the initial computation and return the object *)
  obj#refresh ();
  obj

let rec default_symbol_ordering () =
  let _, arities, _ = current_signature () in
  (* two constraints: false, true at end of precedence, and arity constraint *)
  let constr = compose_constraints
    (arity_constraint arities) (min_constraint [false_symbol; true_symbol]) in
  (* apply the constraints to the dummy symbol ordering *)
  make_ordering constr

(* ----------------------------------------------------------------------
 * Heuristic constraints to try to reduce search space
 * ---------------------------------------------------------------------- *)

(** a weighted constraint is a weight (cost), and a function to check if it's satisfied *)
type weighted_constr = int * (ordering -> bool)

(** Does t contains the symbol f? *)
let rec contains_symbol f t = match t.term with
  | Var _ -> false
  | Node (g, _) when f == g -> true
  | Node (_, ts) -> List.exists (contains_symbol f) ts

(** create a constraint that a > b holds in the given ordering *)
let check_gt ~weight a b =
  (weight, fun ord -> ord#compare a b = Gt)

let weight_def = 5      (** weight of definitions *)
let weight_RR_horn = 2  (** weight of RR Horn clauses *)

(** Creates a weighted constraint if the clause is a symbol definition,
    ie an equation/equivalence f(x1,...,xn)=b where f does not occur in b *)
let check_definition clause =
  match clause.clits with
  | [Equation (({term=Node(f,ts)} as l),r,true,_)] when
    not (contains_symbol f r) && l != T.true_term && r != T.true_term && List.for_all T.is_var ts ->
    Utils.debug 0 (lazy (Utils.sprintf "%% @[<h>definition: %a --> %a@]" !T.pp_term#pp l !T.pp_term#pp r));
    [check_gt ~weight:weight_def l r]
  | [Equation (l, ({term=Node(f,ts)} as r),true,_)] when
    not (contains_symbol f l) && l != T.true_term && r != T.true_term && List.for_all T.is_var ts ->
    Utils.debug 0 (lazy (Utils.sprintf "%% @[<h>definition: %a --> %a@]" !T.pp_term#pp r !T.pp_term#pp l));
    [check_gt ~weight:weight_def r l]
  | _ -> [] (* not a definition *)

(** constraint if the clause is a Range-Restricted Horn clause,
    that is assumed to be a definition of its head. We therefore seek to
    make the head maximal (best coupled with SelectComplexExceptRRHorn). *)
let check_horn_definition c =
  if Theories.is_RR_horn_clause c && List.length c.clits > 1
    then begin
      Utils.debug 0 (lazy (Utils.sprintf "%% @[<h>RR horn definition: %a@]" !C.pp_clause#pp c));
      (* find head and body of the clause *)
      let head = List.hd (List.filter C.pos_lit c.clits)
      and body = List.filter C.neg_lit c.clits in
      (* constraint: head is not < than any literal of the body *)
      let constr ord =
        List.for_all (fun b -> C.compare_lits_partial ~ord head b <> Gt) body in
      [weight_RR_horn, constr]
    end else []

(* ----------------------------------------------------------------------
 * Heuristic creation of precedences (satisfying maximal number of constraints)
 * ---------------------------------------------------------------------- *)

(** Check whether the two precedences are equal *)
let eq_precedence c1 c2 =
  assert (List.length c1#signature = List.length c2#signature);
  List.for_all2 (==) c1#signature c2#signature

(** Compute a precedence from the signature and the strong constraint *)
let compute_precedence constr signature : symbol_ordering =
  let sig_constraint = list_constraint signature in
  (* XXX note that a total ordering is needed for sound updates of the ordering *)
  make_ordering (compose_constraints alpha_constraint
                                     (compose_constraints sig_constraint constr))

(** Compute the cost for the precedence, given a list of constraints
    and a way to build a term ordering *)
let compute_cost ord_factory constraints precedence : int =
  let ord = ord_factory precedence in
  (* sum up weights of unsatisfied constraints *)
  let cost = List.fold_left
    (fun cost (w, constr) -> if constr ord then cost else cost + w)
    0 constraints
  in
  Utils.debug 2 (lazy (Utils.sprintf "@[<h>cost %d for %a@]" cost
                  T.pp_signature precedence#signature));
  cost

(** Shuffle the signature by reversing some symbols (uses random).
    It returns at most [num] modifications of the signature, that differ from
    it by a swap of two elements) *)
let perturbate ?(num=10) signature =
  let new_signatures = ref [] in
  let len = List.length signature in
  (* swap indexes i and j in the list *)
  let swap i j l = 
    let a = Array.of_list l in
    let tmp = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- tmp;
    Array.to_list a
  in
  (* generate the [num] perturbations *)
  for i = 0 to num-1 do
    let i = Random.int len
    and j = Random.int len in
    if i != j then
      let signature' = swap i j signature in
      new_signatures := signature' :: !new_signatures
  done;
  !new_signatures

(** Hill climbing, on the given list of constraints, for at most the
    given number of steps. It shuffles the signature to try to find
    one that satisfies more constraints.
    See http://en.wikipedia.org/wiki/Hill_climbing *)
let hill_climb ~steps mk_precedence mk_cost signature =
  (* main loop to follow gradient. Current state is precedence, with cost cost *)
  let rec follow_gradient ~steps precedence cost =
    if steps = 0 then precedence, cost else (* done *)
    (* perturbate current precedence *)
    let new_signatures = perturbate precedence#signature in
    (* compute new precedences, and remove the ones which are the same *)
    let new_precedences = List.map mk_precedence new_signatures in
    let new_precedences = List.filter (fun p -> not (eq_precedence p precedence)) new_precedences in
    (* find which new precedence has minimal cost *)
    let min_cost, min_precedence =
      List.fold_left
        (fun (min_cost, min_pre) precedence' ->
          let cost' = mk_cost precedence' in
          if cost' < min_cost then cost', precedence' else min_cost, min_pre)
        (cost, precedence) new_precedences
    in
    (* follow gradient, unless we are at a (local) minimum *)
    if min_cost < cost
      then follow_gradient ~steps:(steps-1) min_precedence min_cost
      else precedence, cost  (* local optimum, stop there *)
  in
  let precedence = mk_precedence signature in
  let cost = mk_cost precedence in
  follow_gradient ~steps precedence cost

(** define a constraint on symbols that is believed to improve
    the search by enabling as many simplifications as possible. It takes
    an ordering as a parameter, to be able to decide the orientation of
    terms in a given precedence, and another constraint to compose  with,
    so that it can optimize w.r.t stronger constraints. *)
let heuristic_precedence ord_factory constr clauses =
  let _, _, signature = current_signature () in
  (* the constraints *)
  let constraints = Utils.list_flatmap
    (fun c -> check_definition c @ check_horn_definition c)
    clauses in
  (* helper functions *)
  let mk_precedence = compute_precedence constr
  and mk_cost = compute_cost ord_factory constraints in
  (* randomized hill climbing *)
  let rec climb_hills ~num precedence cost =
    if num = 0 || cost = 0
      then precedence  (* done enough restarts *)
      else begin
        let signature' = Utils.list_shuffle precedence#signature in
        Utils.debug 2 (lazy (Utils.sprintf "restart with signature %a" T.pp_signature signature'));
        let precedence', cost' = hill_climb ~steps:10 mk_precedence mk_cost signature' in
        if cost' < cost
          then climb_hills ~num:(num-1) precedence' cost' (* choose new precedence *)
          else climb_hills ~num:(num-1) precedence cost   (* continue with same precedence, that is better *)
      end
  in
  let precedence = mk_precedence signature in
  let precedence = climb_hills ~num:5 precedence (mk_cost precedence) in
  (* yield the precedence *)
  precedence