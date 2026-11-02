% The evaluator.
%
% Evaluation is deterministic, so the state lives in terms that are mutated in
% place with setarg/3 instead of the database, which would copy every value:
%
%   - A local scope is env(Bindings, Parent), with Bindings a list of Sym-cell(Value).
%   - The global scope is an assoc from symbol to cell(Value), held in a
%     backtrackable global variable because assoc updates build a new tree.
%
% Both kinds of mutation are undone when Prolog unwinds to a catch/3, so a form
% that raises an error leaves the state as it was before that form.
%
% Every clause reaching a Lisp tail position commits first and ends in a call to
% eval/3 or apply_fn/3, so Prolog's last-call optimization makes Lisp tail calls
% run in constant stack.

:- module(eval, [init_globals/0, eval_toplevel/2, lisp_message/2]).

:- use_module(library(assoc)).
:- use_module(printer).

%!  init_globals is det.
%
%   Reset the global scope to the primitives.
init_globals :-
    findall(Name, clause(prim(Name, _, _), _), Names0),
    append(Names0, [apply, eval], Names1),
    sort(Names1, Names),
    foldl(add_primitive, Names, t, Globals),
    b_setval(lisp_globals, Globals).

add_primitive(Name, Globals0, Globals) :-
    put_assoc(Name, Globals0, cell(prim(Name)), Globals).

%!  eval_toplevel(+Form, -Value) is det.
eval_toplevel(Form, Value) :- eval(Form, top, Value).

lisp_error(Format, Args) :-
    format(string(Message), Format, Args),
    throw(lisp_error(Message)).

%!  lisp_message(+Ball, -Message) is det.
%
%   The user-facing text of an exception raised during evaluation.
lisp_message(lisp_error(Message), Message) :- !.
lisp_message(error(evaluation_error(zero_divisor), _), "division by zero") :- !.
lisp_message(error(resource_error(_), _), "stack overflow") :- !.
lisp_message(error(type_error(evaluable, _), _), "arithmetic on a non-number") :- !.
lisp_message(Ball, Message) :- format(string(Message), "~q", [Ball]).

%   ---- Core evaluation ----

eval(X, Env, V) :-
    (   atom(X)
    ->  eval_symbol(X, Env, V)
    ;   X = [Op|Args]
    ->  eval_form(Op, Args, Env, V)
    ;   V = X
    ).

eval_symbol(t, _, t) :- !.
eval_symbol(S, Env, V) :-
    (   lookup(S, Env, cell(V0))
    ->  V = V0
    ;   lisp_error("unbound symbol: ~w", [S])
    ).

lookup(S, env(Bindings, Parent), Cell) :- !,
    (   memberchk(S-Found, Bindings)
    ->  Cell = Found
    ;   lookup(S, Parent, Cell)
    ).
lookup(S, top, Cell) :-
    b_getval(lisp_globals, Globals),
    get_assoc(S, Globals, Cell).

eval_form(Op, Args, Env, V) :-
    special(Op), !,
    special_form(Op, Args, Env, V).
eval_form(Op, Args, Env, V) :-
    eval(Op, Env, F),
    (   F = macro(Params, Body, MacroEnv)
    ->  apply_closure(Params, Body, MacroEnv, Args, Expansion),
        eval(Expansion, Env, V)
    ;   eval_args(Args, Env, Values),
        apply_fn(F, Values, V)
    ).

eval_args([], _, []) :- !.
eval_args([X|Xs], Env, [V|Vs]) :- !, eval(X, Env, V), eval_args(Xs, Env, Vs).
eval_args(_, _, _) :- lisp_error("malformed argument list", []).

eval_body([], _, []) :- !.
eval_body([X], Env, V) :- !, eval(X, Env, V).
eval_body([X|Xs], Env, V) :- eval(X, Env, _), eval_body(Xs, Env, V).

%   ---- Special forms ----

special(quote).
special(if).
special(define).
special(lambda).
special(defmacro).
special('set!').
special(begin).
special(quasiquote).

special_form(quote, [X], _, V) :- !, V = X.
special_form(if, [C, Then], Env, V) :- !, special_form(if, [C, Then, []], Env, V).
special_form(if, [C, Then, Else], Env, V) :- !,
    eval(C, Env, B),
    (   B == []
    ->  eval(Else, Env, V)
    ;   eval(Then, Env, V)
    ).
special_form(define, [[Name|Params]|Body], Env, Name) :- !,
    define(Name, closure(Params, Body, Env), Env).
special_form(define, [Name, X], Env, Name) :- atom(Name), !,
    eval(X, Env, V),
    define(Name, V, Env).
special_form(lambda, [Params|Body], Env, closure(Params, Body, Env)) :- !.
special_form(defmacro, [Name, Params|Body], Env, Name) :- atom(Name), !,
    define(Name, macro(Params, Body, Env), Env).
special_form('set!', [Name, X], Env, V) :- atom(Name), !,
    eval(X, Env, V),
    (   lookup(Name, Env, Cell)
    ->  setarg(1, Cell, V)
    ;   lisp_error("set! of unbound symbol: ~w", [Name])
    ).
special_form(begin, Body, Env, V) :- !, eval_body(Body, Env, V).
special_form(quasiquote, [X], Env, V) :- !, quasi(X, Env, V).
special_form(Op, _, _, _) :- lisp_error("malformed ~w form", [Op]).

define(Name, V, top) :- !,
    b_getval(lisp_globals, Globals0),
    (   get_assoc(Name, Globals0, Cell)
    ->  setarg(1, Cell, V)
    ;   put_assoc(Name, Globals0, cell(V), Globals),
        b_setval(lisp_globals, Globals)
    ).
define(Name, V, Env) :-
    Env = env(Bindings, _),
    (   memberchk(Name-Cell, Bindings)
    ->  setarg(1, Cell, V)
    ;   setarg(1, Env, [Name-cell(V)|Bindings])
    ).

quasi([unquote, X], Env, V) :- !, eval(X, Env, V).
quasi([[ 'unquote-splicing', X]|Rest], Env, V) :- !,
    eval(X, Env, Items),
    quasi(Rest, Env, Tail),
    splice(Items, Tail, V).
quasi([X|Xs], Env, [V|Vs]) :- !, quasi(X, Env, V), quasi(Xs, Env, Vs).
quasi(X, _, X).

splice([], Tail, Tail) :- !.
splice([X|Xs], Tail, [X|Ys]) :- !, splice(Xs, Tail, Ys).
splice(_, _, _) :- lisp_error("unquote-splicing of a non-list", []).

%   ---- Application ----

apply_fn(closure(Params, Body, Env), Args, V) :- !,
    apply_closure(Params, Body, Env, Args, V).
apply_fn(prim(apply), [F, Args], V) :- !, apply_fn(F, Args, V).
apply_fn(prim(eval), [X], V) :- !, eval(X, top, V).
apply_fn(prim(Name), Args, V) :- !,
    (   prim(Name, Args, V0)
    ->  V = V0
    ;   value_text(write, Args, Text),
        lisp_error("bad arguments to ~w: ~s", [Name, Text])
    ).
apply_fn(F, _, _) :-
    value_text(write, F, Text),
    lisp_error("not a function: ~s", [Text]).

apply_closure(Params, Body, Env, Args, V) :-
    bind_params(Params, Args, Bindings),
    eval_body(Body, env(Bindings, Env), V).

bind_params([], [], []) :- !.
bind_params(['&rest', Rest], Args, [Rest-cell(Args)]) :- !.
bind_params([P|Ps], [A|As], [P-cell(A)|Bs]) :- !, bind_params(Ps, As, Bs).
bind_params(Rest, Args, [Rest-cell(Args)]) :- atom(Rest), !.
bind_params([], _, _) :- !, lisp_error("too many arguments", []).
bind_params(_, _, _) :- lisp_error("too few arguments", []).

%   ---- Primitives ----

truth(Goal, V) :- ( call(Goal) -> V = t ; V = [] ).

prim(+, Xs, V) :- foldl(add, Xs, 0, V).
prim(*, Xs, V) :- foldl(mul, Xs, 1, V).
prim(-, [X], V) :- V is -X.
prim(-, [X, Y|Ys], V) :- foldl(sub, [Y|Ys], X, V).
prim(/, [X, Y|Ys], V) :- foldl(divide, [Y|Ys], X, V).
prim(mod, [X, Y], V) :- V is X mod Y.
prim(=, Xs, V) :- ordered(=:=, Xs, V).
prim(<, Xs, V) :- ordered(<, Xs, V).
prim(>, Xs, V) :- ordered(>, Xs, V).
prim(<=, Xs, V) :- ordered(=<, Xs, V).
prim(>=, Xs, V) :- ordered(>=, Xs, V).
prim(cons, [H, T], [H|T]).
prim(car, [X], V) :- pair_part(X, V, _).
prim(cdr, [X], V) :- pair_part(X, _, V).
prim(list, Xs, Xs).
prim('null?', [X], V) :- truth(X == [], V).
prim('atom?', [X], V) :- truth(\+ X = [_|_], V).
prim('pair?', [X], V) :- truth(X = [_|_], V).
prim('symbol?', [X], V) :- truth(atom(X), V).
prim('number?', [X], V) :- truth(number(X), V).
prim('string?', [X], V) :- truth(string(X), V).
prim('eq?', [X, Y], V) :- truth(identical(X, Y), V).
prim('equal?', [X, Y], V) :- truth(X == Y, V).
prim(print, [X], X) :- value_text(display, X, Text), writeln(Text).
prim(gensym, [], S) :- gensym('g#', S).
prim(error, Xs, _) :-
    maplist(value_text(display), Xs, Texts),
    atomic_list_concat(Texts, ' ', Message0),
    atom_string(Message0, Message),
    throw(lisp_error(Message)).

add(X, A0, A) :- A is A0 + X.
mul(X, A0, A) :- A is A0 * X.
sub(X, A0, A) :- A is A0 - X.
divide(X, A0, A) :- A is A0 / X.

pair_part([], [], []).
pair_part([H|T], H, T).

ordered(Op, [X|Xs], V) :- truth(chain(Xs, Op, X), V).

chain([], _, _).
chain([Y|Ys], Op, X) :- call(Op, X, Y), chain(Ys, Op, Y).

identical(X, Y) :- ( compound(X) -> same_term(X, Y) ; X == Y ).
