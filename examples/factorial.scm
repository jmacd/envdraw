;; Factorial — a simple recursive definition.
(define (fact n)
  (if (= n 0)
      1
      (* n (fact (- n 1)))))

(fact 10)
