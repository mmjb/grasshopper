open Form
open ParseSmtLibAux

(* Todo: add proper error handling *)
    
type session = { init: bool;
		 in_chan: in_channel;
		 out_chan: out_channel;
		 replay_chan: out_channel option;
		 mutable assert_count: int;
		 stack_height: int
	       } 

exception SmtLib_error of session * string
    
let fail session msg = raise (SmtLib_error (session, "SmtLib: " ^ msg))
      
let write session cmd =
  output_string session.out_chan cmd;
  match session.replay_chan with
  | Some chan -> output_string chan cmd
  | None -> ()	

let writefn session fn =
  fn session.out_chan;
  match session.replay_chan with
  | Some chan -> fn chan
  | None -> ()

let writeln session cmd = 
  write session (cmd ^ "\n")  
   
let read session = 
  flush session.out_chan;
  let lexbuf = Lexing.from_channel session.in_chan in
  ParseSmtLib.main LexSmtLib.token lexbuf

let start smt_cmd replay_file produce_models produce_interpolants = 
  let in_chan, out_chan = Unix.open_process smt_cmd in
  let replay_chan = 
    match replay_file with
    | Some filename -> Some (open_out filename)
    | None -> None
  in
  let session = { init = true; 
		  in_chan = in_chan; 
		  out_chan = out_chan;
		  replay_chan = replay_chan;
		  assert_count = 0;
		  stack_height = 0 }
  in
  writeln session "(set-option :print-success false)";
  if produce_models then begin
    writeln session "(set-option :produce-models true)"
  end;
  if produce_interpolants then writeln session "(set-option :produce-interpolants true)";
  writeln session "(set-logic QF_UF)";
  writeln session ("(declare-sort " ^ sort_str ^ " 0)");
  session
    
let start_z3 replay_file = start "z3 -smt2 -ini:z3.ini -in" replay_file true false
      
let start_mathsat replay_file = start "mathsat -verbosity=0 -interpolation=true" replay_file false true
    
let quit session = 
  writeln session "(exit)";
  close_out session.out_chan;
  close_in session.in_chan;
  (match session.replay_chan with
  | Some chan -> close_out chan
  | None -> ());
  ignore (Unix.close_process (session.in_chan, session.out_chan));
  { session with init = false }
    
let pop session = 
  if session.stack_height <= 0 then fail session "pop on empty stack" else
  writeln session "(pop 1)";
  let new_session = { session with stack_height = session.stack_height - 1 } in
  new_session

let push session = 
  writeln session "(push 1)";
  let new_session = { session with stack_height = session.stack_height + 1 } in
  new_session

let declare session sign =
  let write_decl id decl = 
    let res_sort = if decl.is_pred then "Bool" else sort_str in
    let arg_sorts = String.concat " " (Util.generate_list (fun _ -> sort_str) decl.arity) in
    writeln session ("(declare-fun " ^ str_of_ident id ^ " (" ^ arg_sorts ^ ") " ^ res_sort ^ ")")
  in
  IdMap.iter write_decl sign
    
let assert_form session ?(igroup=None) f =
  session.assert_count <- session.assert_count + 1;
    (* print_string "(assert ";
       print_smtlib_form stdout f;
       print_endline ")"; *)
  write session "(assert ";
  (match igroup with
  | Some ig -> 
      write session "(!";
      writefn session (fun chan -> print_smtlib_form chan f);
      write session (":interpolation-group " ^ string_of_int ig ^" :named a" ^ (string_of_int session.assert_count) ^ ")")
  | None ->
      match f with
      | Comment (c, f) ->
	  write session "(!";
	  writefn session (fun chan -> print_smtlib_form chan f);
	  write session (":named " ^ c ^ "_" ^ string_of_int session.assert_count ^ ")")
      | f ->
	  writefn session (fun chan -> print_smtlib_form chan f));
  writeln session ")\n"
    
let assert_form session ?(igroup=None) f = Util.measure (assert_form session ~igroup:igroup) f
    
let assert_forms session ?(igroup=None) fs =
  List.iter (fun f -> assert_form session ~igroup:igroup f) fs
    
    
let is_sat session = 
  writeln session "(check-sat)";
  match read session with
  | SmtSat -> Some true
  | SmtUnsat -> Some false
  | SmtUnknown -> None
  | SmtError e -> fail session e
  | _ -> fail session "unexpected response of prover"
	
let get_model session = 
  match is_sat session with
  | Some true | None ->
      begin
	writeln session "(get-model)";
	match read session with
	| SmtModel m -> Some ((*Axioms.simplify_model*) m)
	| SmtError e -> fail session e
	| _ -> None
      end
    | Some false -> None
	  
let get_interpolant session groups =
  match is_sat session with
  | Some true | None -> None
  | Some false ->
      begin
	let a = String.concat " " (List.map string_of_int groups) in
	writeln session ("(get-interpolant (" ^ a ^ "))");
	match read session with
	| SmtError e -> fail session e
	| SmtForm f -> Some f
	| _ -> None
      end



  

