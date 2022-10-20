(* This file is part of the Catala compiler, a specification language for tax
   and social benefits computation rules. Copyright (C) 2020-2022 Inria,
   contributor: Denis Merigoux <denis.merigoux@inria.fr>, Alain Delaët-Tixeuil
   <alain.delaet--tixeuil@inria.fr>, Louis Gesbert <louis.gesbert@inria.fr>

   Licensed under the Apache License, Version 2.0 (the "License"); you may not
   use this file except in compliance with the License. You may obtain a copy of
   the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
   WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
   License for the specific language governing permissions and limitations under
   the License. *)

(** Functions handling the expressions of [shared_ast] *)

open Utils
open Definitions

(** {2 Boxed constructors} *)

val box : ('a, 't) gexpr -> ('a, 't) boxed_gexpr
(** Box the expression from the outside *)

val unbox : ('a, 't) boxed_gexpr -> ('a, 't) gexpr
(** For closed expressions, similar to [Bindlib.unbox] *)

val rebox : ('a, 't) gexpr -> ('a, 't) boxed_gexpr
(** Rebuild the whole term, re-binding all variables and exposing free variables *)

val evar : ('a, 't) gexpr Var.t -> 't -> ('a, 't) boxed_gexpr

val bind :
  ('a, 't) gexpr Var.t array ->
  ('a, 't) boxed_gexpr ->
  (('a, 't) naked_gexpr, ('a, 't) gexpr) Bindlib.mbinder Bindlib.box

val subst :
  (('a, 't) naked_gexpr, ('a, 't) gexpr) Bindlib.mbinder ->
  ('a, 't) gexpr list ->
  ('a, 't) gexpr

val etuple :
  (([< dcalc | lcalc ] as 'a), 't) boxed_gexpr list ->
  StructName.t option ->
  't ->
  ('a, 't) boxed_gexpr

val etupleaccess :
  (([< dcalc | lcalc ] as 'a), 't) boxed_gexpr ->
  int ->
  StructName.t option ->
  typ list ->
  't ->
  ('a, 't) boxed_gexpr

val einj :
  (([< dcalc | lcalc ] as 'a), 't) boxed_gexpr ->
  int ->
  EnumName.t ->
  typ list ->
  't ->
  ('a, 't) boxed_gexpr

val ematch :
  (([< dcalc | lcalc ] as 'a), 't) boxed_gexpr ->
  ('a, 't) boxed_gexpr list ->
  EnumName.t ->
  't ->
  ('a, 't) boxed_gexpr

val earray : ('a any, 't) boxed_gexpr list -> 't -> ('a, 't) boxed_gexpr
val elit : 'a any glit -> 't -> ('a, 't) boxed_gexpr

val eabs :
  (('a any, 't) naked_gexpr, ('a, 't) gexpr) Bindlib.mbinder Bindlib.box ->
  typ list ->
  't ->
  ('a, 't) boxed_gexpr

val eapp :
  ('a any, 't) boxed_gexpr ->
  ('a, 't) boxed_gexpr list ->
  't ->
  ('a, 't) boxed_gexpr

val eassert :
  (([< dcalc | lcalc ] as 'a), 't) boxed_gexpr -> 't -> ('a, 't) boxed_gexpr

val eop : operator -> 't -> (_ any, 't) boxed_gexpr

val edefault :
  (([< desugared | scopelang | dcalc ] as 'a), 't) boxed_gexpr list ->
  ('a, 't) boxed_gexpr ->
  ('a, 't) boxed_gexpr ->
  't ->
  ('a, 't) boxed_gexpr

val eifthenelse :
  ('a any, 't) boxed_gexpr ->
  ('a, 't) boxed_gexpr ->
  ('a, 't) boxed_gexpr ->
  't ->
  ('a, 't) boxed_gexpr

val eerroronempty :
  (([< desugared | scopelang | dcalc ] as 'a), 't) boxed_gexpr ->
  't ->
  ('a, 't) boxed_gexpr

val ecatch :
  (lcalc, 't) boxed_gexpr ->
  except ->
  (lcalc, 't) boxed_gexpr ->
  't ->
  (lcalc, 't) boxed_gexpr

val eraise : except -> 't -> (lcalc, 't) boxed_gexpr

val elocation :
  ([< desugared | scopelang ] as 'a) glocation -> 't -> ('a, 't) boxed_gexpr

val estruct :
  StructName.t ->
  (([< desugared | scopelang ] as 'a), 't) boxed_gexpr StructFieldMap.t ->
  't ->
  ('a, 't) boxed_gexpr

val estructaccess :
  (([< desugared | scopelang ] as 'a), 't) boxed_gexpr ->
  StructFieldName.t ->
  StructName.t ->
  't ->
  ('a, 't) boxed_gexpr

val eenuminj :
  (([< desugared | scopelang ] as 'a), 't) boxed_gexpr ->
  EnumConstructor.t ->
  EnumName.t ->
  't ->
  ('a, 't) boxed_gexpr

val ematchs :
  (([< desugared | scopelang ] as 'a), 't) boxed_gexpr ->
  EnumName.t ->
  ('a, 't) boxed_gexpr EnumConstructorMap.t ->
  't ->
  ('a, 't) boxed_gexpr

(** Manipulation of marks *)

val no_mark : 'm mark -> 'm mark
val mark_pos : 'm mark -> Pos.t
val with_pos : Pos.t -> 'm mark -> 'm mark

val with_ty : 'm mark -> ?pos:Pos.t -> typ -> 'm mark
(** Adds the given type information only on typed marks *)

val map_ty : (typ -> typ) -> 'm mark -> 'm mark
(** Identity on untyped marks*)

val map_mark : (Pos.t -> Pos.t) -> (typ -> typ) -> 'm mark -> 'm mark

val map_mark2 :
  (Pos.t -> Pos.t -> Pos.t) ->
  (typed -> typed -> typ) ->
  'm mark ->
  'm mark ->
  'm mark

val fold_marks :
  (Pos.t list -> Pos.t) -> (typed list -> typ) -> 'm mark list -> 'm mark

val maybe_ty : ?typ:naked_typ -> 'm mark -> typ
(** Returns the corresponding type on a typed expr, or [typ] (defaulting to
    [TAny]) at the current position on an untyped one *)

(** Manipulation of marked expressions *)

val pos : ('a, 'm mark) Marked.t -> Pos.t
val ty : ('e, typed mark) Marked.t -> typ
val set_ty : typ -> ('a, 'm mark) Marked.t -> ('a, typed mark) Marked.t
val untype : ('a, 'm mark) gexpr -> ('a, untyped mark) boxed_gexpr

(** {2 Traversal functions} *)

val map :
  'ctx ->
  f:('ctx -> ('a, 't1) gexpr -> ('a, 't2) boxed_gexpr) ->
  (('a, 't1) naked_gexpr, 't2) Marked.t ->
  ('a, 't2) boxed_gexpr
(** Flat (non-recursive) mapping on expressions.

    If you want to apply a map transform to an expression, you can save up
    writing a painful match over all the cases of the AST. For instance, if you
    want to remove all errors on empty, you can write

    {[
      let remove_error_empty =
        let rec f () e =
          match Marked.unmark e with
          | ErrorOnEmpty e1 -> Expr.map () f e1
          | _ -> Expr.map () f e
        in
        f () e
    ]}

    The first argument of map_expr is an optional context that you can carry
    around during your map traversal. *)

val map_top_down :
  f:(('a, 't1) gexpr -> (('a, 't1) naked_gexpr, 't2) Marked.t) ->
  ('a, 't1) gexpr ->
  ('a, 't2) boxed_gexpr
(** Recursively applies [f] to the nodes of the expression tree. The type
    returned by [f] is hybrid since the mark at top-level has been rewritten,
    but not yet the marks in the subtrees. *)

val map_marks : f:('t1 -> 't2) -> ('a, 't1) gexpr -> ('a, 't2) boxed_gexpr

(** {2 Expression building helpers} *)

val make_var : ('a, 't) gexpr Var.t -> 't -> ('a, 't) boxed_gexpr

val make_abs :
  ('a, 'm mark) gexpr Var.vars ->
  ('a, 'm mark) boxed_gexpr ->
  typ list ->
  Pos.t ->
  ('a, 'm mark) boxed_gexpr

val make_app :
  ('a any, 'm mark) boxed_gexpr ->
  ('a, 'm mark) boxed_gexpr list ->
  Pos.t ->
  ('a, 'm mark) boxed_gexpr

val empty_thunked_term :
  'm mark -> ([< dcalc | desugared | scopelang ], 'm mark) boxed_gexpr

val make_let_in :
  ('a, 'm mark) gexpr Var.t ->
  typ ->
  ('a, 'm mark) boxed_gexpr ->
  ('a, 'm mark) boxed_gexpr ->
  Pos.t ->
  ('a, 'm mark) boxed_gexpr

val make_multiple_let_in :
  ('a, 'm mark) gexpr Var.vars ->
  typ list ->
  ('a, 'm mark) boxed_gexpr list ->
  ('a, 'm mark) boxed_gexpr ->
  Pos.t ->
  ('a, 'm mark) boxed_gexpr

val make_default :
  (([< desugared | scopelang | dcalc ] as 'a), 't) boxed_gexpr list ->
  ('a, 't) boxed_gexpr ->
  ('a, 't) boxed_gexpr ->
  't ->
  ('a, 't) boxed_gexpr
(** [make_default ?pos exceptions just cons] builds a term semantically
    equivalent to [<exceptions | just :- cons>] (the [EDefault] constructor)
    while avoiding redundant nested constructions. The position is extracted
    from [just] by default.

    Note that, due to the simplifications taking place, the result might not be
    of the form [EDefault]:

    - [<true :- x>] is rewritten as [x]
    - [<ex | true :- def>], when [def] is a default term [<j :- c>] without
      exceptions, is collapsed into [<ex | def>]
    - [<ex | false :- _>], when [ex] is a single exception, is rewritten as [ex] *)

val make_tuple :
  (([< dcalc | lcalc ] as 'a), 'm mark) boxed_gexpr list ->
  StructName.t option ->
  'm mark ->
  ('a, 'm mark) boxed_gexpr
(** Builds a tuple; the mark argument is only used as witness and for position
    when building 0-uples *)

(** {2 Transformations} *)

val remove_logging_calls : ('a any, 't) gexpr -> ('a, 't) boxed_gexpr
(** Removes all calls to [Log] unary operators in the AST, replacing them by
    their argument. *)

val format :
  ?debug:bool (** [true] for debug printing *) ->
  decl_ctx ->
  Format.formatter ->
  (_, _ mark) gexpr ->
  unit

(** {2 Analysis and tests} *)

val equal_lit : 'a glit -> 'a glit -> bool
val compare_lit : 'a glit -> 'a glit -> int
val equal_location : 'a glocation Marked.pos -> 'a glocation Marked.pos -> bool
val compare_location : 'a glocation Marked.pos -> 'a glocation Marked.pos -> int

val equal : ('a, 't) gexpr -> ('a, 't) gexpr -> bool
(** Determines if two expressions are equal, omitting their position information *)

val compare : ('a, 't) gexpr -> ('a, 't) gexpr -> int
(** Standard comparison function, suitable for e.g. [Set.Make]. Ignores position
    information *)

val equal_typ : typ -> typ -> bool
val compare_typ : typ -> typ -> int
val is_value : ('a any, 't) gexpr -> bool
val free_vars : ('a any, 't) gexpr -> ('a, 't) gexpr Var.Set.t

val size : ('a, 't) gexpr -> int
(** Used by the optimizer to know when to stop *)

(** {2 Low-level handling of boxed expressions} *)
module Box : sig
  (** This module contains helper functions for Bindlib, and wrappers to use
      boxed expressions.

      We use the [boxed_expr = naked_expr box marked] type throughout, rather
      than the more straightforward [expr box = naked_expr marked box], because
      the latter would force us to resolve the box every time we need to recover
      the annotation, which happens often. It's more efficient and convenient to
      add the annotation outside of the box, and delay its injection (using
      [box_inj]) to when the parent term gets built. *)

  val inj : ('a, 't) boxed_gexpr -> ('a, 't) gexpr Bindlib.box
  (** Inject the annotation within the box, to use e.g. when a [gexpr box] is
      required for building parent terms *)

  val app0 : ('a, 't) naked_gexpr -> 't -> ('a, 't) boxed_gexpr
  (** The [app*] functions allow building boxed expressions using
      [Bindlib.apply_box] and its variants, while correctly handling the
      expression annotations. Note that the function provided as argument should
      return a [naked_gexpr] and the expression annotation (['t]) is provided as
      a separate argument. *)

  val app1 :
    ('a, 't) boxed_gexpr ->
    (('a, 't) gexpr -> ('a, 't) naked_gexpr) ->
    't ->
    ('a, 't) boxed_gexpr

  val app2 :
    ('a, 't) boxed_gexpr ->
    ('a, 't) boxed_gexpr ->
    (('a, 't) gexpr -> ('a, 't) gexpr -> ('a, 't) naked_gexpr) ->
    't ->
    ('a, 't) boxed_gexpr

  val app3 :
    ('a, 't) boxed_gexpr ->
    ('a, 't) boxed_gexpr ->
    ('a, 't) boxed_gexpr ->
    (('a, 't) gexpr -> ('a, 't) gexpr -> ('a, 't) gexpr -> ('a, 't) naked_gexpr) ->
    't ->
    ('a, 't) boxed_gexpr

  val appn :
    ('a, 't) boxed_gexpr list ->
    (('a, 't) gexpr list -> ('a, 't) naked_gexpr) ->
    't ->
    ('a, 't) boxed_gexpr

  val app1n :
    ('a, 't) boxed_gexpr ->
    ('a, 't) boxed_gexpr list ->
    (('a, 't) gexpr -> ('a, 't) gexpr list -> ('a, 't) naked_gexpr) ->
    't ->
    ('a, 't) boxed_gexpr

  val app2n :
    ('a, 't) boxed_gexpr ->
    ('a, 't) boxed_gexpr ->
    ('a, 't) boxed_gexpr list ->
    (('a, 't) gexpr ->
    ('a, 't) gexpr ->
    ('a, 't) gexpr list ->
    ('a, 't) naked_gexpr) ->
    't ->
    ('a, 't) boxed_gexpr
end