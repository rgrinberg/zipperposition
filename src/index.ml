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

(** Generic term indexing *)

open Types

module T = Terms
module C = Clauses
module Utils = FoUtils

type data = clause * position * term

(** a set of (hashconsed clause, position in clause, term). *)
module ClauseSet : Set.S with type elt = data
  = Set.Make(
      struct 
      type t = data

      let compare (c1, p1, t1) (c2, p2, t2) = 
        let c = Pervasives.compare p1 p2 in
        if c <> 0 then c else
        let c = C.compare_clause c1 c2 in
        if c <> 0 then c else
        (assert (T.eq_term t1 t2); 0)
    end)

(** a leaf of an index is generally a map of terms to data *)
type index_leaf = (term * ClauseSet.t) Ptmap.t

let empty_leaf = Ptmap.empty

let add_leaf leaf t data =
  let set =
    try snd (Ptmap.find t.tag leaf)
    with Not_found -> ClauseSet.empty in
  let set = ClauseSet.add data set in
  Ptmap.add t.tag (t, set) leaf

let remove_leaf leaf t data =
  try
    let t', set = Ptmap.find t.tag leaf in
    assert (T.eq_term t t');
    let set = ClauseSet.remove data set in
    if ClauseSet.is_empty set
      then Ptmap.remove t.tag leaf
      else Ptmap.add t.tag (t, set) leaf
  with Not_found -> leaf

let is_empty_leaf leaf = Ptmap.is_empty leaf

let iter_leaf leaf f =
  Ptmap.iter (fun _ (t, set) -> f t set) leaf

let fold_leaf leaf f acc =
  Ptmap.fold (fun _ (t, set) acc -> f acc t set) leaf acc

let size_leaf leaf =
  let cnt = ref 0 in
  Ptmap.iter (fun _ _ -> incr cnt) leaf;
  !cnt

(** A term index *)
class type index =
  object ('b)
    method name : string
    method add : term -> data -> 'b
    method remove: term -> data -> 'b

    method iter : (term -> ClauseSet.t -> unit) -> unit
    method fold : 'a. ('a -> term -> ClauseSet.t -> 'a) -> 'a -> 'a

    method retrieve_unifiables : 'a. term -> 'a ->
                                 ('a -> term -> ClauseSet.t -> 'a) -> 'a
    method retrieve_generalizations : 'a. term -> 'a ->
                                      ('a -> term -> ClauseSet.t -> 'a) -> 'a
    method retrieve_specializations : 'a. term -> 'a ->
                                      ('a -> term -> ClauseSet.t -> 'a) -> 'a

    method pp : all_clauses:bool -> Format.formatter -> unit -> unit
  end

(** A simplification index *)
class type unit_index = 
  object ('b)
    method name : string
    method add : term -> term -> bool -> clause -> 'b    (** add (in)equation (with given ID) *)
    method remove : term -> term -> bool -> clause ->'b  (** remove (in)equation (with given ID) *)
    method retrieve : sign:bool -> term ->
                      (term -> term -> substitution -> clause -> unit) ->
                      unit                      (** iter on (in)equations of given sign l=r
                                                    where subst(l) = query term *)
    method pp : Format.formatter -> unit -> unit
  end

(** A global index, that operates on hashconsed clauses *)
class type clause_index =
  object ('a)
    method index_clause : ord:ordering -> clause -> 'a
    method remove_clause : ord:ordering -> clause -> 'a

    method root_index : index
    method unit_root_index : unit_index (** for simplifications that only require matching *)
    method ground_rewrite_index : (term * data) Ptmap.t (** to rewrite ground terms *)
    method subterm_index : index

    method pp : all_clauses:bool -> Format.formatter -> unit -> unit
  end


(** process the literal (only its maximal side(s)) *)
let process_lit ~ord op c tree ({lit_eqn=Equation (l,r,sign)}, pos) =
  match ord#compare l r with
  | Gt -> op tree l (c, [C.left_pos; pos])
  | Lt -> op tree r (c, [C.right_pos; pos])
  | Incomparable ->
    let tmp_tree = op tree l (c, [C.left_pos; pos]) in
    op tmp_tree r (c, [C.right_pos; pos])
  | Eq ->
    Utils.debug 4 (lazy (Utils.sprintf "add %a = %a to index"
                   !T.pp_term#pp l !T.pp_term#pp r));
    op tree l (c, [C.left_pos; pos])  (* only index one side *)

let process_unit_lit ~ord ({lit_eqn=Equation (l,r,sign)}) hc op tree =
  match ord#compare l r with
  | Gt -> op tree l r sign hc
  | Lt -> op tree r l sign hc
  | Incomparable -> 
    let tree' = op tree l r sign hc in
    op tree' r l sign hc
  | Eq ->
    Utils.debug 4 (lazy (Utils.sprintf "add %a = %a to unit index"
                   !T.pp_term#pp l !T.pp_term#pp r));
    op tree l r sign hc  (* only index one side *)


(** apply op to the maximal literals of the clause, and only to
    the maximal side(s) of those, if restrict is true. Otherwise
    process all literals *)
let process_clause ~restrict ~ord op tree c =
  (* which literals to process? *)
  let eligible lit =
    if restrict && c.cselected = 0 then lit.lit_maximal
    else if restrict then lit.lit_selected
    else true in
  let tree = ref tree in
  Array.iteri
    (fun i lit -> if eligible lit then tree := process_lit ~ord op c !tree (lit, i))
    c.clits;
  !tree

(** apply (op tree) to all subterms, folding the resulting tree *)
let rec fold_subterms op tree t (c, path) =
  match t.term with
  | Var _ -> tree  (* variables are not indexed *)
  | Node (_, []) -> op tree t (c, List.rev path, t) (* reverse path now *)
  | Node (_, l) ->
      (* apply the operation on the term itself *)
      let tmp_tree = op tree t (c, List.rev path, t) in
      let _, new_tree = List.fold_left
        (* apply the operation on each i-th subterm with i::path
           as position. i starts at 0 and the function symbol is ignored. *)
        (fun (idx, tree) t -> idx+1, fold_subterms op tree t (c, idx::path))
        (0, tmp_tree) l
      in new_tree

(** apply (op tree) to the root term, after reversing the path *)
let apply_root_term op tree t (c, path) = op tree t (c, List.rev path, t)

(** size of a Ptmap *)
let ptmap_size m =
  let size = ref 0 in
  Ptmap.iter (fun _ _ -> incr size) m;
  !size

let mk_clause_index (index : index) (unit_index : unit_index) =
  object (_: 'self)
    val _root_index = index
    val _subterm_index = index
    val _unit_root_index = unit_index
    val _ground_rewrite_index = Ptmap.empty

    (** add root terms and subterms to respective indexes *)
    method index_clause ~ord hc =
      let op tree = tree#add in
      let new_subterm_index = process_clause ~ord ~restrict:true (fold_subterms op) _subterm_index hc
      and new_unit_root_index = match hc.clits with
          | [|lit|] -> process_unit_lit ~ord lit hc op _unit_root_index
          | _ -> _unit_root_index
      and new_ground_rewrite_index =
        match hc.clits with
        | [|{lit_eqn=Equation (l,r,true)}|] when T.is_ground_term l && ord#compare l r = Gt ->
            Ptmap.add l.tag (r, (hc, [0; C.left_pos], l)) _ground_rewrite_index
        | [|{lit_eqn=Equation (l,r,true)}|] when T.is_ground_term r && ord#compare l r = Lt->
            Ptmap.add r.tag (l, (hc, [0; C.right_pos], r)) _ground_rewrite_index
        | _ -> _ground_rewrite_index
      and new_root_index = process_clause ~ord ~restrict:true (apply_root_term op) _root_index hc
      in ({< _root_index=new_root_index;
            _unit_root_index=new_unit_root_index;
            _ground_rewrite_index=new_ground_rewrite_index;
            _subterm_index=new_subterm_index >} :> 'self)

    (** remove root terms and subterms from respective indexes *)
    method remove_clause ~ord hc =
      let op tree = tree#remove in
      let new_subterm_index = process_clause ~ord ~restrict:true (fold_subterms op) _subterm_index hc
      and new_unit_root_index = match hc.clits with
          | [|lit|] -> process_unit_lit ~ord lit hc op _unit_root_index
          | _ -> _unit_root_index
      and new_ground_rewrite_index =
        match hc.clits with
        | [|{lit_eqn=Equation (l,r,true)}|] when T.is_ground_term l && ord#compare l r = Gt ->
            Ptmap.remove l.tag _ground_rewrite_index
        | [|{lit_eqn=Equation (l,r,true)}|] when T.is_ground_term r && ord#compare l r = Lt->
            Ptmap.remove r.tag _ground_rewrite_index
        | _ -> _ground_rewrite_index
      and new_root_index = process_clause ~ord ~restrict:true (apply_root_term op) _root_index hc
      in ({< _root_index=new_root_index;
            _unit_root_index=new_unit_root_index;
            _ground_rewrite_index=new_ground_rewrite_index;
            _subterm_index=new_subterm_index >} :> 'self)

    method root_index = _root_index
    method unit_root_index = _unit_root_index
    method ground_rewrite_index = _ground_rewrite_index
    method subterm_index = _subterm_index

    method pp ~all_clauses formatter () =
      Format.fprintf formatter
        ("clause_index:@.root_index=@[<v>%a@]@.unit_root_index=@[<v>%a@]@." ^^
         "ground_rewrite_index=%d rules@.subterm_index=@[<v>%a@]@.")
        (_root_index#pp ~all_clauses) ()
        _unit_root_index#pp ()
        (ptmap_size _ground_rewrite_index)
        (_subterm_index#pp ~all_clauses) ()
  end
