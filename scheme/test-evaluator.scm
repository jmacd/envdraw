;;; test-evaluator.scm — Basic tests for the ported metacircular evaluator
;;;
;;; Run with: guile test-evaluator.scm
;;;
;;; Copyright (C) 2026 Josh MacDonald

(load "src/main.scm")

(define test-count 0)
(define pass-count 0)
(define fail-count 0)
(define eval-one #f)

(define (test name input expected)
  (set! test-count (+ 1 test-count))
  (display (string-append "  " name " ... "))
  (force-output)
  (let ((result
         (catch #t
           (lambda () (eval-one input))
           (lambda (key . args)
             (string-append "ERROR: " (symbol->string key)
                            " " (format #f "~a" args))))))
    (if (equal? result expected)
        (begin
          (set! pass-count (+ 1 pass-count))
          (display "PASS\n"))
        (begin
          (set! fail-count (+ 1 fail-count))
          (display "FAIL\n")
          (display (string-append "    expected: " expected "\n"))
          (display (string-append "    got:      "
                                  (if (string? result) result
                                      (format #f "~a" result))
                                  "\n"))))))

(display "\n=== EnvDraw Evaluator Tests ===\n\n")

;;; Initialize the evaluator
(display "Initializing evaluator...\n")
(let* ((obs (make-null-observer))
       (evaluator (envdraw-init obs)))
  ;; Store globally for tests
  (set! eval-one evaluator)
  ;; Set trace callback to suppress output during tests
  (set! *trace-callback* (lambda (s) #f)))

(display "\n--- Self-evaluating expressions ---\n")
(test "integer"        "42"       "42")
(test "negative"       "-7"       "-7")
(test "boolean true"   "#t"       "#t")
(test "boolean false"  "#f"       "#f")
(test "string"         "\"hello\"" "\"hello\"")
(test "empty list"     "'()"      "()")

(display "\n--- Arithmetic (primitives) ---\n")
(test "addition"       "(+ 1 2)"        "3")
(test "subtraction"    "(- 10 3)"       "7")
(test "multiplication" "(* 4 5)"        "20")
(test "nested"         "(+ (* 2 3) 4)"  "10")

(display "\n--- Define and lookup ---\n")
(test "define x"       "(define x 5)"   "x")
(test "lookup x"       "x"              "5")
(test "define y"       "(define y 10)"  "y")
(test "x + y"          "(+ x y)"        "15")

(display "\n--- Lambda and application ---\n")
(test "define square"   "(define (square n) (* n n))" "square")
(test "apply square"    "(square 5)"                   "25")
(test "define add"      "(define (add a b) (+ a b))"  "add")
(test "apply add"       "(add 3 7)"                    "10")

(display "\n--- Conditionals ---\n")
(test "if true"         "(if #t 1 2)"          "1")
(test "if false"        "(if #f 1 2)"          "2")
(test "cond"            "(cond (#f 1) (#t 2))" "2")
(test "cond else"       "(cond (#f 1) (else 3))" "3")

(display "\n--- Let ---\n")
(test "let"             "(let ((a 1) (b 2)) (+ a b))" "3")

(display "\n--- Sequencing ---\n")
(test "begin"           "(begin 1 2 3)"  "3")

(display "\n--- Boolean logic ---\n")
(test "and true"        "(and 1 2 3)"  "3")
(test "and false"       "(and 1 #f 3)" "#f")
(test "or true"         "(or #f 2 3)"  "2")
(test "or false"        "(or #f #f)"   "#f")

(display "\n--- Recursion ---\n")
(test "factorial"
  "(begin (define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5))"
  "120")

(display "\n--- Tail recursion (Max Hailperin) ---\n")
(test "iter factorial"
  "(begin (define (fact-iter n acc) (if (= n 0) acc (fact-iter (- n 1) (* n acc)))) (fact-iter 6 1))"
  "720")

(display "\n--- Mutation ---\n")
(test "set!"            "(begin (define z 1) (set! z 99) z)" "99")

(display "\n\n=== Results ===\n")
(display (string-append (number->string pass-count) " passed, "
                        (number->string fail-count) " failed, "
                        (number->string test-count) " total\n"))

(if (> fail-count 0)
    (exit 1)
    (display "\nAll tests passed!\n"))
