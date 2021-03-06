
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** test orderings *)

open Logtk
open Logtk_arbitrary

module T = FOTerm
module S = Subst.FO
module O = Ordering

(* [more_specific cm1 cm2] is true if [cmp2] is compatible with, and possibly
    more accurate, than [cmp1]. For instance, Incomparable/Gt is ok, but
    not Lt/Eq *)
let more_specific cmp1 cmp2 = Comparison.(match cmp1, cmp2 with
  | Lt, Lt
  | Gt, Gt
  | Eq, Eq
  | Incomparable, _ -> true
  | _, _ -> false
  )

let check_ordering_inv_by_subst ord =
  let name = CCFormat.sprintf "ordering_%s_inv_by_subst" (O.name ord) in
  let pp = QCheck.Print.triple T.to_string T.to_string Subst.to_string in
  (* generate pairs of terms, and grounding substitutions *)
  let gen = QCheck.Gen.(
    (pair ArTerm.default_g ArTerm.default_g)
    >>= fun (t1, t2) ->
    let vars = Sequence.of_list [t1; t2]
      |> Sequence.flat_map T.Seq.vars
      |> T.VarSet.of_seq
    in
    (* grounding substitution *)
    let subst st = T.VarSet.fold
      (fun v subst ->
        let v = (v : Type.t HVar.t :> InnerTerm.t HVar.t) in
        S.bind subst (v,1) (ArTerm.ground_g st,0))
      vars Subst.empty in
    triple (return t1) (return t2) subst)
  in
  let size (t1, t2, s) =
    T.size t1 + T.size t2 +
      (Subst.fold (fun n _ (t,_) -> n + T.size (T.of_term_unsafe t)) 0 s)
  in
  let gen = QCheck.make ~print:pp ~small:size gen in
  (* do type inference on the fly
  let tyctx = TypeInference.Ctx.create () in
  let signature = ref Signature.empty in
  *)
  let ord = ref ord in
  let prop (t1, t2, subst) =
    (* declare symbols *)
    Sequence.of_list [t1;t2]
      |> Sequence.flat_map T.Seq.symbols
      |> ID.Set.of_seq |> ID.Set.to_seq
      |> O.add_seq !ord;
    let t1' = S.apply_no_renaming subst (t1,0) in
    let t2' = S.apply_no_renaming subst (t2,0) in
    (* check that instantiating variables preserves ordering *)
    let o1 = O.compare !ord t1 t2 in
    let o2 = O.compare !ord t1' t2' in
    more_specific o1 o2
  in
  QCheck.Test.make ~count:1000 ~name gen prop

let check_ordering_trans ord =
  let name = CCFormat.sprintf "ordering_%s_transitive" (O.name ord) in
  let arb = QCheck.triple ArTerm.default ArTerm.default ArTerm.default in
  let ord = ref ord in
  let prop (t1, t2, t3) =
    (* declare symbols *)
    Sequence.of_list [t1;t2;t3]
      |> Sequence.flat_map T.Seq.symbols
      |> ID.Set.of_seq |> ID.Set.to_seq
      |> O.add_seq !ord;
    (* check that instantiating variables preserves ordering *)
    let o12 = O.compare !ord t1 t2 in
    let o23 = O.compare !ord t2 t3 in
    if o12 = Comparison.Lt && o23 = Comparison.Lt
    then 
      let o13 = O.compare !ord t1 t3 in
      o13 = Comparison.Lt
    else QCheck.assume_fail ()
  in
  QCheck.Test.make ~count:1000 ~name arb prop

let check_ordering_subterm ord =
  let name = CCFormat.sprintf "ordering_%s_subterm_property" (O.name ord) in
  let arb = ArTerm.default in
  let ord = ref ord in
  let prop t =
    (* declare symbols *)
    Sequence.of_list [t]
      |> Sequence.flat_map T.Seq.symbols
      |> ID.Set.of_seq |> ID.Set.to_seq
      |> O.add_seq !ord;
    T.Seq.subterms_depth t
    |> Sequence.filter_map (fun (t,i) -> if i>0 then Some t else None)
    |> Sequence.for_all
      (fun sub -> O.compare !ord t sub = Comparison.Gt)
  in
  QCheck.Test.make ~count:1000 ~name arb prop

let props =
  CCList.flat_map
    (fun o ->
       [ check_ordering_inv_by_subst o;
         check_ordering_trans o;
         check_ordering_subterm o;
       ])
    [ O.kbo (Precedence.default []);
      O.rpo6 (Precedence.default []);
    ]
