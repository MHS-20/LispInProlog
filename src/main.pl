% Command-line entry point: swipl src/main.pl [file...]

:- use_module(lisp).
:- initialization(main, main).

main(Files) :- run_lisp(Files).
