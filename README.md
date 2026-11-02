# LispInProlog

A Lisp interpreter written in SWI-Prolog, with lexical closures, `defmacro`, quasiquote, tail-call elimination and arbitrary-precision integers.

## Setup

[mise](https://mise.jdx.dev) provides SWI-Prolog through its conda backend, pinned in `mise.toml`, so nothing is installed globally.

```shell
mise trust && mise install
mise run test
mise run repl                          # start the REPL
mise run repl examples/fizzbuzz.lisp   # load files, then start the REPL
```

Press Ctrl-D to leave the REPL. A form can span several lines; the prompt changes to `|` until its parentheses balance.

## Language

Only `nil`, the empty list, is false. `t` is the conventional true value.

| Form | Meaning |
|---|---|
| `(quote x)`, `'x` | `x`, unevaluated |
| `` `(a ,b ,@c) `` | list template with unquote and splicing |
| `(if c a [b])` | conditional |
| `(define name v)`, `(define (f a) ...)` | bind in the current scope |
| `(lambda (a &rest r) ...)` | function; `&rest` or a dotted parameter list collects extra arguments |
| `(defmacro m (a) ...)` | function from unevaluated forms to a form |
| `(set! name v)` | assign to an existing binding |
| `(begin ...)` | evaluate in order, return the last value |

Primitives: `+ - * / mod = < > <= >= cons car cdr list null? atom? pair? symbol? number? string? eq? equal? apply eval print gensym error`.

The prelude adds `not cadr caddr foldl reverse length map filter append nth` and the macros `let let* cond and or when unless`.

```lisp
> (defmacro my-unless (c &rest body) `(if ,c nil (begin ,@body)))
my-unless
> (my-unless nil 'ran)
ran
```

Limits:

- Special form names are reserved and cannot be shadowed.
- Pairs are immutable, because there is no `set-car!` or `set-cdr!`.
- Nested quasiquotes are not depth-tracked.
- `/` follows Prolog: it returns an integer when the division is exact and a float otherwise.
- Macros are expanded each time they are evaluated, so they cost time inside loops.
- `mise run repl` limits the Prolog stack to 128 MB, which handles at least 100,000 nested non-tail calls and reports runaway recursion in about 20 seconds. Doubling the limit makes that report take over a minute.

## How it works

- `reader.pl` is a DCG from text to values. It reports unfinished input separately from errors, which is how the REPL knows to keep reading.
- `eval.pl` evaluates forms. Lisp lists are Prolog lists, and scopes are terms mutated in place with `setarg/3`, because the database would copy every value on each write. Tail positions commit and end in a last call, so tail-recursive Lisp code runs in constant stack.
- Mutations are backtrackable, so unwinding to `catch/3` undoes them: a form that raises an error leaves all state as it was before that form. For the same reason the REPL is a recursive loop, since a failure-driven one would erase every definition.
- `printer.pl` turns values into text. `lisp.pl` loads programs and runs the REPL, and `main.pl` is the command-line entry point.
- `prelude.lisp` defines everything that needs no interpreter support.
