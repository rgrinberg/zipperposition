
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Induction through Cut} *)

open Libzipperposition

module Lits = Literals
module T = FOTerm
module Su = Substs
module Ty = Type

module type S = Induction_intf.S

let section = Util.Section.make ~parent:Const.section "induction"

let stats_lemmas = Util.mk_stat "induction.lemmas"
let stats_min = Util.mk_stat "induction.assert_min"

let k_enable : bool Flex_state.key = Flex_state.create_key()
let k_ind_depth : int Flex_state.key = Flex_state.create_key()

(* TODO
 in any ground inductive clause C[n]<-Gamma, containing inductive [n]:
   - find path [p], if any (empty at worst)
   - extract context C[]
   - find coverset of [n]
   - for every [n' < n] in the coverset, strengthen the path
     (i.e. if there is [c=t, D[]] in the path with the proper
       type, add [not D[n']], because [n' < n ... < c])
   - add C[t] <- [n=t · p], Gamma
     for every [t] in coverset
   - add boolean clause  [n=t1] or [n=t2] .. or [n=tk] <= Gamma
     where coverset = {t1, t2, ... tk}

  rule to make trivial any clause with >= 2 incompatible path literals
*)

module Make
(E : Env.S)
(A : Avatar_intf.S with module E = E)
= struct
  module Env = E
  module Ctx = E.Ctx
  module C = E.C
  module BoolBox = BBox
  module BoolLit = BoolBox.Lit

  let is_ind_conjecture_ c =
    match C.distance_to_goal c with
    | Some (0 | 1) -> true
    | Some _
    | None -> false

  let has_pos_lit_ c =
    CCArray.exists Literal.is_pos (C.lits c)

  (* terms that are either inductive constants or sub-constants *)
  let constants_or_sub c =
    C.Seq.terms c
    |> Sequence.flat_map T.Seq.subterms
    |> Sequence.filter_map
      (fun t -> match T.view t with
        | T.Const id -> Ind_cst.as_cst id
        | _ -> None)
    |> Sequence.sort_uniq ~cmp:Ind_cst.cst_compare
    |> Sequence.to_rev_list

  (* sub-terms of an inductive type, that occur several times (candidate
     for "subterm generalization" *)
  let generalizable_subterms c =
    let count = T.Tbl.create 16 in
    C.Seq.terms c
      |> Sequence.flat_map T.Seq.subterms
      |> Sequence.filter
        (fun t -> Ind_ty.is_inductive_type (T.ty t) && not (T.is_const t))
      |> Sequence.iter
        (fun t ->
           let n = try T.Tbl.find count t with Not_found -> 0 in
           T.Tbl.replace count t (n+1));
    (* terms that occur more than once *)
    T.Tbl.to_seq count
      |> Sequence.filter_map (fun (t,n) -> if n>1 then Some t else None)
      |> Sequence.to_rev_list

  (* apply the list of replacements [l] to the term [t] *)
  let replace_many l t =
    List.fold_left
      (fun t (old,by) -> T.replace t ~old ~by)
      t l

  (* fresh var generator *)
  let fresh_var_gen_ () =
    let r = ref 0 in
    fun ty ->
      let v = T.var_of_int ~ty !r in
      incr r;
      v

  (* scan terms for inductive constants *)
  let scan_terms seq : Ind_cst.cst list =
    seq
    |> Sequence.flat_map Ind_cst.find_cst_in_term
    |> Sequence.to_rev_list
    |> CCList.sort_uniq ~cmp:Ind_cst.cst_compare

  (* scan clauses for ground terms of an inductive type,
     and declare those terms *)
  let scan_clause c : Ind_cst.cst list =
    C.lits c
    |> Lits.Seq.terms
    |> scan_terms

  let is_eq_ ~path (t1:Ind_cst.cst) (t2:Ind_cst.case) ctxs =
    let p = Ind_cst.path_cons t1 t2 ctxs path in
    BoolBox.inject_case p

  (* TODO: rephrase this in the context of induction *)
  (* exhaustivity (inference):
    if some term [t : tau] is maximal in a clause, [tau] is inductive,
    and [t] was never split on, then introduce
    [t = c1(...) or t = c2(...) or ... or t = ck(...)] where the [ci] are
    constructors of [tau], and [...] are new Skolems of [t];
    if [t] is ground then Avatar splitting (with xor) should apply directly
      instead, as an optimization, with [k] unary clauses and 1 bool clause
  *)

  (* data required for asserting that a constant is the smallest one
     taht makes a conjunction of clause contexts true in the model *)
  type min_witness = {
    mw_cst: Ind_cst.cst;
      (* the constant *)
    mw_contexts: ClauseContext.t list;
      (* the conjunction of contexts for which [cst] is minimal
         (that is, in the model, any term smaller than [cst] makes at
         least one context false) *)
    mw_coverset : Ind_cst.cover_set;
      (* minimality should be asserted for each case of the coverset *)
    mw_path: Ind_cst.path;
      (* path leading to this *)
    mw_proof: ProofStep.t;
  }

  (* recover the (possibly empty) path from a boolean trail *)
  let path_of_trail trail : Ind_cst.path =
    Trail.to_seq trail
    |> Sequence.filter_map BBox.as_case
    |> Sequence.max ~lt:(fun a b -> Ind_cst.path_dominates b a)
    |> CCOpt.get Ind_cst.path_empty

  (* TODO: incremental strenghtening.
     - when expanding a coverset in clauses_of_min_witness, see if there
       are other constants in the path with same type, in which case
     strenghten! *)

  (* for each member [t] of the cover set:
     for each ctx in [mw.mw_contexts]:
      - add ctx[t] <- [cst=t]
      - for each [t' subterm t] of same type, add clause ~[ctx[t']] <- [cst=t]
    @param path the current induction branch
    @param trail precondition to this minimality
  *)
  let clauses_of_min_witness ~trail mw : (C.t list * BoolBox.t list list) =
    let b_lits = ref [] in
    let clauses =
      Ind_cst.cover_set_cases ~which:`All mw.mw_coverset
      |> Sequence.flat_map
        (fun (case:Ind_cst.case) ->
           let b_lit = is_eq_ mw.mw_cst case mw.mw_contexts ~path:mw.mw_path in
           CCList.Ref.push b_lits b_lit;
           (* clauses [ctx[case] <- b_lit] *)
           let pos_clauses =
             List.map
               (fun ctx ->
                  let t = Ind_cst.case_to_term case in
                  let lits = ClauseContext.apply ctx t in
                  C.create_a lits mw.mw_proof ~trail:(Trail.singleton b_lit))
               mw.mw_contexts
           in
           (* clauses [CNF(¬ And_i ctx_i[t']) <- b_lit] for
              each t' subterm of case *)
           let neg_clauses =
             Ind_cst.case_sub_constants case
             |> Sequence.filter_map
               (fun sub ->
                  (* only keep sub-constants that have the same type as [cst] *)
                  let sub = Ind_cst.cst_to_term sub in
                  let ty = Ind_cst.cst_ty mw.mw_cst in
                  if Type.equal (T.ty sub) ty
                  then Some sub else None)
             |> Sequence.flat_map
               (fun sub ->
                  (* for each context, apply it to [sub] and negate its
                     literals, obtaining a DNF of [¬ And_i ctx_i[t']];
                     then turn DNF into CNF *)
                  let clauses =
                    mw.mw_contexts
                    |> Util.map_product
                      ~f:(fun ctx ->
                         let lits = ClauseContext.apply ctx sub in
                         let lits = Array.map Literal.negate lits in
                         [Array.to_list lits])
                    |> List.map
                      (fun lits ->
                         C.create lits mw.mw_proof ~trail:(Trail.singleton b_lit))
                  in
                  Sequence.of_list clauses)
            |> Sequence.to_rev_list
           in
           (* all new clauses *)
           let res = List.rev_append pos_clauses neg_clauses in
           Util.debugf ~section 2
             "@[<2>minimality of `%a`@ in case `%a`:@ @[<hv>%a@]@]"
             (fun k->k Ind_cst.pp_cst mw.mw_cst T.pp (Ind_cst.case_to_term case)
                 (Util.pp_list C.pp) res);
           Sequence.of_list res)
      |> Sequence.to_rev_list
    in
    (* boolean constraint(s) *)
    let b_clauses =
      (* trail => \Or b_lits *)
      let pre = trail |> Trail.to_list |> List.map BoolLit.neg in
      let post = !b_lits in
      [ pre @ post ]
    in
    Util.debugf ~section 2 "@[<2>add boolean constraints@ @[<hv>%a@]@]"
      (fun k->k (Util.pp_list BBox.pp_bclause) b_clauses);
    clauses, b_clauses

  (* ensure the proper declarations are done for this constant *)
  let decl_cst_ cst =
    Util.debugf ~section 3 "@[<2>declare ind.cst. `%a`@]" (fun k->k Ind_cst.pp_cst cst);
    Ind_cst.declarations_of_cst cst
    |> Sequence.iter (fun (id,ty) -> Ctx.declare id ty)

  (* [cst] is the minimal term for which contexts [ctxs] holds, returns
     clauses expressing that, and assert boolean constraints *)
  let assert_min ~trail ~proof ctxs (cst:Ind_cst.cst) =
    let path = path_of_trail trail in
    match Ind_cst.cst_cover_set cst with
      | Some set when not (Ind_cst.path_contains_cst path cst) ->
        decl_cst_ cst;
        let mw = {
          mw_cst=cst;
          mw_contexts=ctxs;
          mw_coverset=set;
          mw_path=path;
          mw_proof=proof;
        } in
        let clauses, b_clauses = clauses_of_min_witness ~trail mw in
        A.Solver.add_clauses ~proof b_clauses;
        Util.incr_stat stats_min;
        clauses
      | Some _ (* path already contains [cst] *)
      | None -> []  (* too deep for induction *)

  (* TODO: trail simplification that removes all path literals except
     the longest? *)

  (* checks whether the trail of [c] is trivial, that is:
     - contains two literals [i = t1] and [i = t2] with [t1], [t2]
        distinct cover set members, or
     - two literals [loop(i) minimal by a] and [loop(i) minimal by b], or
     - two literals [C in loop(i)], [D in loop(j)] if i,j do not depend
        on one another *)
  let has_trivial_trail c =
    let trail = C.trail c |> Trail.to_seq in
    (* all boolean literals that express paths *)
    let relevant_cases = Sequence.filter_map BoolBox.as_case trail in
    (* are there two distinct incompatible paths in the trail? *)
    Sequence.product relevant_cases relevant_cases
    |> Sequence.exists
      (fun (p1, p2) ->
         let res =
           not (Ind_cst.path_equal p1 p2) &&
           not (Ind_cst.path_dominates p1 p2) &&
           not (Ind_cst.path_dominates p2 p1)
         in
         if res
         then (
           Util.debugf ~section 4
             "@[<2>clause@ @[%a@]@ redundant because of@ \
              {@[@[%a@],@,@[%a@]}@] in trail@]"
             (fun k->k C.pp c Ind_cst.pp_path p1 Ind_cst.pp_path p2)
         );
         res)

  (* when a clause contains new inductive constants, assert minimality
     of the clause for all those constants independently *)
  let inf_assert_minimal c =
    let consts = scan_clause c in
    let clauses =
      CCList.flat_map
        (fun cst ->
           decl_cst_ cst;
           let ctx = ClauseContext.extract_exn (C.lits c) (Ind_cst.cst_to_term cst) in
           let proof = ProofStep.mk_inference [C.proof c]
               ~rule:(ProofStep.mk_rule "min") in
           assert_min ~trail:(C.trail c) ~proof [ctx] cst)
        consts
    in
    clauses

  (* clauses when we do induction on [cst] *)
  let induction_on_ ?(trail=Trail.empty) (clauses:C.t list) ~cst : C.t list =
    decl_cst_ cst;
    Util.debugf ~section 1 "@[<2>perform induction on `%a`@ in `@[%a@]`@]"
      (fun k->k Ind_cst.pp_cst cst (Util.pp_list C.pp) clauses);
    (* keep only clauses that depend on [cst] *)
    let ctxs =
      CCList.filter_map
        (fun c ->
           ClauseContext.extract (C.lits c) (Ind_cst.cst_to_term cst))
        clauses
    in
    (* proof: one step from all the clauses above *)
    let proof =
      ProofStep.mk_inference (List.map C.proof clauses)
        ~rule:(ProofStep.mk_rule "min")
    in
    assert_min ~trail ~proof ctxs cst

  (* hook for converting some statements to clauses.
     It check if [Negated_goal l] contains inductive clauses, in which case
     it states their collective minimality.
     It also handles inductive Lemmas *)
  let convert_statement st =
    let consts_of_l l =
      Sequence.of_list l
      |> Sequence.flat_map Sequence.of_list
      |> Sequence.flat_map SLiteral.to_seq
      |> scan_terms
    in
    match Statement.view st with
    | Statement.NegatedGoal l ->
      (* find inductive constants *)
      begin match consts_of_l l with
        | [] -> E.CR_skip
        | consts ->
          (* first, get "proper" clauses *)
          let clauses = C.of_statement st in
          (* for each new inductive constant, assert minimality of
             this constant w.r.t the set of clauses that contain it *)
          consts
          |> CCList.flat_map
            (fun cst -> induction_on_ clauses ~cst)
          |> E.cr_add
        end
    | _ -> E.cr_skip

  let new_lemmas_ : C.t list ref = ref []

  (* look whether, to prove the lemma, we need induction *)
  let on_lemma cut =
    (* find inductive constants in the negative part of the lemma *)
    let consts =
      cut.A.cut_neg
      |> Sequence.of_list
      |> Sequence.flat_map C.Seq.terms
      |> scan_terms
    in
    begin match consts with
      | [] -> () (* regular lemma *)
      | consts ->
        (* add the condition that the lemma is false *)
        let trail = Trail.singleton (BoolLit.neg cut.A.cut_lit) in
        let l =
          CCList.flat_map
            (fun cst -> induction_on_ ~trail cut.A.cut_neg ~cst)
            consts
        in
        new_lemmas_ := List.rev_append l !new_lemmas_;
    end

  let inf_new_lemmas () =
    let l = !new_lemmas_ in
    new_lemmas_ := [];
    l

  let register () =
    Util.debug ~section 2 "register induction";
    let d = Env.flex_get k_ind_depth in
    Util.debugf ~section 2 "maximum induction depth: %d" (fun k->k d);
    Ind_cst.max_depth_ := d;
    Env.add_unary_inf "induction.ind" inf_assert_minimal;
    Env.add_clause_conversion convert_statement;
    Env.add_is_trivial has_trivial_trail;
    Signal.on_every A.on_input_lemma on_lemma;
    Env.add_generate "ind.lemmas" inf_new_lemmas;
    (* declare new constants to [Ctx] *)
    Signal.on_every Ind_cst.on_new_cst decl_cst_;
    ()

  module Meta = struct
    (* TODO *)
    let t : _ Plugin.t = object
      method signature = ID.Map.empty
      method clauses = []
      method owns _ = false
      method to_fact _ = assert false
      method of_fact _ = None (* TODO *)
    end

    (* TODO
    let declare_inductive p ity =
      let ity = Induction.make ity.CI.pattern ity.CI.constructors in
      Util.debugf ~section 2
        "@[<hv2>declare inductive type@ %a@]"
        (fun k->k Induction.print ity);
      let fact = Induction.t#to_fact ity in
      add_fact_ p fact

      (* declare inductive types *)
      E.Ctx.Induction.inductive_ty_seq
        (fun ity -> ignore (declare_inductive p ity));
      Signal.on E.Ctx.Induction.on_new_inductive_ty
        (fun ity ->
           ignore (declare_inductive p ity);
           Signal.ContinueListening
        );
    *)
  end
end

let enabled_ = ref true
let depth_ = ref !Ind_cst.max_depth_

(* if induction is enabled AND there are some inductive types,
   then perform some setup after typing, including setting the key
   [k_enable].
   It will update the parameters. *)
let post_typing_hook stmts state =
  let p = Flex_state.get_exn Params.key state in
  (* only enable if there are inductive types *)
  let should_enable =
    CCVector.exists
      (fun st -> match Statement.view st with
        | Statement.Data _ -> true
        | _ -> false)
      stmts
  in
  if !enabled_ && should_enable then (
    Util.debug ~section 1
      "Enable induction: requires ord=rpo6; select=NoSelection";
    let p = {
      p with Params.
      param_ord = "rpo6";
      param_select = "NoSelection";
    } in
    state
    |> Flex_state.add Params.key p
    |> Flex_state.add k_enable true
    |> Flex_state.add k_ind_depth !depth_
    |> Flex_state.add Ctx.Key.lost_completeness true
  ) else Flex_state.add k_enable false state

(* if enabled: register the main functor, with inference rules, etc. *)
let env_action (module E : Env.S) =
  let is_enabled = E.flex_get k_enable in
  if is_enabled then (
    let (module A) = Avatar.get_env (module E) in
    (* XXX here we do not use E anymore, because we do not know
       that A.E = E. Therefore, it is simpler to use A.E. *)
    let module E = A.E in
    E.Ctx.lost_completeness ();
    E.Ctx.set_selection_fun Selection.no_select;
    let module M = Make(A.E)(A) in
    M.register ();
  )

let extension =
  Extensions.(
    {default with
     name="induction_simple";
     post_typing_actions=[post_typing_hook];
     env_actions=[env_action];
    })

let () =
  Params.add_opts
    [ "--induction", Options.switch_set true enabled_, " enable induction"
    ; "--no-induction", Options.switch_set false enabled_, " enable induction"
    ; "--induction-depth", Arg.Set_int depth_, " maximum depth of nested induction"
    ]
