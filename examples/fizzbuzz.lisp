; Prints FizzBuzz up to 15.

(define (fizzbuzz n)
  (cond ((= (mod n 15) 0) 'fizzbuzz)
        ((= (mod n 5) 0) 'buzz)
        ((= (mod n 3) 0) 'fizz)
        (t n)))

(define (run i n)
  (when (<= i n)
    (print (fizzbuzz i))
    (run (+ i 1) n)))

(run 1 15)
