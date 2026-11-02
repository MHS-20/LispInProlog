% Program loading and the REPL.

:- module(lisp, [boot/0, eval_text/2, run_lisp/1]).

:- use_module(library(readutil)).
:- use_module(reader).
:- use_module(eval).
:- use_module(printer).

:- prolog_load_context(directory, Dir),
   directory_file_path(Dir, 'prelude.lisp', Prelude),
   assertz(prelude_path(Prelude)).
:- dynamic prelude_path/1.

%!  run_lisp(+Files) is det.
%
%   Load Files, then read forms from standard input until it ends.
run_lisp(Files) :-
    boot,
    load_files_(Files),
    repl("").

%!  boot is det.
%
%   Set up a fresh global scope with the primitives and the prelude.
boot :-
    init_globals,
    prelude_path(Path),
    load_lisp_file(Path).

load_files_([]).
load_files_([File|Files]) :- load_lisp_file(File), load_files_(Files).

load_lisp_file(File) :-
    catch(read_file_to_string(File, Text, []), error(_, _), Text = none),
    (   Text == none
    ->  format("error: cannot read ~w~n", [File])
    ;   catch(read_forms(Text, Forms), Ball, ( report(Ball), Forms = [] )),
        eval_forms(Forms)
    ).

eval_forms([]).
eval_forms([Form|Forms]) :-
    catch(eval_toplevel(Form, _), Ball, report(Ball)),
    eval_forms(Forms).

report(lisp_incomplete) :- !, writeln("error: unexpected end of input").
report(Ball) :-
    lisp_message(Ball, Message),
    format("error: ~s~n", [Message]).

%!  eval_text(+Text, -Printed) is det.
%
%   Evaluate all forms in Text, unifying Printed with the written form of the
%   last value. Exceptions propagate to the caller.
eval_text(Text, Printed) :-
    read_forms(Text, Forms),
    eval_all(Forms, [], Value),
    value_text(write, Value, Printed).

eval_all([], V, V).
eval_all([Form|Forms], _, V) :- eval_toplevel(Form, V0), eval_all(Forms, V0, V).

% The REPL recurses rather than using a failure-driven loop, because failure
% would undo the backtrackable state of everything evaluated so far.
repl(Pending) :-
    prompt(_, ''),
    ( Pending == "" -> write('> ') ; write('| ') ),
    flush_output,
    read_line_to_string(user_input, Line),
    (   Line == end_of_file
    ->  nl
    ;   string_concat(Pending, Line, Text0),
        string_concat(Text0, "\n", Text),
        repl_input(Text, Next),
        repl(Next)
    ).

repl_input(Text, Next) :-
    catch(( read_forms(Text, Forms), Next = "" ), Ball, parse_failed(Ball, Text, Forms, Next)),
    repl_eval(Forms).

parse_failed(lisp_incomplete, Text, [], Text) :- !.
parse_failed(Ball, _, [], "") :- report(Ball).

repl_eval([]).
repl_eval([Form|Forms]) :-
    catch(( eval_toplevel(Form, V), value_text(write, V, Text), writeln(Text) ),
          Ball,
          report(Ball)),
    repl_eval(Forms).
