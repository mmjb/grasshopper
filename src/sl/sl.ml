
type ident = Form.ident
let mk_ident = Form.mk_ident
module IdMap = Form.IdMap
module IdSet = Form.IdSet
let ident_to_string = Form.str_of_ident

(* the next pointer *)
let pts = mk_ident "sl_pts"

let skolemCst = "SkolemCst"

type form =
  | Emp
  | Eq of ident * ident
  | PtsTo of ident * ident
  | List of ident * ident
  | SepConj of form list
  | BoolConst of bool
  | Not of form
  | And of form list
  | Or of form list

module SlSet = Set.Make(struct
    type t = form
    let compare = compare
  end)

module SlMap = Map.Make(struct
    type t = form
    let compare = compare
  end)


let mk_true = BoolConst true
let mk_false = BoolConst false
let mk_eq a b = Eq (a, b)
let mk_not a = Not a
let mk_pts a b = PtsTo (a, b)
let mk_ls a b = List (a, b)
let mk_and a b = And [a; b]
let mk_or a b = Or [a; b]
let mk_sep a b = SepConj [a; b]

let rec to_string f = match f with
  | Not (Eq (e1, e2)) -> (ident_to_string e1) ^ " ~= " ^ (ident_to_string e2)
  | Eq (e1, e2) -> (ident_to_string e1) ^ " = " ^ (ident_to_string e2)
  | Not t -> "~(" ^ (to_string t) ^")"
  | And lst -> "(" ^ (String.concat ") && (" (List.map to_string lst)) ^ ")"
  | Or lst ->  "(" ^ (String.concat ") || (" (List.map to_string lst)) ^ ")"
  | BoolConst b -> string_of_bool b
  | Emp -> "emp"
  | PtsTo (a, b) -> (Form.str_of_ident a) ^ " |-> " ^ (Form.str_of_ident b)
  | List (a, b) -> "lseg(" ^ (Form.str_of_ident a) ^ ", " ^ (Form.str_of_ident b) ^ ")"
  | SepConj lst -> "(" ^ (String.concat ") * (" (List.map to_string lst)) ^ ")"

let rec ids f = match f with
  | Eq (a, b) | PtsTo (a, b) | List (a, b) -> 
    IdSet.add a (IdSet.singleton b)
  | Not t -> ids t
  | And lst | Or lst | SepConj lst -> 
    List.fold_left
      (fun acc f2 -> IdSet.union acc (ids f2))
      IdSet.empty
      lst
  | BoolConst _ | Emp -> IdSet.empty

let rec normalize f = match f with
  | Eq (e1, e2) -> if e1 = e2 then BoolConst true else Eq (e1, e2)
  | Not t -> 
    begin
      match normalize t with
      | BoolConst b -> BoolConst (not b)
      | t2 -> Not t2
    end
  | And lst -> 
    let sub_forms =
      List.fold_left
        (fun acc t -> SlSet.add (normalize t) acc)
        SlSet.empty
        lst
    in
    let sub_forms = SlSet.remove (BoolConst true) sub_forms in
      if (SlSet.mem (BoolConst false) sub_forms) then BoolConst false
      else if (SlSet.cardinal sub_forms = 0) then BoolConst true
      else if (SlSet.cardinal sub_forms = 1) then SlSet.choose sub_forms
      else And (SlSet.elements sub_forms)
  | Or lst ->  
    let sub_forms =
      List.fold_left
        (fun acc t -> SlSet.add (normalize t) acc)
        SlSet.empty
        lst
    in
    let sub_forms = SlSet.remove (BoolConst false) sub_forms in
      if (SlSet.mem (BoolConst true) sub_forms) then BoolConst true
      else if (SlSet.cardinal sub_forms = 0) then BoolConst false
      else if (SlSet.cardinal sub_forms = 1) then SlSet.choose sub_forms
      else Or (SlSet.elements sub_forms)
  | SepConj lst -> 
    let lst2 = List.map normalize lst in
    let lst3 = List.filter (fun x -> x <> Emp) lst2 in
      SepConj lst3
  | BoolConst b -> BoolConst b
  | Emp -> Emp
  | PtsTo (a, b) -> PtsTo (a, b)
  | List (a, b) -> if a = b then Emp else List (a, b)

let rec map_id fct f = match f with
  | Eq (e1, e2) -> Eq (fct e1, fct e2)
  | Not t ->  Not (map_id fct t)
  | And lst -> And (List.map (map_id fct) lst)
  | Or lst -> Or (List.map (map_id fct) lst)
  | BoolConst b -> BoolConst b
  | Emp -> Emp
  | PtsTo (a, b) -> PtsTo (fct a, fct b)
  | List (a, b) -> List (fct a, fct b)
  | SepConj lst -> SepConj (List.map (map_id fct) lst)

let subst_id subst f =
  let get id =
    try IdMap.find id subst with Not_found -> id
  in
    map_id get f

(* TODO translation to lolli:
 * tricky part is the scope of the quantifier -> looli does not have this explicitely,
 * (1) maybe we can have an intermediate step with a new AST
 * (2) interprete the comments as scope for the quantified variable (ugly hack)
 *)

let exists = "exists"
let forall = "forall"

let mk_exists f = Form.Comment (exists, f)
let mk_forall f = Form.Comment (forall, f)

let cst = Form.mk_const
let reachWoT a b c = Axioms.reach pts a b c
let reachWo a b c = reachWoT (cst a) (cst b) (cst c)
let reach a b = reachWo a b b
let mk_domain d v = Form.mk_pred d [v]

let one_and_rest lst =
  let rec process acc1 acc2 lst = match lst with
    | x :: xs -> process ((x, acc2 @ xs) :: acc1) (x :: acc2) xs
    | [] -> acc1
  in
    process [] [] lst

(*
let to_form domain f =
  let v = Axioms.var1 in
  let rec process domain f = match f with
    | BoolConst b -> Form.BoolConst b
    | Eq (id1, id2) -> Form.mk_eq (cst id1) (cst id2)
    | Emp -> mk_forall (Form.mk_not (mk_domain domain v))
    | PtsTo (id1, id2) ->
      Form.mk_and [
        Form.mk_eq (Form.mk_app pts [cst id1]) (cst id2) ;
        mk_forall (Form.mk_equiv (Form.mk_eq (cst id1) v) (mk_domain domain v))
      ]
    | List (id1, id2) ->
      Form.mk_and [
        reach id1 id2;
        mk_forall (
          Form.mk_equiv (
            Form.mk_and [
              reachWoT (cst id1) v (cst id2);
              Form.mk_neq v (cst id2)
            ]; )
          (mk_domain domain v) )
      ]
    | SepConj forms ->
      let ds = List.map (fun _ -> Form.fresh_ident ("sub_" ^(fst domain))) forms in
      let dsP = List.map (fun d -> mk_domain d v) ds in
      let translated = List.map2 process ds forms in
      let d = mk_domain domain v in
      let sepration =
        mk_forall (Form.mk_and (
            (Form.mk_implies d (Form.mk_or dsP))
            :: (List.map (fun (x, xs) -> Form.mk_implies x (Form.mk_and (d :: (List.map Form.mk_not xs)))) (one_and_rest dsP))
          )
        )
      in
        Form.mk_and (sepration :: translated)
    | Not form -> Form.mk_not (process domain form)
    | And forms -> Form.smk_and (List.map (process domain) forms)
    | Or forms -> Form.smk_or (List.map (process domain) forms)
  in
    process domain f
*)

(* translation that keep the heap separation separated from the pointer structure *)
let to_form domain f =
  let v = Axioms.var1 in
  let empty domain = mk_forall (Form.mk_not (mk_domain domain v)) in
  let rec process domain f = match f with
    | BoolConst b -> (Form.BoolConst b, empty domain)
    | Eq (id1, id2) -> 
      (Form.mk_eq (cst id1) (cst id2), empty domain)
    | Emp -> (Form.BoolConst true, empty domain)
    | PtsTo (id1, id2) ->
      ( Form.mk_eq (Form.mk_app pts [cst id1]) (cst id2),
        mk_forall (Form.mk_equiv (Form.mk_eq (cst id1) v) (mk_domain domain v))
      )
    | List (id1, id2) ->
      ( reach id1 id2,
        mk_forall (
          Form.mk_equiv (
            Form.mk_and [
              reachWoT (cst id1) v (cst id2);
              Form.mk_neq v (cst id2)
            ]; )
          (mk_domain domain v) )
      )
    | Not form ->
      let (structure, heap) = process domain form in
        (Form.mk_not structure, heap)
    | SepConj forms ->
      let ds = List.map (fun _ -> Form.fresh_ident ("sub_" ^(fst domain))) forms in
      let translated = List.map2 process ds forms in
      let (translated_1, translated_2) = List.split translated in
      let dsP = List.map (fun d -> mk_domain d v) ds in
      let d = mk_domain domain v in
      let sepration =
        mk_forall (Form.mk_and (
            (Form.mk_implies d (Form.mk_or dsP))
            :: (List.map (fun (x, xs) -> Form.mk_implies x (Form.mk_and (d :: (List.map Form.mk_not xs)))) (one_and_rest dsP))
          )
        )
      in
      let heap_part = Form.mk_and (sepration :: translated_2) in
      let struct_part = Form.smk_and translated_1 in
        (struct_part, heap_part)
    | And forms ->
      let ds = List.map (fun _ -> Form.fresh_ident ("sub_" ^(fst domain))) forms in
      let translated = List.map2 process ds forms in
      let (translated_1, translated_2) = List.split translated in
      let dsP = List.map (fun d -> mk_domain d v) ds in
      let d = mk_domain domain v in
      let pick_all = List.map (fun d2 -> mk_forall (Form.mk_equiv d d2)) dsP in
        (Form.smk_and (pick_all @ translated_1), Form.smk_and translated_2)
    | Or forms ->
      let ds = List.map (fun _ -> Form.fresh_ident ("sub_" ^(fst domain))) forms in
      let translated = List.map2 process ds forms in
      let (translated_1, translated_2) = List.split translated in
      let dsP = List.map (fun d -> mk_domain d v) ds in
      let d = mk_domain domain v in
      let pick_one = Form.smk_or (List.map2 (fun d2 f -> Form.smk_and [mk_forall (Form.mk_equiv d d2); f]) dsP translated_1) in
        (pick_one, Form.smk_and translated_2)
  in
    process domain f

let nnf f =
  let rec process negate f = match f with
    | Form.BoolConst b -> Form.BoolConst (negate <> b)
    | Form.Pred _ as p -> if negate then Form.mk_not p else p
    | Form.Eq _ as eq -> if negate then Form.mk_not eq else eq
    | Form.Not form -> process (not negate) form
    | Form.And forms ->
      let forms2 = List.map (process negate) forms in
        if negate then Form.mk_or forms2
        else Form.mk_and forms2
    | Form.Or forms -> 
      let forms2 = List.map (process negate) forms in
        if negate then Form.mk_and forms2
        else Form.mk_or forms2
    | Form.Comment (c, form) ->
      let form2 = process negate form in
      let c2 =
        if negate && c = exists then forall
        else if negate && c = forall then exists
        else c
      in
        Form.mk_comment c2 form2
  in
    process false f

let negate_ignore_quantifiers f =
  let rec process negate f = match f with
    | Form.BoolConst b -> Form.BoolConst (negate <> b)
    | Form.Pred _ as p -> if negate then Form.mk_not p else p
    | Form.Eq _ as eq -> if negate then Form.mk_not eq else eq
    | Form.Not form -> process (not negate) form
    | Form.And forms ->
      let forms2 = List.map (process negate) forms in
        if negate then Form.mk_or forms2
        else Form.mk_and forms2
    | Form.Or forms -> 
      let forms2 = List.map (process negate) forms in
        if negate then Form.mk_and forms2
        else Form.mk_or forms2
    | Form.Comment (c, form) ->
      let form2 = process negate form in
        Form.mk_comment c form2
  in
    process true f

(* TODO skolem and equisat, negation for entailement ?
 * translation should either or not, nnf/restricted form should make it so.
 * ...
 *)

(* assumes no quantifier alternation *)
(*
let skolemize f =
  let fresh () = cst (Form.fresh_ident skolemCst) in
  let rec process subst f = match f with
    | Form.BoolConst _ as b -> b
    | Form.Eq _ | Form.Pred _ -> Form.subst subst f
    | Form.Not form -> Form.mk_not (process subst form)
    | Form.And forms -> Form.smk_and (List.map (process subst) forms) 
    | Form.Or forms -> Form.smk_or (List.map (process subst) forms)
    | Form.Comment (c, form) ->
        if c = exists then
          let subst2 =
            IdSet.fold
              (fun v acc -> IdMap.add v (fresh ()) acc) 
              (Form.fv form)
              subst
          in
            process subst2 form
        else if c = forall then 
          let vs = Form.fv form in
          let subst2 = IdSet.fold IdMap.remove vs subst in
            Form.mk_comment c (process subst2 form)
        else 
          Form.mk_comment c (process subst form)
  in
    process IdMap.empty f
*)

(* pull the axioms at the top level.
 * assumes: nnf, skolemized
 *)
let positive_with_top_Lvl_axioms f =
(*let equisat_with_topLvl_axioms f =
  let fresh () = Form.mk_pred (Form.fresh_ident "equisat") [] in*)
  let fresh () = Form.mk_pred (Form.fresh_ident "positive") [] in
  let rec process f = match f with
    | Form.BoolConst _ | Form.Eq _ | Form.Pred _ -> (f, [])
    | Form.Not f2 -> 
      let (f3, acc) = process f2 in
        (Form.mk_not f3, acc)
    | Form.And forms -> 
      let forms2, accs = List.split (List.map process forms) in
        (Form.mk_and forms2, List.flatten accs)
    | Form.Or forms ->
      let forms2, accs = List.split (List.map process forms) in
        (Form.mk_or forms2, List.flatten accs)
    | Form.Comment (c, form) ->
        if c = exists then
          failwith "f has not been skolemized"
        else if c = forall then 
          let p = fresh () in
          let part1 = Form.mk_or [Form.mk_not p; form] in
          (*let part2 = Form.mk_or [skolemize (nnf (Form.mk_not f)); p] in*)
            (p, [part1](*; part2]*))
        else 
          let (f2, acc) = process form in
            (Form.mk_comment c f2, acc)
  in
  let top_level f = match f with
    | Form.BoolConst _ | Form.Eq _ | Form.Pred _ -> (f, [])
    | Form.Comment (c, form) when c = exists -> (f, [])
    | Form.Comment (c, form) when c = forall -> (f, [])
    | other -> process other
  in
  let clauses = match f with
    | Form.And lst -> lst
    | other -> [other]
  in
  let (f2s, accs) = List.split (List.map top_level clauses) in
    Form.smk_and (f2s  @ (List.flatten accs))

let to_lolli domain f =
  let (pointers, separations) = to_form domain f in
    positive_with_top_Lvl_axioms (Form.smk_and [pointers; separations])

let to_lolli_with_axioms domain f =
  let f2 = to_lolli domain f in
  let ax = List.flatten (Axioms.make_axioms [[f2]]) in
    Form.smk_and (f2 :: ax)

let to_lolli_negated domain f =
  (*TODO make a new domain ... *)
  let domain2 = Form.fresh_ident ("neg_" ^(fst domain)) in
  let sk_var = Form.mk_const (Form.fresh_ident "skolemCst") in
  let different_domain = mk_forall (Form.mk_not (Form.mk_equiv (mk_domain domain sk_var) (mk_domain domain2 sk_var))) in
  let (pointers, separations) = to_form domain2 f in
  let pointers = negate_ignore_quantifiers pointers in
    positive_with_top_Lvl_axioms (Form.smk_and [Form.smk_or [different_domain; pointers]; separations])

let to_lolli_negated_with_axioms domain f =
  let f2 = to_lolli_negated domain f in
  let ax = List.flatten (Axioms.make_axioms [[f2]]) in
    Form.smk_and (f2 :: ax)