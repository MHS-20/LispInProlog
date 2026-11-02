% Converts Lisp values to text.

:- module(printer, [value_text/3]).

%!  value_text(+Style, +Value, -Text) is det.
%
%   Style is `write`, showing strings as readable literals, or `display`, showing
%   their bare contents.
value_text(Style, Value, Text) :-
    with_output_to(string(Text), print_value(Style, Value)).

print_value(_, []) :- !, write(nil).
print_value(Style, [H|T]) :- !,
    write('('), print_value(Style, H), print_tail(Style, T), write(')').
print_value(write, S) :- string(S), !, print_string(S).
print_value(_, closure(_, _, _)) :- !, write('#<lambda>').
print_value(_, macro(_, _, _)) :- !, write('#<macro>').
print_value(_, prim(Name)) :- !, format("#<primitive ~w>", [Name]).
print_value(_, X) :- write(X).

print_tail(_, []) :- !.
print_tail(Style, [H|T]) :- !, write(' '), print_value(Style, H), print_tail(Style, T).
print_tail(Style, X) :- write(' . '), print_value(Style, X).

print_string(S) :-
    string_codes(S, Cs),
    write('"'), forall(member(C, Cs), print_code(C)), write('"').

print_code(0'") :- !, write('\\"').
print_code(0'\\) :- !, write('\\\\').
print_code(0'\n) :- !, write('\\n').
print_code(0'\t) :- !, write('\\t').
print_code(C) :- put_char_code(C).

put_char_code(C) :- char_code(Ch, C), write(Ch).
