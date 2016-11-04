
(* This file is free software, part of Libzipperposition. See file "license" for more details. *)

(** {1 Meta-Level reasoner} *)

open Libzipperposition

module HOT = TypedSTerm

let section = Util.Section.(make ~parent:zip "meta")

(** {2 Meta-level property}
    A meta-level statement is just a higher-order term. *)

type term = HOT.t
type ty = term
type property = term
type fact = term

let property_id = ID.make "property"
let property_ty = HOT.Ty.const property_id

(** {2 Meta-Level clause}
    A Horn clause about meta-level properties *)

exception Error of string

let () = Printexc.register_printer
  (function
    | Error msg -> Some msg
    | _ -> None)

module Clause = struct
  type t = {
    head : term;
    body : term list;
  }
  type clause = t

  (* find a variable occurring in [head] and not in [body] *)
  let find_unsafe_var head body =
    let vars_body =
      Sequence.of_list body
      |> Sequence.flat_map HOT.Seq.vars
      |> Var.Set.of_seq
    in
    HOT.Seq.vars head
      |> Sequence.find
        (fun v -> if Var.Set.mem vars_body v then None else Some v)

  let rule head body =
    match find_unsafe_var head body with
    | None -> {head; body; }
    | Some v ->
        let msg =
          CCFormat.sprintf
            "@[<2>unsafe Horn clause (var %a):@ @[<2>@[%a@] <-@ @[<hv>%a@]@]@]"
            Var.pp v HOT.pp head (Util.pp_list HOT.pp) body
        in
        raise (Error msg)

  let fact head = rule head []

  let is_fact t = t.body = []

  let equal c1 c2 =
    HOT.equal c1.head c2.head &&
    (try List.for_all2 HOT.equal c1.body c2.body with Invalid_argument _ -> false)

  let pop_body c = match c.body with
    | [] -> failwith "Clause.pop_body"
    | _::body' -> {c with body=body'; }

  let deref_clause c =
    let head = HOT.deref_rec c.head in
    let body = List.map HOT.deref_rec c.body in
    { head; body; }

  module Seq = struct
    let terms c k =
      k c.head; List.iter k c.body
    let vars c = terms c |> Sequence.flat_map HOT.Seq.vars
  end

  let hash_fun c h = CCHash.seq HOT.hash_fun (Seq.terms c) h
  let hash c = CCHash.apply hash_fun c

  let compare c1 c2 =
    let c = HOT.compare c1.head c2.head in
    if c = 0
    then CCOrd.list_ HOT.compare c1.body c2.body
    else c

  let pp out c = match c.body with
    | [] -> Format.fprintf out "@[%a@]." HOT.pp c.head
    | _::_ ->
        Format.fprintf out "@[<hv2>%a@ <- @[<hv>%a@]@]." HOT.pp c.head (Util.pp_list HOT.pp) c.body
  let to_string = CCFormat.to_string pp

  module Set = Sequence.Set.Make(struct
      type t = clause
      let compare = compare
    end)

  module Map = Sequence.Map.Make(struct
      type t = clause
      let compare = compare
    end)
end

type clause = Clause.t

(** {2 Proofs}

    Unit-resolution proofs *)

module Proof = struct
  type t =
    | Axiom
    | Resolved of fact with_proof * clause with_proof

  and 'a with_proof = {
    conclusion : 'a;
    proof : t;
  }

  let rec facts t k = match t with
    | Axiom -> ()
    | Resolved (fact, clause) ->
        k fact.conclusion;
        facts fact.proof k;
        facts clause.proof k

  let rec rules t k = match t with
    | Axiom -> ()
    | Resolved (fact, clause) ->
        k clause.conclusion;
        rules fact.proof k;
        rules clause.proof k

  let make fact proof clause proof' =
    Resolved ({conclusion=fact; proof;}, {conclusion=clause; proof=proof';})
end

type proof = Proof.t


(** {2 Consequences}
    What can be deduced when the Database is updated with new rules
    and facts. *)

type consequence = fact * proof

(** Index.

    For now we don't use indexing, but still use an Index module so that
    the change to a proper indexing structure is easier later *)

module Index = struct
  module M = HOT.Map
  module S = Clause.Set

  type t = S.t M.t

  let empty = M.empty

  let add idx t c =
    let set = try M.find t idx with Not_found -> S.empty in
    let set = S.add c set in
    M.add t set idx

  (* iter on unifiable terms and their associated clause *)
  let retrieve_unify ?(st=HOT.UStack.create()) idx t k =
    let level = HOT.UStack.snapshot ~st in
    M.iter
      (fun t' set ->
         begin
           try
             HOT.unify ~st t' t;
             S.iter k set
           with HOT.UnifyFailure _ -> ()
         end;
         HOT.UStack.restore ~st level)
      idx
end

(** {2 Fact and Rules Database}

    A database contains a set of Horn-clauses about properties, that allow
    to reason about them by forward-chaining. *)

type t = {
  facts : Index.t;
  rules : Index.t;    (* indexed by first lit of body *)
  all : proof Clause.Map.t; (* map clause to proofs *)
} (** A DB that holds a saturated set of Horn clauses and facts *)

let empty = {
  facts = Index.empty;
  rules = Index.empty;
  all = Clause.Map.empty;
}

(* Used for the fixpoint computation *)
type add_state = {
  mutable db : t;
  consequences : consequence Queue.t;
  to_process : (Clause.t * Proof.t) Queue.t;
  renaming : Substs.Renaming.t;
}

(* new state *)
let new_state db = {
  db;
  consequences = Queue.create ();
  to_process = Queue.create ();
  renaming = Substs.Renaming.create ();
}

let __consequences state =
  Sequence.of_queue state.consequences

(* add a fact to the DB *)
let __add_fact ~state ~proof fact =
  Index.retrieve_unify state.db.rules fact
    (fun clause ->
       (* compute resolvent *)
       Substs.Renaming.clear state.renaming;
       let clause' = Clause.deref_clause clause |> Clause.pop_body in
       (* build proof *)
       let proof_clause = Clause.Map.find clause state.db.all in
       let proof' = Proof.make fact proof clause proof_clause in
       Queue.push (clause', proof') state.to_process)

(* add a rule (non unit Horn clause) to the DB *)
let __add_rule ~state ~proof clause =
  match clause.Clause.body with
  | [] -> assert false
  | lit::_ ->
      Index.retrieve_unify state.db.facts lit
        (fun fact_clause ->
           assert (Clause.is_fact fact_clause);
           let fact = fact_clause.Clause.head in
           (* compute resolvent *)
           Substs.Renaming.clear state.renaming;
           let clause' = Clause.deref_clause clause in
           (* build proof *)
           let proof_fact = Clause.Map.find fact_clause state.db.all in
           let proof' = Proof.make fact proof_fact clause proof in
           Queue.push (clause', proof') state.to_process)

(* deal with state.to_process until no clause is to be processed *)
let __process state =
  while not (Queue.is_empty state.to_process) do
    let c, proof = Queue.pop state.to_process in
    if not (Clause.Map.mem c state.db.all)
    then begin
      Util.debugf ~section 5 "meta-reasoner: add clause %a" (fun k->k Clause.pp c);
      (* new clause: insert its proof in state.db.all, then update fixpoint *)
      state.db <- {state.db with all=Clause.Map.add c proof state.db.all;};
      match c.Clause.body with
      | [] ->
          let fact = c.Clause.head in
          (* add fact to consequence if it's not an axiom *)
          if proof <> Proof.Axiom
          then Queue.push (fact,proof) state.consequences;
          (* update fixpoint *)
          __add_fact ~state ~proof c.Clause.head;
          (* add to index *)
          state.db <- {state.db with facts=Index.add state.db.facts fact c; }
      | body1::_ ->
          (* update fixpoint *)
          __add_rule ~state ~proof c;
          (* add [c] to index, by its first literal *)
          state.db <- {state.db with rules=Index.add state.db.rules body1 c; }
    end
  done

(* add a clause to the state *)
let __add state ~proof c =
  Queue.push (c, proof) state.to_process;
  __process state

let add db clause =
  let state = new_state db in
  Queue.push (clause, Proof.Axiom) state.to_process;
  __process state;
  state.db, __consequences state

let add_fact db fact =
  add db (Clause.fact fact)

module Seq = struct
  let to_seq db k =
    Clause.Map.iter
      (fun c proof -> match proof with
         | Proof.Axiom -> k c
         | Proof.Resolved _ -> ())
      db.all

  (* efficient *)
  let of_seq db seq =
    let state = new_state db in
    Sequence.iter (__add state ~proof:Proof.Axiom) seq;
    assert (Queue.is_empty state.to_process);
    state.db, __consequences state

  let facts db =
    to_seq db
    |> Sequence.fmap
      (fun c ->
         match c.Clause.body with
         | [] -> Some c.Clause.head
         | _::_ -> None)
end
