(* This file is part of the Catala compiler, a specification language for tax
   and social benefits computation rules. Copyright (C) 2020 Inria, contributor:
   Denis Merigoux <denis.merigoux@inria.fr>

   Licensed under the Apache License, Version 2.0 (the "License"); you may not
   use this file except in compliance with the License. You may obtain a copy of
   the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
   WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
   License for the specific language governing permissions and limitations under
   the License. *)
open Utils
open Shared_ast
open Ast
module D = Dcalc.Ast

let ( let+ ) x f = Bindlib.box_apply f x
let ( and+ ) x y = Bindlib.box_pair x y

let visitor_map
    (t : 'a -> 'm expr -> 'm expr Bindlib.box)
    (ctx : 'a)
    (e : 'm expr) : 'm expr Bindlib.box =
  (* calls [t ctx] on every direct childs of [e], then rebuild an abstract
     syntax tree modified. Used in other transformations. *)
  let default_mark e' = Marked.same_mark_as e' e in
  match Marked.unmark e with
  | EVar v ->
    let+ v = Bindlib.box_var v in
    default_mark @@ v
  | ETuple (args, n) ->
    let+ args = args |> List.map (t ctx) |> Bindlib.box_list in
    default_mark @@ ETuple (args, n)
  | ETupleAccess (e1, i, n, ts) ->
    let+ e1 = t ctx e1 in
    default_mark @@ ETupleAccess (e1, i, n, ts)
  | EInj (e1, i, n, ts) ->
    let+ e1 = t ctx e1 in
    default_mark @@ EInj (e1, i, n, ts)
  | EMatch (arg, cases, n) ->
    let+ arg = t ctx arg
    and+ cases = cases |> List.map (t ctx) |> Bindlib.box_list in
    default_mark @@ EMatch (arg, cases, n)
  | EArray args ->
    let+ args = args |> List.map (t ctx) |> Bindlib.box_list in
    default_mark @@ EArray args
  | EAbs (binder, ts) ->
    let vars, body = Bindlib.unmbind binder in
    let body = t ctx body in
    let+ binder = Bindlib.bind_mvar vars body in
    default_mark @@ EAbs (binder, ts)
  | EApp (e1, args) ->
    let+ e1 = t ctx e1
    and+ args = args |> List.map (t ctx) |> Bindlib.box_list in
    default_mark @@ EApp (e1, args)
  | EAssert e1 ->
    let+ e1 = t ctx e1 in
    default_mark @@ EAssert e1
  | EIfThenElse (e1, e2, e3) ->
    let+ e1 = t ctx e1 and+ e2 = t ctx e2 and+ e3 = t ctx e3 in
    default_mark @@ EIfThenElse (e1, e2, e3)
  | ECatch (e1, exn, e2) ->
    let+ e1 = t ctx e1 and+ e2 = t ctx e2 in
    default_mark @@ ECatch (e1, exn, e2)
  | ERaise _ | ELit _ | EOp _ -> Bindlib.box e

let rec iota_expr (_ : unit) (e : 'm expr) : 'm expr Bindlib.box =
  let default_mark e' = Marked.mark (Marked.get_mark e) e' in
  match Marked.unmark e with
  | EMatch ((EInj (e1, i, n', _ts), _), cases, n) when EnumName.compare n n' = 0
    ->
    let+ e1 = visitor_map iota_expr () e1
    and+ case = visitor_map iota_expr () (List.nth cases i) in
    default_mark @@ EApp (case, [e1])
  | EMatch (e', cases, n)
    when cases
         |> List.mapi (fun i (case, _pos) ->
                match case with
                | EInj (_ei, i', n', _ts') ->
                  i = i' && (* n = n' *) EnumName.compare n n' = 0
                | _ -> false)
         |> List.for_all Fun.id ->
    visitor_map iota_expr () e'
  | _ -> visitor_map iota_expr () e

let rec beta_expr (_ : unit) (e : 'm expr) : 'm expr Bindlib.box =
  let default_mark e' = Marked.same_mark_as e' e in
  match Marked.unmark e with
  | EApp (e1, args) -> (
    let+ e1 = beta_expr () e1
    and+ args = List.map (beta_expr ()) args |> Bindlib.box_list in
    match Marked.unmark e1 with
    | EAbs (binder, _ts) ->
      let (_ : (_, _) Bindlib.mbinder) = binder in
      Bindlib.msubst binder (List.map fst args |> Array.of_list)
    | _ -> default_mark @@ EApp (e1, args))
  | _ -> visitor_map beta_expr () e

let iota_optimizations (p : 'm program) : 'm program =
  let new_scopes =
    Scope.map_exprs ~f:(iota_expr ()) ~varf:(fun v -> v) p.scopes
  in
  { p with scopes = Bindlib.unbox new_scopes }

(* TODO: beta optimizations apply inlining of the program. We left the inclusion
   of beta-optimization as future work since its produce code that is harder to
   read, and can produce exponential blowup of the size of the generated
   program. *)
let _beta_optimizations (p : 'm program) : 'm program =
  let new_scopes =
    Scope.map_exprs ~f:(beta_expr ()) ~varf:(fun v -> v) p.scopes
  in
  { p with scopes = Bindlib.unbox new_scopes }

let rec peephole_expr (_ : unit) (e : 'm expr) :
    'm expr Bindlib.box =
  let default_mark e' = Marked.mark (Marked.get_mark e) e' in

  match Marked.unmark e with
  | EIfThenElse (e1, e2, e3) -> (
    let+ e1 = peephole_expr () e1
    and+ e2 = peephole_expr () e2
    and+ e3 = peephole_expr () e3 in
    match Marked.unmark e1 with
    | ELit (LBool true)
    | EApp ((EOp (Unop (Log _)), _), [(ELit (LBool true), _)]) ->
      e2
    | ELit (LBool false)
    | EApp ((EOp (Unop (Log _)), _), [(ELit (LBool false), _)]) ->
      e3
    | _ -> default_mark @@ EIfThenElse (e1, e2, e3))
  | ECatch (e1, except, e2) -> (
    let+ e1 = peephole_expr () e1 and+ e2 = peephole_expr () e2 in
    match Marked.unmark e1, Marked.unmark e2 with
    | ERaise except', ERaise except'' when except' = except && except = except''
      ->
      default_mark @@ ERaise except
    | ERaise except', _ when except' = except -> e2
    | _, ERaise except' when except' = except -> e1
    | _ -> default_mark @@ ECatch (e1, except, e2))
  | _ -> visitor_map peephole_expr () e

let peephole_optimizations (p : 'm program) : 'm program =
  let new_scopes =
    Scope.map_exprs ~f:(peephole_expr ()) ~varf:(fun v -> v) p.scopes
  in
  { p with scopes = Bindlib.unbox new_scopes }

let optimize_program (p : 'm program) : untyped program =
  p |> iota_optimizations |> peephole_optimizations |> Program.untype
