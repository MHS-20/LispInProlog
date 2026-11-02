% Test suite: swipl -g run_tests -t halt test/lisp.plt

:- use_module(library(plunit)).
:- use_module('../src/lisp').
:- use_module('../src/reader').

run(Text, Printed) :- boot, eval_text(Text, Printed).

fails_with(Text, Message) :-
    catch(( run(Text, _), Got = no_error ), lisp_error(Got), true),
    Got == Message.

:- begin_tests(reader).
test(atoms) :- read_forms("foo 42 -7 1.5 \"s\" nil", F), F == [foo, 42, -7, 1.5, "s", []].
test(symbols_like_numbers) :- read_forms("- + 1+ a-b", F), F == [-, +, '1+', 'a-b'].
test(not_prolog_numbers) :- read_forms("0a", F), F == ['0a'].
test(nesting) :- read_forms("(a (b) ())", F), F == [[a, [b], []]].
test(dotted) :- read_forms("(a . b) (a b . c)", F), F == [[a|b], [a, b|c]].
test(quotes) :- read_forms("'a `b ,c ,@d", F),
    F == [[quote, a], [quasiquote, b], [unquote, c], ['unquote-splicing', d]].
test(comment) :- read_forms("; x\n1 ; y", F), F == [1].
test(escapes) :- read_forms("\"a\\n\\\"\"", F), F == ["a\n\""].
test(incomplete, throws(lisp_incomplete)) :- read_forms("(a", _).
test(incomplete_string, throws(lisp_incomplete)) :- read_forms("\"a", _).
test(incomplete_quote, throws(lisp_incomplete)) :- read_forms("'", _).
test(unbalanced, throws(lisp_error(_))) :- read_forms(")", _).
:- end_tests(reader).

:- begin_tests(eval).
test(arith, P == "7") :- run("(+ 1 (* 2 3))", P).
test(bignum, P == "1267650600228229401496703205376") :-
    run("(define (pow b n) (if (= n 0) 1 (* b (pow b (- n 1))))) (pow 2 100)", P).
test(sub_unary, P == "-3") :- run("(- 3)", P).
test(variadic_compare, P == "t") :- run("(< 1 2 3)", P).
test(variadic_compare_false, P == "nil") :- run("(< 1 3 2)", P).
test(only_nil_false, P == "yes") :- run("(if 0 'yes 'no)", P).
test(if_no_else, P == "nil") :- run("(if nil 1)", P).
test(quote, P == "(a (b) nil)") :- run("'(a (b) nil)", P).
test(dotted_print, P == "(1 2 . 3)") :- run("(cons 1 (cons 2 3))", P).
test(string_print, P == "\"a\\nb\"") :- run("\"a\\nb\"", P).
test(car_nil, P == "nil") :- run("(car nil)", P).
test(closure, P == "5") :- run("(define (adder a) (lambda (b) (+ a b))) ((adder 2) 3)", P).
test(counter, P == "3") :-
    run("(define (mk) (define n 0) (lambda () (set! n (+ n 1)) n))
         (define c (mk)) (c) (c) (c)", P).
test(counters_independent, P == "1") :-
    run("(define (mk) (define n 0) (lambda () (set! n (+ n 1)) n))
         (define a (mk)) (define b (mk)) (a) (a) (b)", P).
test(lexical_scope, P == "1") :-
    run("(define x 1) (define (f) x) (define (g x) (f)) (g 2)", P).
test(internal_mutual_recursion, P == "t") :-
    run("(define (f n)
           (define (ev n) (if (= n 0) t (od (- n 1))))
           (define (od n) (if (= n 0) nil (ev (- n 1))))
           (ev n))
         (f 10)", P).
test(global_set, P == "2") :- run("(define x 1) (define (f) (set! x 2)) (f) x", P).
test(rest_args, P == "(1 (2 3))") :- run("((lambda (a &rest r) (list a r)) 1 2 3)", P).
test(rest_empty, P == "nil") :- run("((lambda (&rest r) r))", P).
test(dotted_params, P == "(2 3)") :- run("((lambda (a . r) r) 1 2 3)", P).
test(apply, P == "6") :- run("(apply + '(1 2 3))", P).
test(eval, P == "3") :- run("(eval '(+ 1 2))", P).
test(shadow_primitive, P == "9") :- run("(define (car x) 9) (car 1)", P).
test(eq_lists, P == "(t nil t)") :-
    run("(define a '(1)) (list (eq? a a) (eq? a '(1)) (equal? a '(1)))", P).
test(prelude, P == "((2 4) (2) 6 (3 2 1) (1 2 3 4) 3)") :-
    run("(list (map (lambda (x) (* x 2)) '(1 2))
               (filter (lambda (x) (= x 2)) '(1 2))
               (foldl + 0 '(1 2 3))
               (reverse '(1 2 3))
               (append '(1) '(2 3) '(4))
               (length '(a b c)))", P).
test(print_returns_value, P == "1") :-
    with_output_to(string(Out), run("(print 1)", P)),
    assertion(Out == "1\n").
:- end_tests(eval).

:- begin_tests(macros).
test(quasi, P == "(1 2 3 4 (5))") :- run("(define x 2) `(1 ,x ,@(list 3 4) (,(+ 2 3)))", P).
test(quasi_dotted, P == "(1 . 2)") :- run("`(1 . ,(+ 1 1))", P).
test(splice_last, P == "(1 2)") :- run("`(,@(list 1 2))", P).
test(defmacro, P == "ran") :-
    run("(defmacro my-unless (c &rest body) `(if ,c nil (begin ,@body))) (my-unless nil 'ran)", P).
test(macro_args_unevaluated, P == "(a b)") :-
    run("(defmacro q (x) `(quote ,x)) (q (a b))", P).
test(macro_evaluates_in_caller, P == "5") :-
    run("(defmacro getx () 'x) ((lambda (x) (getx)) 5)", P).
test(let, P == "3") :- run("(let ((a 1) (b 2)) (+ a b))", P).
test(let_star, P == "2") :- run("(let* ((a 1) (b (+ a 1))) b)", P).
test(cond, P == "b") :- run("(cond (nil 'a) (t 'b) (t 'c))", P).
test(cond_none, P == "nil") :- run("(cond (nil 'a))", P).
test(and, P == "2") :- run("(and 1 2)", P).
test(and_short_circuit, P == "nil") :- run("(and nil (error \"no\"))", P).
test(or_short_circuit, P == "1") :- run("(or 1 (error \"no\"))", P).
test(or_evaluates_once, P == "1") :-
    run("(define n 0) (or (begin (set! n (+ n 1)) nil) nil (set! n n)) n", P).
test(when_unless, P == "(1 nil)") :- run("(list (when t 1) (unless t 1))", P).
:- end_tests(macros).

:- begin_tests(errors).
test(unbound) :- fails_with("(foo)", "unbound symbol: foo").
test(not_function) :- fails_with("(1 2)", "not a function: 1").
test(too_few) :- fails_with("((lambda (a) a))", "too few arguments").
test(too_many) :- fails_with("((lambda () 1) 2)", "too many arguments").
test(user_error) :- fails_with("(error \"bad\" 'x 1)", "bad x 1").
test(bad_car) :- fails_with("(car 1)", "bad arguments to car: (1)").
test(malformed) :- fails_with("(if)", "malformed if form").
test(set_unbound) :- fails_with("(set! zz 1)", "set! of unbound symbol: zz").
test(rollback, P == "1") :-
    % A form that raises leaves the state as it was before that form.
    boot,
    eval_text("(define x 1)", _),
    catch(eval_text("(begin (set! x 2) (error \"e\"))", _), lisp_error(_), true),
    eval_text("x", P).
:- end_tests(errors).

:- begin_tests(limits).
test(tail_call_constant_stack, P == "done") :-
    run("(define (loop n) (if (= n 0) 'done (loop (- n 1)))) (loop 300000)", P).
test(mutual_tail_calls, P == "t") :-
    run("(define (ev n) (if (= n 0) t (od (- n 1))))
         (define (od n) (if (= n 0) nil (ev (- n 1))))
         (ev 100000)", P).
test(deep_recursion, P == "100000") :-
    run("(define (sum n) (if (= n 0) 0 (+ 1 (sum (- n 1))))) (sum 100000)", P).
test(long_list, P == "100000") :-
    run("(define (build n acc) (if (= n 0) acc (build (- n 1) (cons n acc))))
         (length (map (lambda (x) x) (build 100000 nil)))", P).
:- end_tests(limits).
