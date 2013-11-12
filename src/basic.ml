
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

(** {1 Terms without type, typically produced from AST} *)

(** {2 Type representation} *)

module Ty = struct
  type t =
    | Var of string
    | App of string * t list
    | Fun of t * t list

  type quantified = {
    vars : t list;
    ty : t;
    loc : Location.t option;
  }

  let eq a b = a = b
  let cmp a b = Pervasives.compare a b
  let hash a = Hashtbl.hash a

  let var s = Var s
  let app s l = App (s, l)
  let const s = app s []

  let mk_fun ret l = match l with
    | [] -> ret
    | _ ->
      (* see {!(<==)} for the invariants *)
      begin match ret with
      | Fun (ret', l') -> Fun (ret', l @ l')
      | _ -> Fun (ret, l)
      end

  let (<==) = mk_fun
  let (<=.) a b = mk_fun a [b]

  let is_var = function | Var _ -> true | _ -> false
  let is_fun = function | Fun _ -> true | _ -> false
  let is_app = function | App _ -> true | _ -> false

  let atom ?loc ty = {
    vars = [];
    ty;
    loc;
  }

  let forall ?loc vars q =
    assert (List.for_all is_var vars);
    (* flatten forall *)
    match vars, q.vars with
    | [], _ -> { q with loc; }
    | _::_, [] -> { ty=q.ty; vars; loc; }
    | _::_, vars' -> { ty=q.ty; vars= vars@vars'; loc; }

  let forall_atom ?loc vars t = forall ?loc vars (atom t)

  let loc q = q.loc

  let i = const "$i"
  let o = const "$o"
  let int = const "$int"
  let rat = const "$rat"
  let real = const "$real"
  let tType = const "$tType"

  let rec pp buf t = match t with
    | Var s -> Buffer.add_string buf s
    | App (s, []) -> Buffer.add_string buf s
    | App (s, l) ->
      Printf.bprintf buf "%s(%a)" s (Util.pp_list pp) l
    | Fun (ret, [x]) ->
      Printf.bprintf buf "%a > %a" pp x pp ret
    | Fun (ret, l) ->
      Printf.bprintf buf "(%a) > %a" (Util.pp_list ~sep:" * " pp) l pp ret

  let pp_tstp = pp
  let to_string = Util.on_buffer pp
  let fmt fmt t = Format.pp_print_string fmt (to_string t)

  let pp_quant buf q = match q.vars with
    | [] -> pp buf q.ty
    | _ -> Printf.bprintf buf "!%a. %a" (Util.pp_list pp) q.vars pp q.ty
  let pp_quant_tstp buf q = match q.vars with
    | [] -> pp_tstp buf q.ty
    | _ ->
      Printf.bprintf buf "!>[%a]: %a" (Util.pp_list pp_tstp) q.vars pp_tstp q.ty
  let to_string_quant = Util.on_buffer pp_quant
  let fmt_quant fmt q = Format.pp_print_string fmt (to_string_quant q)
end

(** {2 First Order terms} *)

module FO = struct
  type t = {
    term : tree;
    ty : Ty.t option;
    loc : Location.t option;
  }
  and tree =
    | App of Symbol.t * t list
    | Var of string

  let eq a b = a = b
  let cmp a b = Pervasives.compare a b
  let hash a = Hashtbl.hash a

  let app ?loc s l = {loc; ty=None; term=App (s, l); }

  let const ?loc s = app ?loc s []

  let var ?loc ?ty s =
    (* ensure a variable always has a type *)
    let ty = match ty with | Some _ -> ty | None -> Some Ty.i in
    { term=Var s; ty; loc; }

  let is_var t = match t.term with | Var _ -> true | _ -> false
  let is_app t = match t.term with | App _ -> true | _ -> false

  let loc t = t.loc
  let cast t ty = { t with ty=Some ty; }
  let get_ty t = match t.ty with
    | Some ty -> ty
    | None -> failwith "Basic.FO.get_ty: no type"
  
  let symbols seq =
    let rec recurse set t = match t.term with
    | App (s, l) ->
      let set = Symbol.Set.add s set in
      List.fold_left recurse set l
    | Var _ -> set
    in
    Sequence.fold recurse Symbol.Set.empty seq

  let free_vars ?(init=[]) t =
    let rec find set t = match t.term with
      | Var _ -> if List.mem t set then set else t :: set
      | App (_, l) -> List.fold_left find set l
    in
    find init t

  let rec generalize_vars t = match t.term, t.ty with
    | Var s, Some (Ty.App("$i",[])) ->
      var ~ty:(Ty.var ("Ty_" ^ s)) s
    | Var _, _ -> t
    | App (s, l), _ ->
      let l' = List.map generalize_vars l in
      {t with term=App (s, l'); }

  let _same_name v1 v2 = match v1.term, v2.term with
    | Var n1, Var n2 -> n1 = n2
    | _ -> false

  (* replace var of given [name] by [v] in [t] *)
  let rec _replace_var v t = match t.term with
    | Var _ ->
      if _same_name v t then v else t
    | App (s, l) ->
      let l' = List.map (_replace_var v) l in
      {t with term=App(s, l'); }

  let rec pp buf t = match t.term with
    | App (s, []) -> Symbol.pp buf s
    | App (s, l) ->
      Printf.bprintf buf "%a(%a)" Symbol.pp s (Util.pp_list pp) l
    | Var s -> Buffer.add_string buf s

  (* print var with its type *)
  let pp_var buf t =
    match t.term, t.ty with
    | Var s, Some (Ty.App ("$i",[])) -> Printf.bprintf buf "%s" s
    | Var s, Some ty -> Printf.bprintf buf "%s:%a" s Ty.pp ty
    | Var s, None -> Printf.bprintf buf "%s" s
    | _, _ -> failwith "pp_var: expected variable"

  let pp_tstp = pp
  let to_string = Util.on_buffer pp
  let fmt fmt t = Format.pp_print_string fmt (to_string t)
end

(** {2 First Order formulas} *)

module Form = struct
  type b_op =
    | Imply
    | Equiv

  type l_op =
    | And
    | Or

  type q_op =
    | Forall
    | Exists

  type t = {
    form : tree;
    loc : Location.t option;
  }
  and tree =
    | Nary of l_op * t list
    | Binary of b_op * t * t
    | Not of t
    | Bool of bool
    | Equal of FO.t * FO.t
    | Atom of FO.t
    | Quant of q_op * FO.t list * t

  type sourced = t * string * string
    (** Sourced formula *)

  let eq a b = a = b
  let cmp a b = Pervasives.compare a b
  let hash a = Hashtbl.hash a

  let mk_and ?loc l = {form=Nary (And, l); loc; }
  let mk_or ?loc l = {form=Nary (Or, l); loc; }
  let mk_not ?loc t = {form=Not t; loc; }
  let mk_eq ?loc t1 t2 = {form=Equal (t1, t2); loc; }
  let mk_neq ?loc t1 t2 = mk_not ?loc (mk_eq ?loc t1 t2)
  let mk_equiv ?loc f1 f2 = {form= Binary (Equiv, f1, f2); loc; }
  let mk_xor ?loc f1 f2 = mk_not ?loc (mk_equiv ?loc f1 f2)
  let mk_imply ?loc f1 f2 = {form=Binary (Imply, f1, f2); loc; }
  let atom ?loc t = {form=Atom t; loc; }
  let mk_true = {form=Bool true; loc=None; }
  let mk_false = {form=Bool false; loc=None; }

  (* replace vars with same name as [v] by [v] in [f] *)
  let rec _replace_var v f = match f.form with
    | Bool _ -> f
    | Not f' -> mk_not ?loc:f.loc (_replace_var v f')
    | Binary (op, f1, f2) ->
      {f with form = Binary (op, _replace_var v f1, _replace_var v f2); }
    | Nary (op, l) ->
      {f with form = Nary (op, List.map (_replace_var v) l); }
    | Quant (op, vars, f') ->
      if List.exists (FO._same_name v) vars
        then f  (* shadowed *)
        else {f with form = Quant (op, vars, _replace_var v f'); }
    | Equal (t1, t2) ->
      {f with form=Equal (FO._replace_var v t1, FO._replace_var v t2); }
    | Atom p ->
      {f with form=Atom (FO._replace_var v p); }

  (* be sure that all variables in [vars] are properly replace in [f] *)
  let _replace_vars vars f =
    assert (List.for_all FO.is_var vars);
    List.fold_left
      (fun f v -> _replace_var v f)
      f vars

  let forall ?loc vars f = {loc; form=Quant (Forall, vars, _replace_vars vars f); }
  let exists ?loc vars f = {loc; form=Quant (Exists, vars, _replace_vars vars f); }

  let free_vars f =
    let rec find set f = match f.form with
    | Bool _ -> set
    | Not f' -> find set f'
    | Binary (_, f1, f2) -> find (find set f1) f2
    | Nary (_, l) -> List.fold_left find set l
    | Atom p -> FO.free_vars ~init:set p
    | Equal (t1, t2) -> FO.free_vars ~init:(FO.free_vars ~init:set t1) t2
    | Quant (_, vars, f') ->
      let set' = find [] f' in
      let set' = List.filter (fun v -> not (List.mem v vars)) set' in
      Util.list_merge compare set set'
    in
    find [] f

  let close_forall f = match free_vars f with
    | [] -> f
    | vars -> forall ?loc:f.loc vars f

  let close_exists f = match free_vars f with
    | [] -> f
    | vars -> exists ?loc:f.loc vars f

  let rec generalize_vars f = match f.form with
    | Nary (op, l) ->
      {f with form=Nary (op, List.map generalize_vars l); }
    | Binary (op, f1, f2) ->
      {f with form=Binary (op, generalize_vars f1, generalize_vars f2); }
    | Not f' ->
      {f with form=Not (generalize_vars f'); }
    | Atom p ->
      {f with form=Atom (FO.generalize_vars p); }
    | Bool _ -> f
    | Equal (t1, t2) ->
      {f with form=Equal (FO.generalize_vars t1, FO.generalize_vars t2); }
    | Quant (op, vars, f') ->
      let vars = List.map FO.generalize_vars vars in
      {f with form=Quant (op, vars, _replace_vars vars f'); }

  let loc f = f.loc

  let rec pp buf f = match f.form with
    | Bool true -> Buffer.add_string buf "$true"
    | Bool false -> Buffer.add_string buf "$false"
    | Nary (And, l) -> Util.pp_list ~sep:" ∧ " pp_inner buf l
    | Nary (Or, l) -> Util.pp_list ~sep:" ∨ " pp_inner buf l
    | Atom t -> FO.pp buf t
    | Binary (Imply, f1, f2) ->
      Printf.bprintf buf "%a → %a" pp_inner f1 pp_inner f2
    | Binary (Equiv, f1, f2) ->
      Printf.bprintf buf "%a <=> %a" pp_inner f1 pp_inner f2
    | Equal (t1, t2) ->
      Printf.bprintf buf "%a = %a" FO.pp t1 FO.pp t2
    | Not {form=Equal (t1, t2)} ->
      Printf.bprintf buf "%a ≠ %a" FO.pp t1 FO.pp t2
    | Not {form=Binary (Equiv, f1, f2)} ->
      Printf.bprintf buf "%a <~> %a" pp_inner f1 pp_inner f2
    | Not f' -> Printf.bprintf buf "¬%a" pp_inner f'
    | Quant (Forall, vars, f') ->
      Printf.bprintf buf "∀%a. %a" (Util.pp_list FO.pp_var) vars pp_inner f'
    | Quant (Exists, vars, f') ->
      Printf.bprintf buf "∃%a. %a" (Util.pp_list FO.pp_var) vars pp_inner f'
  and pp_inner buf f = match f.form with
    | Bool _
    | Equal _
    | Quant _
    | Atom _
    | Not _ -> pp buf f
    | Nary _
    | Binary _ ->
      Buffer.add_char buf '(';
      pp buf f;
      Buffer.add_char buf ')'

  (* TODO: only print types in binders, not in subterms *)

  let rec pp_tstp buf f = match f.form with
    | Bool true -> Buffer.add_string buf "$true"
    | Bool false -> Buffer.add_string buf "$false"
    | Nary (And, l) -> Util.pp_list ~sep:" & " pp_tstp_inner buf l
    | Nary (Or, l) -> Util.pp_list ~sep:" | " pp_tstp_inner buf l
    | Atom t -> FO.pp_tstp buf t
    | Binary (Imply, f1, f2) ->
      Printf.bprintf buf "%a | %a" pp_tstp_inner f1 pp_tstp_inner f2
    | Binary (Equiv, f1, f2) ->
      Printf.bprintf buf "%a <=> %a" pp_tstp_inner f1 pp_tstp_inner f2
    | Equal (t1, t2) ->
      Printf.bprintf buf "%a = %a" FO.pp_tstp t1 FO.pp_tstp t2
    | Not {form=Equal (t1, t2)} ->
      Printf.bprintf buf "%a != %a" FO.pp_tstp t1 FO.pp_tstp t2
    | Not {form=Binary (Equiv, f1, f2)} ->
      Printf.bprintf buf "%a <~> %a" pp_tstp_inner f1 pp_tstp_inner f2
    | Not f' -> Printf.bprintf buf "~ %a" pp_tstp_inner f'
    | Quant (Forall, vars, f') ->
      Printf.bprintf buf "![%a]: %a" (Util.pp_list FO.pp_var) vars pp_tstp_inner f'
    | Quant (Exists, vars, f') ->
      Printf.bprintf buf "?[%a]: %a" (Util.pp_list FO.pp_var) vars pp_tstp_inner f'
  and pp_tstp_inner buf f = match f.form with
    | Bool _
    | Equal _
    | Quant _
    | Atom _
    | Not _ -> pp_tstp buf f
    | Nary _
    | Binary _ ->
      Buffer.add_char buf '(';
      pp_tstp buf f;
      Buffer.add_char buf ')'

  let to_string = Util.on_buffer pp
  let fmt fmt t = Format.pp_print_string fmt (to_string t)
end

(** {2 Higher order Terms} *)

module HO = struct
  type t = {
    term : tree;
    ty : Ty.t option;
    loc : Location.t option;
  }
  and tree =
    | Const of Symbol.t
    | App of t * t list
    | Var of string
    | Lambda of t * t

  let eq a b = a = b
  let cmp a b = Pervasives.compare a b
  let hash a = Hashtbl.hash a

  let const ?loc s = {loc; ty=None; term=Const s; }

  let app ?loc a l = match a.term with
    | App (a', l') ->
      {loc; ty=None; term=App (a', l' @ l); }   (* no nested apps *)
    | _ ->
      begin match l with
      | [] -> {a with loc; }
      | _::_ -> {loc; ty=None; term=App (a, l); }
      end

  let at ?loc a b = app ?loc a [b]

  let var ?loc ?ty s =
    (* ensure a variable always has a type *)
    let ty = match ty with | Some _ -> ty | None -> Some Ty.i in
    {loc; ty; term=Var s; }

  let cast t ty = { t with ty=Some ty; }

  let get_ty t = match t.ty with
    | Some ty -> ty
    | None -> failwith "Basic.HO.get_ty: no type"

  let _same_name v1 v2 = match v1.term, v2.term with
    | Var n1, Var n2 -> n1 = n2
    | _ -> false

  (* replace vars with same name as [v] by [v] in [t] *)
  let rec _replace_var v t = match t.term with
    | Const _ -> t
    | Var _ ->
      if _same_name v t then v else t
    | App (head, l) ->
      let head' = _replace_var v head in
      let l' = List.map (_replace_var v) l in
      {t with term=App(head',l'); }
    | Lambda ({term=Var _} as var, t') ->
      if _same_name v var
        then t  (* name is shadowed under quantifier *)
        else {t with term=Lambda (var, _replace_var v t'); }
    | Lambda _ -> assert false

  let lambda ?loc ~var t = match var.term with
    | Var _ ->
      (* be sure that all variables occurring in [t] with the same name
          have the same type *)
      {loc; ty=None; term=Lambda (var, _replace_var var t); }
    | _ -> failwith "Untyped.HO.lambda: expect (var, term)"

  let true_term = const Symbol.true_symbol
  let false_term = const Symbol.false_symbol

  let forall ?loc ~var t =
    at ?loc (const ?loc Symbol.forall_symbol) (lambda ?loc ~var t)

  let exists ?loc ~var t =
    at ?loc (const ?loc Symbol.exists_symbol) (lambda ?loc ~var t)

  let rec forall_list ?loc vars t = match vars with
    | [] -> t
    | var::vars' -> forall ?loc ~var (forall_list vars' t)

  let rec exists_list ?loc vars t = match vars with
    | [] -> t
    | var::vars' -> exists ?loc ~var (exists_list vars' t)

  let rec of_term t =
    let loc = t.FO.loc in
    match t.FO.term with
    | FO.Var n -> var ?loc ~ty:(FO.get_ty t) n
    | FO.App (s, l) -> app ?loc (const s) (List.map of_term l)

  let rec of_form f = match f.Form.form with
    | Form.Bool true -> true_term
    | Form.Bool false -> false_term
    | Form.Nary (Form.And, l) ->
      app (const Symbol.and_symbol) (List.map of_form l)
    | Form.Nary (Form.Or, l) ->
      app (const Symbol.or_symbol) (List.map of_form l)
    | Form.Binary (Form.Equiv, f1, f2) ->
      app (const Symbol.equiv_symbol) [of_form f1; of_form f2]
    | Form.Binary (Form.Imply, f1, f2) ->
      app (const Symbol.imply_symbol) [of_form f1; of_form f2]
    | Form.Equal (t1, t2) ->
      app (const Symbol.eq_symbol) [of_term t1; of_term t2]
    | Form.Not f' -> at (const Symbol.not_symbol) (of_form f')
    | Form.Atom p -> of_term p
    | Form.Quant (Form.Forall, l, f') ->
      forall_list (List.map of_term l) (of_form f')
    | Form.Quant (Form.Exists, l, f') ->
      exists_list (List.map of_term l) (of_form f')

  (* special: print variables in quantifiers, with their types if needed *)
  let pp_var buf t = match t.term, t.ty with
    | Var s, None -> Buffer.add_string buf s
    | Var s, Some ty' when Ty.eq ty' Ty.i -> Buffer.add_string buf s
    | Var s, Some ty' -> Printf.bprintf buf "%s:%a" s Ty.pp ty'
    | _ -> failwith "pp_var"

  let rec pp buf t = match t.term with
    | Const s -> Symbol.pp buf s
    | Var s -> Buffer.add_string buf s
    | App (_, []) -> assert false
    | App (t, l) -> Util.pp_list ~sep:" @ " pp_inner buf (t :: l)
    | Lambda (v, t') ->
      Printf.bprintf buf "λ%a. %a" pp_var v pp_inner t'

  and pp_inner buf t = match t.term with
    | App _
    | Lambda _ -> 
      Buffer.add_char buf '(';
      pp buf t;
      Buffer.add_char buf ')'
    | Var _ | Const _ -> pp buf t

  let rec pp_tstp buf t = match t.term with
    | Const s when Symbol.eq s Symbol.forall_symbol -> Buffer.add_string buf "!!"
    | Const s when Symbol.eq s Symbol.exists_symbol -> Buffer.add_string buf "??"
    | Const s -> Symbol.pp buf s
    | Var s -> Buffer.add_string buf s
    | App (_, []) -> assert false
    | App (t, l) -> Util.pp_list ~sep:" @ " pp_inner buf (t :: l)
    | Lambda (v, t') ->
      Printf.bprintf buf "^[%a]: %a" pp_var v pp_inner t'

  and pp_inner buf t = match t.term with
    | App _
    | Lambda _ -> 
      Buffer.add_char buf '(';
      pp_tstp buf t;
      Buffer.add_char buf ')'
    | Var _ | Const _ -> pp buf t

  let to_string = Util.on_buffer pp
  let fmt fmt t = Format.pp_print_string fmt (to_string t)
end
