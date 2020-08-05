(* This file is part of the Catala compiler, a specification language for tax and social benefits
   computation rules. Copyright (C) 2020 Inria, contributor: Nicolas Chataing
   <nicolas.chataing@ens.fr>

   Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
   in compliance with the License. You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software distributed under the License
   is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
   or implied. See the License for the specific language governing permissions and limitations under
   the License. *)

module G = Graph.Pack.Digraph
open Lambda

type uid = int

type scope_uid = int

module UidMap = Uid.UidMap
module UidSet = Uid.UidSet

type exec_context = Lambda.untyped_term UidMap.t

let empty_exec_ctxt = UidMap.empty

let rec substitute (var : uid) (value : Lambda.untyped_term) (term : Lambda.term) : Lambda.term =
  let (term', pos), typ = term in
  let subst = substitute var value in
  let subst_term =
    match term' with
    | EVar uid -> if var = uid then value else term'
    | EFun (bindings, body) -> EFun (bindings, subst body)
    | EApp (f, args) -> EApp (subst f, List.map subst args)
    | EIfThenElse (t_if, t_then, t_else) -> EIfThenElse (subst t_if, subst t_then, subst t_else)
    | EInt _ | EBool _ | EDec _ | EOp _ -> term'
  in
  ((subst_term, pos), typ)

let rec eval_term (exec_ctxt : exec_context) (term : Lambda.term) : Lambda.term =
  let (term, pos), typ = term in
  let evaled_term =
    match term with
    | EFun _ | EInt _ | EDec _ | EBool _ | EOp _ -> term (* already a value *)
    | EVar uid -> ( match UidMap.find_opt uid exec_ctxt with Some t -> t | None -> assert false )
    | EApp (f, args) -> (
        (* First evaluate and match the function body *)
        let f = f |> eval_term exec_ctxt |> Lambda.untype in
        match f with
        | EFun (bindings, body) ->
            let body =
              List.fold_left2
                (fun body arg (uid, _) ->
                  substitute uid (arg |> eval_term exec_ctxt |> Lambda.untype) body)
                body args bindings
            in
            eval_term exec_ctxt body |> Lambda.untype
        | EOp op -> (
            let args = List.map (fun arg -> arg |> eval_term exec_ctxt |> Lambda.untype) args in
            match op with
            | Binop binop -> (
                match binop with
                | And | Or ->
                    let b1, b2 =
                      match args with [ EBool b1; EBool b2 ] -> (b1, b2) | _ -> assert false
                    in
                    EBool (if binop = And then b1 && b2 else b1 || b2)
                | _ -> (
                    let i1, i2 =
                      match args with [ EInt i1; EInt i2 ] -> (i1, i2) | _ -> assert false
                    in
                    match binop with
                    | Add | Sub | Mult | Div ->
                        let op_arith =
                          match binop with
                          | Add -> ( + )
                          | Sub -> ( - )
                          | Mult -> ( * )
                          | Div -> ( / )
                          | _ -> assert false
                        in
                        EInt (op_arith i1 i2)
                    | _ ->
                        let op_comp =
                          match binop with
                          | Lt -> ( < )
                          | Lte -> ( <= )
                          | Gt -> ( > )
                          | Gte -> ( >= )
                          | Eq -> ( = )
                          | Neq -> ( <> )
                          | _ -> assert false
                        in
                        EBool (op_comp i1 i2) ) )
            | Unop Minus -> ( match args with [ EInt i ] -> EInt (-i) | _ -> assert false )
            | Unop Not -> ( match args with [ EBool b ] -> EBool (not b) | _ -> assert false ) )
        | _ -> assert false )
    | EIfThenElse (t_if, t_then, t_else) ->
        ( match eval_term exec_ctxt t_if |> Lambda.untype with
        | EBool b -> if b then eval_term exec_ctxt t_then else eval_term exec_ctxt t_else
        | _ -> assert false )
        |> Lambda.untype
  in
  ((evaled_term, pos), typ)

(* Evaluates a default term : see the formalization for an insight about this operation *)
let eval_default_term (exec_ctxt : exec_context) (term : Lambda.default_term) :
    (Lambda.term, Pos.t list) result =
  (* First filter out the term which justification are false *)
  let candidates =
    IntMap.filter
      (fun _ (cond, _) ->
        match eval_term exec_ctxt cond |> Lambda.untype with EBool b -> b | _ -> assert false)
      term.defaults
  in
  (* Now filter out the terms that have a predecessor which justification is true *)
  let module ISet = Set.Make (Int) in
  let key_candidates = IntMap.fold (fun x _ -> ISet.add x) candidates ISet.empty in
  let chosen_one =
    List.fold_left
      (fun set (lo, hi) -> if ISet.mem lo set && ISet.mem hi set then ISet.remove hi set else set)
      key_candidates term.ordering
  in
  match ISet.elements chosen_one with
  | [ x ] ->
      let _, cons = IntMap.find x term.defaults in
      Ok (eval_term exec_ctxt cons)
  | xs ->
      let pos = xs |> List.map (fun x -> IntMap.find x term.defaults |> fst |> Lambda.get_pos) in
      Error pos

(** Returns the scheduling of the scope variables, if y is a subscope and x a variable of y, then we
    have two different variable y.x(internal) and y.x(result) and the ordering y.x(internal) -> y ->
    y.x(result) *)
let build_scope_schedule (ctxt : Context.context) (scope : Scope.scope) : G.t =
  let g = G.create ~size:100 () in
  let scope_uid = scope.scope_uid in
  (* Add all the vertices to the graph *)
  let vertices =
    UidSet.fold
      (fun uid verts ->
        match Context.get_uid_sort ctxt uid with
        | IdScopeVar | IdSubScope _ -> UidMap.add uid (G.V.create uid) verts
        | _ -> verts)
      (UidMap.find scope_uid ctxt.scopes).uid_set UidMap.empty
  in
  UidMap.iter (fun _ v -> G.add_vertex g v) vertices;
  (* Process definitions dependencies. There are two types of dependencies : var -> var; sub_scope
     -> var *)
  UidMap.iter
    (fun var_uid def ->
      let fv = Lambda.default_term_fv def in
      UidSet.iter
        (fun uid ->
          if Context.belongs_to ctxt uid scope_uid then
            let data = UidMap.find uid ctxt.data in
            let from_uid =
              match data.uid_sort with
              | IdScopeVar -> uid
              | IdSubScopeVar (_, sub_scope_uid) -> sub_scope_uid
              | _ -> assert false
            in
            G.add_edge g (UidMap.find from_uid vertices) (UidMap.find var_uid vertices)
          else ())
        fv)
    scope.scope_defs;
  (* Process sub-definitions dependencies. Only one kind of dependencies : var -> sub_scopes*)
  UidMap.iter
    (fun sub_scope_uid defs ->
      UidMap.iter
        (fun _ def ->
          let fv = Lambda.default_term_fv def in
          UidSet.iter
            (fun var_uid ->
              (* Process only uid from the current scope (not the subscope) *)
              if Context.belongs_to ctxt var_uid scope_uid then
                G.add_edge g (UidMap.find var_uid vertices) (UidMap.find sub_scope_uid vertices)
              else ())
            fv)
        defs)
    scope.scope_sub_defs;
  g

let merge_var_redefs (subscope : Scope.scope) (redefs : Scope.definition UidMap.t) : Scope.scope =
  {
    subscope with
    scope_defs =
      UidMap.fold
        (fun uid new_def sub_defs ->
          match UidMap.find_opt uid sub_defs with
          | None -> UidMap.add uid new_def sub_defs
          | Some old_def ->
              let def = Lambda.merge_default_terms old_def new_def in
              UidMap.add uid def sub_defs)
        redefs subscope.scope_defs;
  }

let rec execute_scope ?(exec_context = empty_exec_ctxt) (ctxt : Context.context)
    (prgm : Scope.program) (scope_prgm : Scope.scope) : exec_context =
  let schedule = build_scope_schedule ctxt scope_prgm in

  (* Printf.printf "Scheduling : "; *)
  (* G.Topological.iter (fun v_uid -> Printf.printf "%s; " (G.V.label v_uid |> Uid.get_ident))
     schedule; *)
  (* Printf.printf "\n"; *)
  G.Topological.fold
    (fun v_uid exec_context ->
      let uid = G.V.label v_uid in
      match Context.get_uid_sort ctxt uid with
      | IdScopeVar -> (
          match UidMap.find_opt uid scope_prgm.scope_defs with
          | Some def -> (
              match eval_default_term exec_context def with
              | Ok value -> UidMap.add uid (Lambda.untype value) exec_context
              | Error pos -> Errors.default_conflict (Uid.get_ident uid) pos )
          | None ->
              Cli.error_print
                (Printf.sprintf "Variable %s is undefined AND unused in scope %s"
                   (Uid.get_ident uid)
                   (Uid.get_ident scope_prgm.scope_uid));
              assert false )
      | IdSubScope sub_scope_ref ->
          (* Merge the new definitions *)
          let sub_scope_prgm = UidMap.find sub_scope_ref prgm in
          let redefs =
            match UidMap.find_opt uid scope_prgm.scope_sub_defs with
            | Some defs -> defs
            | None -> UidMap.empty
          in
          let new_sub_scope_prgm = merge_var_redefs sub_scope_prgm redefs in
          (* Scope.print_scope new_sub_scope_prgm; *)
          let out_context = execute_scope ctxt ~exec_context prgm new_sub_scope_prgm in
          (* Now let's merge back the value from the output context *)
          UidSet.fold
            (fun var_uid exec_context ->
              match Context.get_uid_sort ctxt var_uid with
              | IdSubScopeVar (ref_uid, scope_ref) ->
                  if uid = scope_ref then
                    match Context.get_uid_sort ctxt ref_uid with
                    | IdScopeVar | IdSubScopeVar _ ->
                        let value = UidMap.find ref_uid out_context in
                        UidMap.add var_uid value exec_context
                    | _ -> exec_context
                  else exec_context
              | _ -> exec_context)
            (UidMap.find scope_prgm.scope_uid ctxt.scopes).uid_set exec_context
      | _ -> assert false)
    schedule exec_context