
(* This file is free software, part of Libzipperposition. See file "license" for more details. *)

(** {1 Reduction to CNF of TPTP file} *)

open Libzipperposition
open Libzipperposition_parsers

module T = TypedSTerm
module F = T.Form
module A = Ast_tptp

open CCError.Infix

let print_sig = ref false
let flag_distribute_exists = ref false
let flag_disable_renaming = ref false

let options = Arg.align (
    [ "--signature", Arg.Set print_sig, " print signature"
    ; "--distribute-exist"
        , Arg.Set flag_distribute_exists
        , " distribute existential quantifiers during miniscoping"
    ; "--disable-def", Arg.Set flag_disable_renaming, " disable definitional CNF"
    ; "--time-limit", Arg.Int Util.set_time_limit, " hard time limit (in s)"
    ] @ Options.make ()
  )

let print_res decls = match !Options.output with
  | Options.Print_none -> ()
  | Options.Print_normal ->
      let ppst =
        Statement.pp
          (Util.pp_list ~sep:" ∨ " (SLiteral.pp T.pp)) T.pp T.pp
      in
      Format.printf "@[<v2>%d statements:@ %a@]@."
        (CCVector.length decls)
        (CCVector.print ~start:"" ~stop:"" ~sep:"" ppst)
        decls
  | Options.Print_tptp ->
      let ppst out st =
        Statement.TPTP.pp
          (Util.pp_list ~sep:" | " (SLiteral.TPTP.pp T.TPTP.pp)) T.TPTP.pp T.TPTP.pp
          out st
      in
      Format.printf "@[<v>%a@]@."
        (CCVector.print ~start:"" ~stop:"" ~sep:"" ppst)
        decls
  | Options.Print_zf ->
      let ppst out st =
        Statement.pp
          (Util.pp_list ~sep:" || " (SLiteral.ZF.pp T.ZF.pp)) T.ZF.pp T.ZF.pp
          out st
      in
      Format.printf "@[<v>%a@]@."
        (CCVector.print ~start:"" ~stop:"" ~sep:"" ppst)
        decls

(* process the given file, converting it to CNF *)
let process file =
  Util.debugf 1 "process file %s" (fun k->k file);
  let res =
    (* parse *)
    Parsing_utils.parse file
    >>= TypeInference.infer_statements ?ctx:None
    >|= fun st ->
    let opts =
      (if !flag_distribute_exists then [Cnf.DistributeExists] else []) @
      (if !flag_disable_renaming then [Cnf.DisableRenaming] else []) @
      []
    in
    let decls = Cnf.cnf_of_seq ~opts ?ctx:None (CCVector.to_seq st) in
    let sigma = Cnf.type_declarations (CCVector.to_seq decls) in
    if !print_sig
    then (
      Format.printf "@[<hv2>signature:@ (@[<v>%a@]@])@."
        (ID.Map.print ~start:"" ~stop:"" ~sep:"" ~arrow:" : " ID.pp T.pp) sigma
    );
    (* print *)
    let decls =
      CCVector.map
        (Statement.map_src
          ~f:(fun {UntypedAST.name;_} -> StatementSrc.make ?name file))
        decls
    in
    print_res decls;
    ()
  in match res with
  | `Ok () -> ()
  | `Error msg ->
      print_endline msg;
      exit 1

let main () =
  CCFormat.set_color_default true;
  let files = ref [] in
  let add_file f = files := f :: !files in
  Arg.parse options add_file "cnf_of_tptp [options] [file1|stdin] file2...";
  (if !files = [] then files := ["stdin"]);
  files := List.rev !files;
  List.iter process !files;
  Util.debug 1 "success!";
  ()

let _ =
  main ()
