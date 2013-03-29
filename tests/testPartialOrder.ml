(** test partial orderings *)

open Basic
open Symbols

module PO = PartialOrder

let symbs = List.map mk_symbol ["a"; "b"; "c"; "p"; "q"; "r"]

(* cheat : build some term not to have problems with signature *)
let my_term = Terms.mk_node (mk_symbol "a")
  univ_ (List.map (fun s -> Terms.mk_node s univ_ []) symbs)

let alpha_cmp x y = compare (name_symbol x) (name_symbol y)

(* create an order, add stuff in it, etc. *)
let print_order () =
  (* partial ordering (constraint) *)
  let partial_cmp x y =
    match name_symbol x, name_symbol y with
    | "a", "p" -> 1
    | "p", "c" -> 1
    | "p", "a" -> -1
    | "c", "p" -> -1
    | _ -> 0
  in
  let s1 = [mk_symbol "a"; mk_symbol "p"; mk_symbol "b"] in
  let po = PO.mk_partial_order s1 in
  Format.printf "@[<v>initial PO:@ %a@]@." PO.pp po;
  PO.complete po partial_cmp;
  Format.printf "after 'a > p': @[<v>%a@]@." PO.pp po;
  let po = PO.mk_partial_order symbs in
  PO.complete po partial_cmp;
  Format.printf "@[<v>PO after partial extension:@ %a@]@." PO.pp po;
  PO.complete po alpha_cmp;
  Format.printf "@[<v>final PO:@ %a@]@." PO.pp po;
  Format.printf "signature: @[<h>%a@]@." pp_precedence (PO.symbols po);
  ()

let run () =
  print_order ()  
