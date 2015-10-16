#!/usr/bin/env ocaml

(* run tests *)

#use "topfind";;
#require "gen";;
#require "containers";;
#require "containers.string";;
#require "containers.unix";;

type result =
  | Sat
  | Unsat
  | Error

let pp_result out e =
  Format.fprintf out "%s"
    (match e with Sat -> "sat" | Unsat -> "unsat" | Error -> "error")

(* what is expected? *)
let find_expected f =
  if CCString.mem ~sub:"unsat" f then Unsat
  else if CCString.mem ~sub:"sat" f then Sat
  else if CCString.mem ~sub:"error" f then Error
  else (* inline *)
    CCIO.with_in f
      (fun ic ->
        let g = CCIO.read_lines ic
          |> Gen.map String.trim
          |> Gen.map String.lowercase
          |> Gen.filter_map
            (function
              | "# expect: sat" -> Some Sat
              | "# expect: unsat" -> Some Unsat
              | "# expect: error"
              | "# expect: fail" -> Some Error
              | _ -> None
            )
        in
        match g() with
        | None -> failwith ("cannot read expected result for " ^ f)
        | Some r -> r
      )

(* run test for [f] , and return [true] if test was ok *)
let test_file f =
  Format.printf "running %-30s... @?" f;
  (* expected result *)
  let expected = find_expected f in
  let options =
    (if CCString.mem ~sub:"ARI" f
      then "-arith -arith-inf-diff-to-lesseq" else "")
  in
  let p = CCUnix.call
    "./zipperposition.native -timeout 5 %s -theory src/builtin.theory %s" options f
  in
  let actual =
    if p#errcode <> 0 then Error
    else
      if CCString.mem ~sub:"status Theorem" p#stdout
        || CCString.mem ~sub:"status Unsatisfiable" p#stdout then Unsat
      else if CCString.mem ~sub:"status CounterSatisfiable" p#stdout
        || CCString.mem ~sub:"status Satisfiable" p#stdout then Sat
      else Error
  in
  if expected = actual
  then (Format.printf "\x1b[32;1mok\x1b[0m@."; true)
  else (
    Format.printf "\x1b[31;1mfailure\x1b[0m: expected `%a`, got `%a`@."
      pp_result expected pp_result actual;
    false
  )

(* find list of files to test *)
let gather_files () =
  CCIO.File.read_dir ~recurse:true "tests/"
  |> Gen.filter (CCString.suffix ~suf:".p")
  |> Gen.to_rev_list
  |> List.sort Pervasives.compare

let () =
  Arg.parse [] (fun _ -> failwith "no arguments") "./tests/run.ml";
  let files = gather_files () in
  Format.printf "run %d tests@." (List.length files);
  let num_failed = List.fold_left
    (fun acc f ->
      let ok = test_file f in
      (if ok then 0 else 1) + acc
    )
    0 files
  in
  if num_failed = 0
  then Format.printf "success.@."
  else (
    Format.printf "%d test(s) failed@." num_failed;
    exit 1
  )
