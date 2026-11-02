% S-expression reader. Lists are Prolog lists, nil is [], symbols are atoms,
% strings are SWI-Prolog strings and numbers are Prolog numbers.

:- module(reader, [read_forms/2]).

%!  read_forms(+Text, -Forms) is det.
%
%   Parse all forms in Text. Throws lisp_incomplete when the text ends inside a
%   form, which is how the REPL knows to keep reading, and lisp_error(Message)
%   when no further input could make it valid.
read_forms(Text, Forms) :-
    string_codes(Text, Codes),
    phrase(forms(Forms), Codes).

forms(Fs) --> ws, forms_(Fs).
forms_([]) --> eos, !.
forms_([F|Fs]) --> form(F), ws, forms_(Fs).

eos([], []).

ws --> [C], { code_type(C, space) }, !, ws.
ws --> ";", !, comment, ws.
ws --> [].

comment --> "\n", !.
comment --> [_], !, comment.
comment --> [].

form(X) --> "(", !, ws, list_items(X).
form(_) --> ")", !, { throw(lisp_error("unexpected )")) }.
form([quote, X]) --> "'", !, ws, operand(X).
form([quasiquote, X]) --> "`", !, ws, operand(X).
form(['unquote-splicing', X]) --> ",@", !, ws, operand(X).
form([unquote, X]) --> ",", !, ws, operand(X).
form(S) --> "\"", !, string_chars_(Cs), { string_codes(S, Cs) }.
form(X) --> token(Cs), { token_value(Cs, X) }.

operand(X) --> eos, !, { throw(lisp_incomplete), X = [] }.
operand(X) --> form(X).

list_items(_) --> eos, !, { throw(lisp_incomplete) }.
list_items([]) --> ")", !.
list_items(Tail) --> dot, !, ws, operand(Tail), ws, close_list.
list_items([X|Xs]) --> form(X), ws, list_items(Xs).

% A dot alone is the dotted-pair marker; it may also start a token such as `.5`.
dot, [C] --> ".", [C], { delimiter(C) }.

close_list --> eos, !, { throw(lisp_incomplete) }.
close_list --> ")", !.
close_list --> { throw(lisp_error("expected ) after dotted tail")) }.

string_chars_(_) --> eos, !, { throw(lisp_incomplete) }.
string_chars_([]) --> "\"", !.
string_chars_([C|Cs]) --> "\\", !, escape(C), string_chars_(Cs).
string_chars_([C|Cs]) --> [C], string_chars_(Cs).

escape(_) --> eos, !, { throw(lisp_incomplete) }.
escape(0'\n) --> "n", !.
escape(0'\t) --> "t", !.
escape(C) --> [C].

token([C|Cs]) --> [C], token_rest(Cs).
token_rest([C|Cs]) --> [C], { \+ delimiter(C) }, !, token_rest(Cs).
token_rest([]) --> [].

delimiter(C) :- code_type(C, space), !.
delimiter(C) :- memberchk(C, `()'"\`,;`).

token_value(Cs, X) :- number_token(Cs), catch(number_codes(X, Cs), error(_, _), fail), !.
token_value(`nil`, []) :- !.
token_value(Cs, X) :- atom_codes(X, Cs).

% number_codes/2 alone would also accept Prolog syntax such as 0'a.
number_token([S, D|Rest]) :- memberchk(S, `+-`), !, digit(D), number_rest(Rest).
number_token([D|Rest]) :- digit(D), number_rest(Rest).

digit(C) :- code_type(C, digit(_)).
number_rest(Cs) :- forall(member(C, Cs), ( digit(C) ; memberchk(C, `.eE+-`) )).
