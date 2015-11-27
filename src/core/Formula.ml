
(*
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

(** {1 First-order Formulas} *)

module T = ScopedTerm
module Sym = Symbol

type symbol = Sym.t
type type_ = Type.t

let prof_simplify = Util.mk_profiler "formula.simplify"

module type S = sig
  type term
  type term_set

  type t = private ScopedTerm.t

  type form = t

  type view = private
    | True
    | False
    | Atom of term
    | And of t list
    | Or of t list
    | Not of t
    | Imply of t * t
    | Equiv of t * t
    | Xor of t * t
    | Eq of term * term
    | Neq of term * term
    | Forall of Type.t * t  (** Quantified formula, with De Bruijn index *)
    | Exists of Type.t * t
    | ForallTy of t  (** quantification on type variable *)

  val view : t -> view
    (** View of the formula *)

  include Interfaces.HASH with type t := t
  include Interfaces.ORD with type t := t

  (** {2 Containers} *)

  module Tbl : Hashtbl.S with type key = t
  module Set : Sequence.Set.S with type elt = t
  module Map : Sequence.Map.S with type key = t

  (** {b Caution}: constructors can raise {!Type.Error} if the types are not
      as expected.  In particular, {!Base.eq} and {!Base.neq} expect two terms
      of the exact same type. *)

  module Base : sig
    val true_ : t
    val false_ : t
    val atom : term -> t
    val not_ : t -> t
    val and_ : t list -> t
    val or_ : t list -> t
    val imply : t -> t -> t
    val equiv : t -> t -> t
    val xor : t -> t -> t
    val eq : term -> term -> t
    val neq : term -> term -> t

    val mk_eq : bool -> term -> term -> t
    val mk_atom : bool -> term -> t

    (** Quantifiers: the term list must be a list of free variables. *)

    val forall : term list -> t -> t
    val exists : term list -> t -> t
    val forall_ty : Type.t list -> t -> t

    val __mk_forall : varty:Type.t -> t -> t
    val __mk_exists : varty:Type.t -> t -> t
    val __mk_forall_ty : t -> t
  end

  (** {2 Sequence} *)

  module Seq : sig
    val terms : t -> term Sequence.t
    val vars : t -> term Sequence.t
    val atoms : t -> t Sequence.t
    val symbols : t -> symbol Sequence.t
  end

  (** {2 Combinators} *)

  val map_leaf : (t -> t) -> t -> t
    (** Call the function on leaves (atom,equal,true,false) and replace the
        leaves by their image. The image formulas should {b not} contain
        free De Bruijn indexes (ie, should verify {! db_closed}). *)

  val map : (term -> term) -> t -> t    (** Map on terms *)
  val fold : ('a -> term -> 'a) -> 'a -> t -> 'a  (** Fold on terms *)
  val iter : (term -> unit) -> t -> unit

  val map_shallow : (t -> t) -> t -> t
    (** Apply the function to the immediate subformulas *)

  val map_depth: ?depth:int ->
                  (int -> term -> term) ->
                  t -> t
    (** Map each term to another term. The number of binders from the root
        of the formula to the term is given to the function. *)

  val map_leaf_depth : ?depth:int ->
                        (int -> t -> t) ->
                        t -> t

  val fold_depth : ?depth:int ->
                ('a -> int -> term -> 'a) ->
                'a -> t -> 'a
    (** Fold on terms, but with an additional argument, the number of
        De Bruijn indexes bound on through the path to the term *)

  val weight : t -> int
    (** Number of 'nodes' of the formula, including the terms *)

  val subterm : term -> t -> bool
    (** [subterm t f] true iff [t] occurs in some term of [f] *)

  val is_atomic : t -> bool   (** No connectives? *)
  val is_ground : t -> bool   (** No variables? *)
  val is_closed : t -> bool   (** All variables bound? *)

  val contains_symbol : Symbol.t -> t -> bool

  val symbols : ?init:Symbol.Set.t -> t -> Symbol.Set.t
    (** Set of symbols occurring in the formula *)

  (** {2 High level operations} *)

  val free_vars_set : t -> term_set (** Set of free variables *)
  val free_vars : t -> term list (** Set of free vars *)

  val close_forall : t -> t   (** Bind all free variables with forall *)
  val close_exists : t -> t   (** Bind all free variables with exists *)

  val open_forall : ?offset:int -> t -> t
    (** Remove outer forall binders, using fresh vars instead of DB symbols *)

  val open_and : t -> t list
    (** If the formula is an outer conjunction, return the list of elements of
        the conjunction *)

  val open_or : t -> t list

  (** {2 Simplifications} *)

  val flatten : t -> t        (** Flatten AC connectives (or/and) *)
  val simplify : t -> t       (** Simplify the formula *)

  val is_trivial : t -> bool  (** Trivially true formula? *)

  val ac_normal_form : t -> t (** Normal form modulo AC of "or" and "and" *)
  val ac_eq : t -> t -> bool  (** Equal modulo AC? *)

  (** {2 Conversions} *)

  val to_simple_term : ?depth:int -> t -> STerm.t

  (** {2 IO} *)

  include Interfaces.PRINT with type t := t
  include Interfaces.PRINT_DE_BRUIJN with type t := t
      and type term := term

  module TPTP : sig
    include Interfaces.PRINT with type t := t
    include Interfaces.PRINT_DE_BRUIJN with type t := t
      and type term := term
      and type print_hook := print_hook
  end

  (* TODO
  include Interfaces.SERIALIZABLE with type t := t
  *)
end

module type TERM = sig
  type t = private ScopedTerm.t

  val of_term_unsafe : ScopedTerm.t -> t

  val ty : t -> Type.t

  val size : t -> int

  include Interfaces.HASH with type t := t
  include Interfaces.ORD with type t := t

  module Seq : sig
    val vars : t -> t Sequence.t
  end

  module Set : Sequence.Set.S with type elt = t

  val to_simple_term : ?depth:int -> t -> STerm.t

  include Interfaces.PRINT_DE_BRUIJN with type t := t
      and type term := t

  val default_hooks : unit -> print_hook list

  module TPTP : sig
    include Interfaces.PRINT_DE_BRUIJN with type t := t
      and type term := t
      and type print_hook := print_hook
  end
end

module Make(MyT : TERM) = struct
  type term = MyT.t
  type term_set = MyT.Set.t

  type t = ScopedTerm.t

  type form = t

  let equal = T.equal
  let compare = T.compare
  let hash = T.hash
  let hash_fun = T.hash_fun

  type view =
    | True
    | False
    | Atom of term
    | And of t list
    | Or of t list
    | Not of t
    | Imply of t * t
    | Equiv of t * t
    | Xor of t * t
    | Eq of term * term
    | Neq of term * term
    | Forall of Type.t * t  (** Quantified formula, with De Bruijn index *)
    | Exists of Type.t * t
    | ForallTy of t  (** quantification on type variable *)

  let view t = match T.view t with
    | T.AppBuiltin (Builtin.True, []) -> True
    | T.AppBuiltin (Builtin.False, []) -> False
    | T.AppBuiltin (Builtin.And, l) -> And l
    | T.AppBuiltin (Builtin.Or, l) -> Or l
    | T.AppBuiltin (Builtin.Not, [a]) -> Not a
    | T.AppBuiltin (conn, [a; b]) ->
        begin match conn with
        | Builtin.Equiv -> Equiv (a,b)
        | Builtin.Xor -> Xor (a,b)
        | Builtin.Imply -> Imply (a,b)
        | Builtin.Eq -> Eq (MyT.of_term_unsafe a, MyT.of_term_unsafe b)
        | Builtin.Neq -> Neq (MyT.of_term_unsafe a, MyT.of_term_unsafe b)
        | _ -> assert false
        end
    | T.Bind (Binder.Forall, varty, f') ->
        Forall (Type.of_term_unsafe varty, f')
    | T.Bind (Binder.Exists, varty, f') ->
        Exists (Type.of_term_unsafe varty, f')
    | T.Bind (Binder.ForallTy, ty, f') when T.equal ty T.tType->
        ForallTy f'
    | _ -> assert false

  let of_term_unsafe t = t

  (** {2 Containers} *)

  module Tbl = Hashtbl.Make(struct
    type t = form
    let equal = equal
    let hash = hash
  end)

  module Set = Sequence.Set.Make(struct
    type t = form
    let compare = compare
  end)

  module Map = Sequence.Map.Make(struct
    type t = form
    let compare = compare
  end)

  (* "type" of a formula *)
  let ty = T.const ~ty:T.tType (Sym.of_string "prop")

  module Base = struct
    let true_ = T.builtin ~ty Builtin.true_
    let false_ = T.builtin ~ty Builtin.false_
    let atom (t:term) = (t:>T.t)

    let imply f1 f2 = T.app_builtin ~ty Builtin.imply [f1; f2]
    let equiv f1 f2 = T.app_builtin ~ty Builtin.equiv [f1; f2]
    let xor f1 f2 = T.app_builtin ~ty Builtin.xor [f1; f2]

    let check_same_ t1 t2 =
      let ty1 = MyT.ty t1 and ty2 = MyT.ty t2 in
      if not (Type.equal ty1 ty2)
        then
          let msg = CCFormat.sprintf
            "Formula.Base.eq: expect same types for %a and %a, got %a and %a"
            (MyT.pp_depth 0) t1 Type.pp ty1 (MyT.pp_depth 0) t2 Type.pp ty2
          in
          raise (Type.Error msg)

    let eq t1 t2 =
      check_same_ t1 t2;
      T.app_builtin ~ty Builtin.eq ([t1; t2] : term list :> T.t list)

    let neq t1 t2 =
      T.app_builtin ~ty Builtin.neq ([t1; t2] : term list :> T.t list)

    let not_ f = match view f with
      | True -> false_
      | False -> true_
      | Eq(a,b) -> neq a b
      | Neq(a,b) -> eq a b
      | Not f' -> f'
      | _ -> T.app_builtin ~ty Builtin.not_ [f]

    let mk_eq sign t1 t2 =
      if sign then eq t1 t2 else neq t1 t2

    let mk_atom sign p =
      if sign then atom p else not_ (atom p)

    let and_ = function
      | [] -> true_
      | [f] -> f
      | l -> T.app_builtin ~ty Builtin.and_ l

    let or_ = function
      | [] -> false_
      | [f] -> f
      | l -> T.app_builtin ~ty Builtin.or_ l

    let __mk_forall ~(varty:Type.t) f =
      T.bind ~ty ~varty:(varty:>T.t) Binder.forall f

    let __mk_exists ~(varty:Type.t) f =
      T.bind ~ty ~varty:(varty:>T.t) Binder.exists f

    let __mk_forall_ty f =
      T.bind ~ty ~varty:T.tType Binder.forall_ty f

    let forall vars f =
      List.fold_right
        (fun (v:term) f ->
          let f' = T.DB.replace (T.DB.shift 1 f) ~sub:(v:>T.t) in
          __mk_forall ~varty:(MyT.ty v) f')
        vars f

    let exists vars f =
      List.fold_right
        (fun (v:term) f ->
          let f' = T.DB.replace (T.DB.shift 1 f) ~sub:(v:>T.t) in
          __mk_exists ~varty:(MyT.ty v) f')
        vars f

    let forall_ty vars f =
      List.fold_right
        (fun (v:Type.t) f ->
          let f' = T.DB.replace (T.DB.shift 1 f) ~sub:(v:>T.t) in
          __mk_forall_ty f')
        vars f
  end

  (** {2 Combinators} *)

  let rec map_leaf f form = match view form with
    | And l -> Base.and_ (List.map (map_leaf f) l)
    | Or l -> Base.or_ (List.map (map_leaf f) l)
    | Imply (f1, f2) -> Base.imply (map_leaf f f1) (map_leaf f f2)
    | Equiv (f1, f2) -> Base.equiv (map_leaf f f1) (map_leaf f f2)
    | Xor (f1, f2) -> Base.xor (map_leaf f f1) (map_leaf f f2)
    | Not f' -> Base.not_ (map_leaf f f')
    | True
    | False
    | Atom _
    | Neq _
    | Eq _ -> f form  (* replace by image *)
    | Forall (varty,f') -> Base.__mk_forall ~varty (map_leaf f f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (map_leaf f f')
    | ForallTy f' -> Base.__mk_forall_ty (map_leaf f f')

  let map (f:term->term) form =
    map_leaf
      (fun form -> match view form with
        | True
        | False -> form
        | Atom p -> Base.atom (f p)
        | Eq (t1, t2) -> Base.eq (f t1) (f t2)
        | Neq (t1, t2) -> Base.neq (f t1) (f t2)
        | _ -> assert false)
      form

  let rec fold_atom f acc form = match view form with
    | And l
    | Or l -> List.fold_left (fold_atom f) acc l
    | Xor (f1, f2)
    | Imply (f1, f2)
    | Equiv (f1, f2) -> fold_atom f (fold_atom f acc f1) f2
    | Not f' -> fold_atom f acc f'
    | True
    | False -> f acc form
    | Atom _ -> f acc form
    | Eq _
    | Neq _ -> f acc form
    | Forall (_,f')
    | Exists (_,f')
    | ForallTy f' -> fold_atom f acc f'

  let fold f acc form =
    fold_atom
      (fun acc form -> match view form with
        | True
        | False -> acc
        | Eq (t1, t2)
        | Neq (t1, t2) -> f (f acc t1) t2
        | Atom p -> f acc p
        | _ -> assert false)
      acc form

  let iter f form = fold (fun () t -> f t) () form

  let map_shallow func f = match view f with
    | And l -> Base.and_ (List.map func l)
    | Or l -> Base.or_ (List.map func l)
    | Imply (f1, f2) -> Base.imply (func f1) (func f2)
    | Equiv (f1, f2) -> Base.equiv (func f1) (func f2)
    | Xor (f1, f2) -> Base.xor (func f1) (func f2)
    | Not f' -> Base.not_ (func f')
    | True
    | False
    | Atom _
    | Eq _
    | Neq _ -> f
    | Forall (varty,f') -> Base.__mk_forall ~varty (func f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (func f')
    | ForallTy f' -> Base.__mk_forall_ty (func f')

  let rec map_depth ?(depth=0) f form = match view form with
    | And l -> Base.and_ (List.map (map_depth ~depth f) l)
    | Or l -> Base.or_ (List.map (map_depth ~depth f) l)
    | Imply (f1, f2) -> Base.imply (map_depth ~depth f f1) (map_depth ~depth f f2)
    | Equiv (f1, f2) -> Base.equiv (map_depth ~depth f f1) (map_depth ~depth f f2)
    | Xor (f1, f2) -> Base.xor (map_depth ~depth f f1) (map_depth ~depth f f2)
    | Not f' -> Base.not_ (map_depth ~depth f f')
    | True
    | False -> form
    | Atom p -> Base.atom (f depth p)
    | Eq (t1, t2) -> Base.eq (f depth t1) (f depth t2)
    | Neq (t1, t2) -> Base.neq (f depth t1) (f depth t2)
    | Forall (varty,f') -> Base.__mk_forall ~varty (map_depth ~depth:(depth+1) f f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (map_depth ~depth:(depth+1) f f')
    | ForallTy f' -> Base.__mk_forall_ty (map_depth ~depth:(depth+1) f f')

  let rec map_leaf_depth ?(depth=0) f form = match view form with
    | And l -> Base.and_ (List.map (map_leaf_depth ~depth f) l)
    | Or l -> Base.or_ (List.map (map_leaf_depth ~depth f) l)
    | Imply (f1, f2) -> Base.imply (map_leaf_depth ~depth f f1) (map_leaf_depth ~depth f f2)
    | Equiv (f1, f2) -> Base.equiv (map_leaf_depth ~depth f f1) (map_leaf_depth ~depth f f2)
    | Xor (f1, f2) -> Base.xor (map_leaf_depth ~depth f f1) (map_leaf_depth ~depth f f2)
    | Not f' -> Base.not_ (map_leaf_depth ~depth f f')
    | True
    | False
    | Atom _
    | Neq _
    | Eq _ -> f depth form  (* replace by image *)
    | Forall (varty,f') -> Base.__mk_forall ~varty (map_leaf_depth ~depth:(depth+1) f f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (map_leaf_depth ~depth:(depth+1) f f')
    | ForallTy f' -> Base.__mk_forall_ty (map_leaf_depth ~depth:(depth+1) f f')

  let fold_depth ?(depth=0) f acc form =
    let rec recurse f acc depth form = match view form with
    | And l
    | Or l -> List.fold_left (fun acc f' -> recurse f acc depth f') acc l
    | Xor (f1, f2)
    | Imply (f1, f2)
    | Equiv (f1, f2) ->
      let acc = recurse f acc depth f1 in
      let acc = recurse f acc depth f2 in
      acc
    | Not f' -> recurse f acc depth f'
    | True
    | False -> acc
    | Atom p -> f acc depth p
    | Neq (t1, t2)
    | Eq (t1, t2) ->
      let acc = f acc depth t1 in
      let acc = f acc depth t2 in
      acc
    | Forall (_, f')
    | Exists (_, f')
    | ForallTy f' ->
      recurse f acc (depth+1) f'
    in
    recurse f acc depth form

  let weight f =
    let rec count n f = match view f with
    | True
    | False -> n + 1
    | Not f'
    | Forall (_,f')
    | Exists (_,f')
    | ForallTy f' -> count (n+1) f'
    | Neq (t1, t2)
    | Eq (t1, t2) -> n + MyT.size t1 + MyT.size t2
    | Atom p -> n + MyT.size p
    | Or l
    | And l -> List.fold_left count (n+1) l
    | Xor (f1, f2)
    | Imply (f1, f2)
    | Equiv (f1, f2) ->
      let n = count (n+1) f1 in
      count n f2
    in
    count 0 f

  module Seq = struct
    let terms f k = iter k f

    let vars f =
      Sequence.flatMap MyT.Seq.vars (terms f)

    let atoms f k =
      fold_atom
        (fun () atom -> k atom)
        () f

    let symbols f = T.Seq.symbols f
  end

  let subterm t f =
    Sequence.exists (MyT.equal t) (Seq.terms f)

  let is_atomic f = match view f with
    | And _
    | Or _
    | Imply _
    | Equiv _
    | Xor _
    | Not _
    | Forall _
    | Exists _
    | ForallTy _ -> false
    | True
    | False
    | Atom _
    | Eq _
    | Neq _ -> true

  let is_ground f = T.ground f

  let free_vars_set f =
      Seq.vars f
        |> Sequence.fold (fun set v -> MyT.Set.add v set) MyT.Set.empty

  let free_vars f = free_vars_set f |> MyT.Set.elements

  let is_closed f = T.DB.closed f

  let contains_symbol sy f =
    Sequence.exists (Symbol.equal sy) (Seq.symbols f)

  let symbols ?(init=Symbol.Set.empty) f =
    Sequence.fold (fun set s -> Symbol.Set.add s set) init (Seq.symbols f)

  (** {2 High level operations} *)

  let close_forall f =
    let fv = free_vars f in
    Base.forall fv f

  let close_exists f =
    let fv = free_vars f in
    Base.exists fv f

  let open_forall ?(offset=0) f =
    let offset = max offset (T.Seq.max_var (T.Seq.vars f)) + 1 in
    (* open next forall, replacing it with a fresh var *)
    let rec open_one offset env f = match view f with
    | Forall (varty,f') ->
      let v = T.var ~ty:(varty:>T.t) offset in
      let env' = DBEnv.push env v in
      open_one (offset+1) env' f'
    | _ ->
      of_term_unsafe (T.DB.eval env f)  (* replace *)
    in
    open_one offset DBEnv.empty f

  let rec open_and f = match view f with
    | And l -> CCList.flat_map open_and l
    | True -> []
    | _ -> [f]

  let rec open_or f = match view f with
    | Or l -> CCList.flat_map open_or l
    | False -> []
    | _ -> [f]

  (** {2 Simplifications} *)

  let rec flatten f =
    match view f with
    | Or _ ->
      let l' = open_or f in
      let l' = List.map flatten l' in
      Base.or_ l'
    | And _ ->
      let l' = open_and f in
      let l' = List.map flatten l' in
      Base.and_ l'
    | Imply (f1, f2) -> Base.imply (flatten f1) (flatten f2)
    | Equiv (f1, f2) -> Base.equiv (flatten f1) (flatten f2)
    | Xor (f1, f2) -> Base.xor (flatten f1) (flatten f2)
    | Not f' -> Base.not_ (flatten f')
    | Forall (varty,f') -> Base.__mk_forall ~varty (flatten f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (flatten f')
    | ForallTy f' -> Base.__mk_forall_ty (flatten f')
    | True
    | False
    | Atom _
    | Eq _
    | Neq _ -> f

  let flag_simplified = T.new_flag()

  let simplify f =
    let rec simplify ~depth f =
      if T.get_flag f flag_simplified then f
      else (
        (* cache result: f' is simplified *)
        let f' = simplify_rec ~depth f in
        T.set_flag f' flag_simplified;
        f'
      )
    and simplify_rec ~depth f = match view f with
      | And l ->
        let l' = List.map (simplify ~depth) l in
        flatten (Base.and_ l')
      | Or l ->
        let l' = List.map (simplify ~depth) l in
        flatten (Base.or_ l')
      | Forall (_,f')
      | Exists (_,f') when not (T.DB.contains f' 0) ->
        simplify ~depth (of_term_unsafe (T.DB.unshift 1 f'))
      | Forall (varty,f') -> Base.__mk_forall ~varty (simplify ~depth:(depth+1) f')
      | Exists (varty,f') -> Base.__mk_exists ~varty (simplify ~depth:(depth+1) f')
      | ForallTy f' -> Base.__mk_forall_ty (simplify ~depth:(depth+1) f')
      | Neq (a, b) when MyT.equal a b -> Base.false_
      | Eq (a,b) when MyT.equal a b -> Base.true_
      | Neq _
      | Eq _ -> f
      | Atom _
      | True
      | False -> f
      | Not f' ->
          let f' = simplify ~depth f' in
          begin match view f' with
          | Xor (f1, f2) -> Base.equiv f1 f2
          | Equiv (f1, f2) -> Base.xor f1 f2
          | Neq (t1, t2) -> Base.eq t1 t2
          | Eq (t1, t2) -> Base.neq t1 t2
          | Imply (f1, f2) -> Base.and_ [f1; simplify ~depth (Base.not_ f2)]
          | Not f' -> f'
          | True -> Base.false_
          | False -> Base.true_
          | _ -> Base.not_ f'
          end
      | Imply (a, b) ->
          let a = simplify ~depth a and b = simplify ~depth b in
          begin match view a, view b with
          | True, _ -> simplify ~depth b
          | False, _
          | _, True -> Base.true_
          | _, False -> simplify ~depth (Base.not_ a)
          | _ -> Base.imply (simplify ~depth a) (simplify ~depth b)
          end
      | Equiv (a, b) ->
          let a = simplify ~depth a and b = simplify ~depth b in
          begin match view a, view b with
          | _ when equal a b -> Base.true_
          | True, _ -> simplify ~depth b
          | _, True -> simplify ~depth a
          | False, _ -> simplify ~depth (Base.not_ b)
          | _, False -> simplify ~depth (Base.not_ a)
          | _ -> Base.equiv (simplify ~depth a) (simplify ~depth b)
          end
      | Xor (f1, f2) ->
          Base.xor (simplify ~depth f1) (simplify ~depth f2) (* TODO *)
    in
    Util.enter_prof prof_simplify;
    let f' = simplify ~depth:0 f in
    Util.exit_prof prof_simplify;
    f'

  let rec is_trivial f = match view f with
    | True -> true
    | Neq _
    | Atom _ -> false
    | Eq (l,r) -> MyT.equal l r
    | False -> false
    | Imply (a, _) when equal a Base.false_ -> true
    | Equiv (l,r) -> equal l r
    | Xor (_, _) -> false
    | Or l -> List.exists is_trivial l
    | And _
    | Imply _
    | Not _ -> false
    | Exists (_,f')
    | Forall (_,f')
    | ForallTy f' -> is_trivial f'

  let ac_normal_form f =
    let rec recurse f = match view f with
    | True
    | False
    | Atom _ -> f
    | Imply (f1, f2) -> Base.imply (recurse f1) (recurse f2)
    | Equiv (f1, f2) -> Base.equiv (recurse f1) (recurse f2)
    | Xor (f1, f2) -> Base.xor (recurse f1) (recurse f2)
    | Not f' -> Base.not_ (recurse f')
    | Eq (t1, t2) ->
      (* put bigger term first *)
      begin match MyT.compare t1 t2 with
      | n when n >= 0 -> f
      | _ -> Base.eq t2 t1
      end
    | Neq (t1, t2) ->
      (* put bigger term first *)
      begin match MyT.compare t1 t2 with
      | n when n >= 0 -> f
      | _ -> Base.neq t2 t1
      end
    | And l ->
      let l' = List.map recurse l in
      let l' = List.sort compare l' in
      Base.and_ l'
    | Or l ->
      let l' = List.map recurse l in
      let l' = List.sort compare l' in
      Base.or_ l'
    | Forall (varty,f') -> Base.__mk_forall ~varty (recurse f')
    | Exists (varty,f') -> Base.__mk_exists ~varty (recurse f')
    | ForallTy f' -> Base.__mk_forall_ty (recurse f')
    in
    recurse (flatten f)

  let ac_eq f1 f2 =
    let f1 = ac_normal_form f1 in
    let f2 = ac_normal_form f2 in
    equal f1 f2

  (** {2 Conversion} *)


  let to_simple_term ?(depth=0) f =
    let module PT = STerm in
    let rec to_simple_term depth f = match view f with
    | True -> PT.TPTP.true_
    | False -> PT.TPTP.false_
    | Not f' -> PT.TPTP.not_ (to_simple_term depth f')
    | And l -> PT.TPTP.and_ (List.map (to_simple_term depth) l)
    | Or l -> PT.TPTP.or_ (List.map (to_simple_term depth) l)
    | Imply (a,b) -> PT.TPTP.imply (to_simple_term depth a) (to_simple_term depth b)
    | Equiv (a,b) -> PT.TPTP.equiv (to_simple_term depth a) (to_simple_term depth b)
    | Xor (a,b) -> PT.TPTP.xor (to_simple_term depth a) (to_simple_term depth b)
    | Eq (a,b) -> PT.TPTP.eq (MyT.to_simple_term ~depth a) (MyT.to_simple_term ~depth b)
    | Neq (a,b) -> PT.TPTP.neq (MyT.to_simple_term ~depth a) (MyT.to_simple_term ~depth b)
    | Atom a -> MyT.to_simple_term ~depth a
    | Forall (tyvar, f') ->
      PT.TPTP.forall
        [PT.column
            (PT.var (CCFormat.sprintf "Y%d" depth))
            (Type.Conv.to_simple_term ~depth tyvar)]
        (to_simple_term (depth+1) f')
    | Exists (tyvar, f') ->
      PT.TPTP.exists
        [PT.column
            (PT.var (CCFormat.sprintf "Y%d" depth))
            (Type.Conv.to_simple_term ~depth tyvar)]
        (to_simple_term (depth+1) f')
    | ForallTy f' ->
      PT.TPTP.forall_ty
        [PT.var (CCFormat.sprintf "A%d" depth)]
        (to_simple_term (depth+1) f')
    in to_simple_term depth f

  (** {2 IO} *)

  type print_hook = int -> (CCFormat.t -> term -> unit) -> CCFormat.t -> term -> bool

  let pp_depth ?(hooks=[]) depth out f =
    let depth = ref depth in
    (* outer formula *)
    let rec pp_outer out f = match view f with
    | True -> CCFormat.string out "true"
    | False -> CCFormat.string out "false"
    | Atom t -> (MyT.pp_depth ~hooks !depth) out t
    | Neq (t1, t2) ->
      Format.fprintf out
        "@[%a ≠ %a@]" (MyT.pp_depth ~hooks !depth) t1 (MyT.pp_depth ~hooks !depth) t2
    | Eq (t1, t2) ->
      Format.fprintf out
        "@[%a = %a@]" (MyT.pp_depth ~hooks !depth) t1 (MyT.pp_depth ~hooks !depth) t2
    | Xor(f1, f2) ->
      Format.fprintf out "@[<hv>%a@ <~>@ %a@]" pp_inner f1 pp_inner f2
    | Equiv (f1, f2) ->
      Format.fprintf out "@[<hv>%a@ <=>@ %a@]" pp_inner f1 pp_inner f2
    | Imply (f1, f2) ->
      Format.fprintf out "@[<hv>%a@ =>@ %a@]" pp_inner f1 pp_inner f2
    | Not f' -> Format.fprintf out "@[¬ %a@]" pp_inner f'
    | Forall (ty,f') ->
      let v = !depth in
      incr depth;
      Format.fprintf out "@[<2>∀ Y%d: %a.@ @[%a@]@]" v Type.pp ty pp_inner f';
      decr depth
    | ForallTy f' ->
      let v = !depth in
      incr depth;
      Format.fprintf out "@[<2>∀ A%d.@ @[%a@]@]" v pp_inner f';
      decr depth
    | Exists (ty, f') ->
      let v = !depth in
      incr depth;
      Format.fprintf out "@[<2>∃ Y%d: %a.@ @[%a@]@]" v Type.pp ty pp_inner f';
      decr depth
    | And l ->
        Format.fprintf out "@[<hv>%a@]"
          (Util.pp_list ~sep:" ∧ " pp_inner) l
    | Or l ->
        Format.fprintf out "@[<hv>%a@]"
          (Util.pp_list ~sep:" ∨ " pp_inner) l
    and pp_inner out f = match view f with
    | And _
    | Or _
    | Equiv _
    | Xor _
    | Imply _ ->
        (* cases where ambiguities could arise *)
        Format.fprintf out "(@[%a@])" pp_outer f
    | _ -> pp_outer out f
    in
    pp_outer out f

  let pp out f = pp_depth ~hooks:(MyT.default_hooks ()) 0 out f

  let to_string f = CCFormat.to_string pp f

  module TPTP = struct
    let pp_depth ?hooks:_ _depth out f =
      let depth = ref 0 in
      (* outer formula *)
      let rec pp_outer out f = match view f with
      | True -> CCFormat.string out "$true"
      | False -> CCFormat.string out "$false"
      | Atom t -> (MyT.TPTP.pp_depth !depth) out t
      | Neq (t1, t2) ->
        Format.fprintf out
          "@[%a != %a@]" (MyT.TPTP.pp_depth !depth) t1 (MyT.TPTP.pp_depth !depth) t2
      | Eq (t1, t2) ->
        Format.fprintf out
          "@[%a = %a@]" (MyT.TPTP.pp_depth !depth) t1 (MyT.TPTP.pp_depth !depth) t2
      | Xor (f1, f2) ->
        Format.fprintf out "@[<hv>%a@ <~>@ %a@]" pp_inner f1 pp_inner f2
      | Equiv (f1, f2) ->
        Format.fprintf out "@[<hv>%a@ <=>@ %a@]" pp_inner f1 pp_inner f2
      | Imply (f1, f2) ->
        Format.fprintf out "@[<hv>%a@ =>@ %a@]" pp_inner f1 pp_inner f2
      | Not f' -> CCFormat.string out "~ "; pp_inner out f'
      | Forall (ty,f') ->
        let v = !depth in
        incr depth;
        if Type.equal ty Type.TPTP.i
          then Format.fprintf out "@[<2>![Y%d]:@ %a@]" v pp_inner f'
          else Format.fprintf out "@[<2>![Y%d:%a]:@ %a@]" v Type.pp ty pp_inner f';
        decr depth
      | ForallTy f' ->
        let v = !depth in
        incr depth;
        Format.fprintf out "@[<2>![A%d:$tType]:@ %a@]" v pp_inner f';
        decr depth
      | Exists (ty, f') ->
        let v = !depth in
        incr depth;
        if Type.equal ty Type.TPTP.i
          then Format.fprintf out "@[<2>?[Y%d]:@ %a@]" v pp_inner f'
          else Format.fprintf out "@[<2>?[Y%d:%a]:@ %a@]" v Type.pp ty pp_inner f';
        decr depth
      | And l ->
        Format.fprintf out "(@[%a@])"
          (Util.pp_list ~sep:" & " pp_inner) l
      | Or l ->
        Format.fprintf out "(@[%a@])"
          (Util.pp_list ~sep:" | " pp_inner) l
      and pp_inner out f = match view f with
      | And _
      | Or _
      | Equiv _
      | Xor _
      | Imply _ ->
        (* cases where ambiguities could arise *)
        Format.fprintf out "(@[%a@])" pp_outer f
      | _ -> pp_outer out f
      in
      pp_outer out f

    let pp = pp_depth 0

    let to_string f = CCFormat.to_string pp f
  end
end

module FO = struct
  include Make(FOTerm)

  let rec to_hoterm f =
    let module T = HOTerm in
    match view f with
    | True -> T.TPTP.true_
    | False -> T.TPTP.false_
    | And l -> T.TPTP.mk_and_list (List.map to_hoterm l)
    | Or l -> T.TPTP.mk_or_list (List.map to_hoterm l)
    | Equiv (f1, f2) -> T.TPTP.mk_equiv (to_hoterm f1) (to_hoterm f2)
    | Imply (f1, f2) -> T.TPTP.mk_imply (to_hoterm f1) (to_hoterm f2)
    | Xor (f1, f2) -> T.TPTP.mk_xor (to_hoterm f1) (to_hoterm f2)
    | Eq (t1, t2) -> T.TPTP.mk_eq (T.curry t1) (T.curry t2)
    | Neq (t1, t2) -> T.TPTP.mk_neq (T.curry t1) (T.curry t2)
    | Not f' -> T.TPTP.mk_not (to_hoterm f')
    | Forall (ty,f') -> T.__mk_forall ~varty:ty (to_hoterm f')
    | Exists (ty,f') -> T.__mk_exists ~varty:ty (to_hoterm f')
    | ForallTy _ -> failwith "HOTerm doesn't support dependent types"
    | Atom p -> T.curry p

  let of_hoterm t =
    let module T = HOTerm in
    let rec recurse t = match T.view t with
      | _ when T.equal t T.TPTP.true_ -> Base.true_
      | _ when T.equal t T.TPTP.false_ -> Base.false_
      | T.At (hd, lam) when T.equal hd T.TPTP.forall ->
          begin match T.view lam with
          | T.Lambda (varty, t') ->
              Base.__mk_forall ~varty (recurse t')
          | _ -> raise Exit
          end
      | T.At (hd, lam) when T.equal hd T.TPTP.exists ->
          begin match T.view lam with
          | T.Lambda (varty, t') ->
              Base.__mk_exists ~varty (recurse t')
          | _ -> raise Exit
          end
      | T.Lambda _ -> raise Exit
      | T.Const s -> Base.atom (FOTerm.const ~ty:(T.ty t) s)
      | T.Var _ | T.BVar _ -> raise Exit
      | _ ->
          (* unroll applications *)
          match T.open_at t with
          | hd, _, l when T.equal hd T.TPTP.and_ -> Base.and_ (List.map recurse l)
          | hd, _, l when T.equal hd T.TPTP.or_ -> Base.or_ (List.map recurse l)
          | hd, _, [a;b] when T.equal hd T.TPTP.equiv ->
              Base.equiv (recurse a) (recurse b)
          | hd, _, [a;b] when T.equal hd T.TPTP.xor ->
              Base.xor (recurse a) (recurse b)
          | hd, _, [a;b] when T.equal hd T.TPTP.imply ->
              Base.imply (recurse a) (recurse b)
          | hd, _, [a;b] when T.equal hd T.TPTP.eq ->
              begin match T.uncurry a, T.uncurry b with
              | Some a, Some b -> Base.eq a b
              | _ -> raise Exit
              end
          | hd, _, [a;b] when T.equal hd T.TPTP.neq ->
              begin match T.uncurry a, T.uncurry b with
              | Some a, Some b -> Base.neq a b
              | _ -> raise Exit
              end
          | _ ->
              begin match T.uncurry t with
              | None -> raise Exit
              | Some p -> Base.atom p
              end
    in
    try Some (recurse t)
    with Exit -> None
end

module Map(From : S)(To : S) = struct
  let map _f form = match From.view form with
    | _ -> assert false (* TODO *)
end
