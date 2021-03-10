(* This file is part of the Catala compiler, a specification language for tax and social benefits
   computation rules. Copyright (C) 2020 Inria, contributor: Denis Merigoux
   <denis.merigoux@inria.fr>

   Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
   in compliance with the License. You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software distributed under the License
   is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
   or implied. See the License for the specific language governing permissions and limitations under
   the License. *)

open Utils
open Ast

let typ_needs_parens (e : typ Pos.marked) : bool =
  match Pos.unmark e with TArrow _ | TArray _ -> true | _ -> false

let is_uppercase (x : CamomileLibraryDefault.Camomile.UChar.t) : bool =
  try
    match CamomileLibraryDefault.Camomile.UCharInfo.general_category x with
    | `Ll -> false
    | `Lu -> true
    | _ -> false
  with _ -> true

let begins_with_uppercase (s : string) : bool =
  let first_letter = CamomileLibraryDefault.Camomile.UTF8.get s 0 in
  is_uppercase first_letter

let format_uid_list (fmt : Format.formatter) (infos : Uid.MarkedString.info list) : unit =
  Format.fprintf fmt "%a"
    (Format.pp_print_list
       ~pp_sep:(fun fmt () -> Format.fprintf fmt ".")
       (fun fmt info ->
         Format.fprintf fmt "%s"
           (Utils.Cli.print_with_style
              (if begins_with_uppercase (Pos.unmark info) then [ ANSITerminal.red ] else [])
              "%s"
              (Format.asprintf "%a" Utils.Uid.MarkedString.format_info info))))
    infos

let format_tlit (fmt : Format.formatter) (l : typ_lit) : unit =
  match l with
  | TUnit -> Format.fprintf fmt "unit"
  | TBool -> Format.fprintf fmt "bool"
  | TInt -> Format.fprintf fmt "integer"
  | TRat -> Format.fprintf fmt "decimal"
  | TMoney -> Format.fprintf fmt "money"
  | TDuration -> Format.fprintf fmt "duration"
  | TDate -> Format.fprintf fmt "date"

let rec format_typ (ctx : Ast.decl_ctx) (fmt : Format.formatter) (typ : typ Pos.marked) : unit =
  let format_typ = format_typ ctx in
  let format_typ_with_parens (fmt : Format.formatter) (t : typ Pos.marked) =
    if typ_needs_parens t then Format.fprintf fmt "(%a)" format_typ t
    else Format.fprintf fmt "%a" format_typ t
  in
  match Pos.unmark typ with
  | TLit l -> Format.fprintf fmt "%a" format_tlit l
  | TTuple (ts, None) ->
      Format.fprintf fmt "@[<hov 2>(%a)@]"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt "@ *@ ")
           (fun fmt t -> Format.fprintf fmt "%a" format_typ t))
        ts
  | TTuple (ts, Some s) ->
      Format.fprintf fmt "%a @[<hov 2>{@ %a@ }@]" Ast.StructName.format_t s
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt ";@ ")
           (fun fmt (t, f) ->
             Format.fprintf fmt "%a:@ %a" Ast.StructFieldName.format_t f format_typ t))
        (List.combine ts (List.map fst (Ast.StructMap.find s ctx.ctx_structs)))
  | TEnum (ts, e) ->
      Format.fprintf fmt "%a [@[<hov 2>%a@]]" Ast.EnumName.format_t e
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt "@ |@ ")
           (fun fmt (t, f) ->
             Format.fprintf fmt "%a:@ %a" Ast.EnumConstructor.format_t f format_typ t))
        (List.combine ts (List.map fst (Ast.EnumMap.find e ctx.ctx_enums)))
  | TArrow (t1, t2) ->
      Format.fprintf fmt "@[<hov 2>%a →@ %a@]" format_typ_with_parens t1 format_typ t2
  | TArray t1 -> Format.fprintf fmt "@[%a@ array@]" format_typ t1
  | TAny -> Format.fprintf fmt "any"

let format_lit (fmt : Format.formatter) (l : lit Pos.marked) : unit =
  match Pos.unmark l with
  | LBool b -> Format.fprintf fmt "%b" b
  | LInt i -> Format.fprintf fmt "%s" (Runtime.integer_to_string i)
  | LEmptyError -> Format.fprintf fmt "∅"
  | LUnit -> Format.fprintf fmt "()"
  | LRat i ->
      Format.fprintf fmt "%s"
        (Runtime.decimal_to_string ~max_prec_digits:!Utils.Cli.max_prec_digits i)
  | LMoney e -> (
      match !Utils.Cli.locale_lang with
      | `En -> Format.fprintf fmt "$%s" (Runtime.money_to_string e)
      | `Fr -> Format.fprintf fmt "%s €" (Runtime.money_to_string e) )
  | LDate d -> Format.fprintf fmt "%s" (Runtime.date_to_string d)
  | LDuration d -> Format.fprintf fmt "%s" (Runtime.duration_to_string d)

let format_op_kind (fmt : Format.formatter) (k : op_kind) =
  Format.fprintf fmt "%s"
    (match k with KInt -> "" | KRat -> "." | KMoney -> "$" | KDate -> "@" | KDuration -> "^")

let format_binop (fmt : Format.formatter) (op : binop Pos.marked) : unit =
  match Pos.unmark op with
  | Add k -> Format.fprintf fmt "+%a" format_op_kind k
  | Sub k -> Format.fprintf fmt "-%a" format_op_kind k
  | Mult k -> Format.fprintf fmt "*%a" format_op_kind k
  | Div k -> Format.fprintf fmt "/%a" format_op_kind k
  | And -> Format.fprintf fmt "%s" "&&"
  | Or -> Format.fprintf fmt "%s" "||"
  | Eq -> Format.fprintf fmt "%s" "="
  | Neq -> Format.fprintf fmt "%s" "!="
  | Lt k -> Format.fprintf fmt "%s%a" "<" format_op_kind k
  | Lte k -> Format.fprintf fmt "%s%a" "<=" format_op_kind k
  | Gt k -> Format.fprintf fmt "%s%a" ">" format_op_kind k
  | Gte k -> Format.fprintf fmt "%s%a" ">=" format_op_kind k
  | Map -> Format.fprintf fmt "map"
  | Filter -> Format.fprintf fmt "filter"

let format_ternop (fmt : Format.formatter) (op : ternop Pos.marked) : unit =
  match Pos.unmark op with Fold -> Format.fprintf fmt "fold"

let format_log_entry (fmt : Format.formatter) (entry : log_entry) : unit =
  match entry with
  | VarDef -> Format.fprintf fmt "%s" (Utils.Cli.print_with_style [ ANSITerminal.blue ] "≔ ")
  | BeginCall -> Format.fprintf fmt "%s" (Utils.Cli.print_with_style [ ANSITerminal.yellow ] "→ ")
  | EndCall -> Format.fprintf fmt "%s" (Utils.Cli.print_with_style [ ANSITerminal.yellow ] "← ")
  | PosRecordIfTrueBool ->
      Format.fprintf fmt "%s" (Utils.Cli.print_with_style [ ANSITerminal.green ] "☛ ")

let format_unop (fmt : Format.formatter) (op : unop Pos.marked) : unit =
  Format.fprintf fmt "%s"
    ( match Pos.unmark op with
    | Minus _ -> "-"
    | Not -> "~"
    | ErrorOnEmpty -> "error_empty"
    | Log (entry, infos) ->
        Format.asprintf "log@[<hov 2>[%a|%a]@]" format_log_entry entry
          (Format.pp_print_list
             ~pp_sep:(fun fmt () -> Format.fprintf fmt ".")
             (fun fmt info -> Utils.Uid.MarkedString.format_info fmt info))
          infos
    | Length -> "length"
    | IntToRat -> "int_to_rat"
    | GetDay -> "get_day"
    | GetMonth -> "get_month"
    | GetYear -> "get_year" )

let needs_parens (e : expr Pos.marked) : bool =
  match Pos.unmark e with EAbs _ | EApp _ -> true | _ -> false

let format_var (fmt : Format.formatter) (v : Var.t) : unit =
  Format.fprintf fmt "%s" (Bindlib.name_of v)

let rec format_expr (ctx : Ast.decl_ctx) (fmt : Format.formatter) (e : expr Pos.marked) : unit =
  let format_expr = format_expr ctx in
  let format_with_parens (fmt : Format.formatter) (e : expr Pos.marked) =
    if needs_parens e then Format.fprintf fmt "(%a)" format_expr e
    else Format.fprintf fmt "%a" format_expr e
  in
  match Pos.unmark e with
  | EVar v -> Format.fprintf fmt "%a" format_var (Pos.unmark v)
  | ETuple (es, None) ->
      Format.fprintf fmt "@[<hov 2>(%a)@]"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
           (fun fmt e -> Format.fprintf fmt "%a" format_expr e))
        es
  | ETuple (es, Some s) ->
      Format.fprintf fmt "%a {@[<hov 2>%a@]}" Ast.StructName.format_t s
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
           (fun fmt (e, struct_field) ->
             Format.fprintf fmt "\"%a\":@ %a" Ast.StructFieldName.format_t struct_field format_expr
               e))
        (List.combine es (List.map fst (Ast.StructMap.find s ctx.ctx_structs)))
  | EArray es ->
      Format.fprintf fmt "@[<hov 2>[%a]@]"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt ";@ ")
           (fun fmt e -> Format.fprintf fmt "%a" format_expr e))
        es
  | ETupleAccess (e1, n, s, _ts) -> (
      match s with
      | None -> Format.fprintf fmt "%a.%d" format_expr e1 n
      | Some s ->
          Format.fprintf fmt "%a.\"%a\"" format_expr e1 Ast.StructFieldName.format_t
            (fst (List.nth (Ast.StructMap.find s ctx.ctx_structs) n)) )
  | EInj (e, n, en, _ts) ->
      Format.fprintf fmt "@[<hov 2>%a@ %a@]" Ast.EnumConstructor.format_t
        (fst (List.nth (Ast.EnumMap.find en ctx.ctx_enums) n))
        format_expr e
  | EMatch (e, es, e_name) ->
      Format.fprintf fmt "@[<hov 2>match@ %a@ with@ %a@]" format_expr e
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt "@ |@ ")
           (fun fmt (e, c) ->
             Format.fprintf fmt "%a@ %a" Ast.EnumConstructor.format_t c format_expr e))
        (List.combine es (List.map fst (Ast.EnumMap.find e_name ctx.ctx_enums)))
  | ELit l -> Format.fprintf fmt "%a" format_lit (Pos.same_pos_as l e)
  | EApp ((EAbs (_, binder, taus), _), args) ->
      let xs, body = Bindlib.unmbind binder in
      let xs_tau = List.map2 (fun x tau -> (x, tau)) (Array.to_list xs) taus in
      let xs_tau_arg = List.map2 (fun (x, tau) arg -> (x, tau, arg)) xs_tau args in
      Format.fprintf fmt "@[%a%a@]"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt "")
           (fun fmt (x, tau, arg) ->
             Format.fprintf fmt "@[@[<hov 2>let@ %a@ :@ %a@ =@ %a@]@ in@\n@]" format_var x
               (format_typ ctx) tau format_expr arg))
        xs_tau_arg format_expr body
  | EAbs (_, binder, taus) ->
      let xs, body = Bindlib.unmbind binder in
      let xs_tau = List.map2 (fun x tau -> (x, tau)) (Array.to_list xs) taus in
      Format.fprintf fmt "@[<hov 2>λ@ %a →@ %a@]"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt "@ ")
           (fun fmt (x, tau) ->
             Format.fprintf fmt "@[<hov 2>(%a:@ %a)@]" format_var x (format_typ ctx) tau))
        xs_tau format_expr body
  | EApp ((EOp (Binop ((Ast.Map | Ast.Filter) as op)), _), [ arg1; arg2 ]) ->
      Format.fprintf fmt "@[<hov 2>%a@ %a@ %a@]" format_binop (op, Pos.no_pos) format_with_parens
        arg1 format_with_parens arg2
  | EApp ((EOp (Binop op), _), [ arg1; arg2 ]) ->
      Format.fprintf fmt "@[<hov 2>%a@ %a@ %a@]" format_with_parens arg1 format_binop
        (op, Pos.no_pos) format_with_parens arg2
  | EApp ((EOp (Unop op), _), [ arg1 ]) ->
      Format.fprintf fmt "@[<hov 2>%a@ %a@]" format_unop (op, Pos.no_pos) format_with_parens arg1
  | EApp (f, args) ->
      Format.fprintf fmt "@[<hov 2>%a@ %a@]" format_expr f
        (Format.pp_print_list ~pp_sep:(fun fmt () -> Format.fprintf fmt "@ ") format_with_parens)
        args
  | EIfThenElse (e1, e2, e3) ->
      Format.fprintf fmt "@[<hov 2> if@ @[<hov 2>%a@]@ then@ @[<hov 2>%a@]@ else@ @[<hov 2>%a@]@]"
        format_expr e1 format_expr e2 format_expr e3
  | EOp (Ternop op) -> Format.fprintf fmt "%a" format_ternop (op, Pos.no_pos)
  | EOp (Binop op) -> Format.fprintf fmt "%a" format_binop (op, Pos.no_pos)
  | EOp (Unop op) -> Format.fprintf fmt "%a" format_unop (op, Pos.no_pos)
  | EDefault (exceptions, just, cons) ->
      if List.length exceptions = 0 then
        Format.fprintf fmt "@[<hov 2>⟨%a@ ⊢@ %a⟩@]" format_expr just format_expr cons
      else
        Format.fprintf fmt "@[<hov 2>⟨%a@ |@ %a@ ⊢@ %a@ ⟩@]"
          (Format.pp_print_list ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ") format_expr)
          exceptions format_expr just format_expr cons
  | EAssert e' -> Format.fprintf fmt "@[<hov 2>assert@ (%a)@]" format_expr e'