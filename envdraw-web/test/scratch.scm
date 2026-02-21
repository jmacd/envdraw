;;; scratch.scm — Quick tests for diagnosing Guile compat issues

;; Load the full evaluator
(load (string-append (dirname (current-filename)) "/../src/main.scm"))

;; Test: can we directly call procedure-info-frame?
(display "=== Direct record test ===\n")
(let ((pi (make-procedure-info "test-id" "test-frame")))
  (display "procedure-info-frame: ")
  (display (procedure-info-frame pi))
  (newline)
  (display "procedure? procedure-info-frame => ")
  (display (procedure? procedure-info-frame))
  (newline))

;; Test: can we create a lambda via the evaluator?
(display "\n=== Lambda eval test ===\n")
(let* ((root (make-group-node 0 0))
       (obs (make-null-observer))
       (evaluator (envdraw-init obs)))
  (set! *trace-callback* (lambda (s) #f))
  ;; Check again after envdraw-init
  (display "After envdraw-init, procedure? procedure-info-frame => ")
  (display (procedure? procedure-info-frame))
  (newline)
  (display "procedure-info-frame value: ")
  (display procedure-info-frame)
  (newline)
  (catch #t
    (lambda ()
      ;; Try just making a procedure info directly inside the evaluator context
      (display "testing make-procedure-info: ")
      (let* ((pi (make-procedure-info "x" "y"))
             (f (procedure-info-frame pi)))
        (display f)
        (newline))
      ;; Try calling make-procedure directly
      (display "testing make-procedure (from meta.scm): \n")
      (catch #t
        (lambda ()
          (let* ((env0 (setup-environment obs))
                 (p (make-procedure '(lambda (x) x) env0)))
            (display "compound? ")
            (display (compound-procedure? p))
            (newline)
            ;; Manual steps from viewed-rep
            (let* ((po (procedure-info-of p)))
              (display "po: ") (display po) (newline)
              (display "procedure-info?: ") (display (procedure-info? po)) (newline)
              ;; Try calling the accessor directly in THIS lexical scope
              (display "direct (procedure-info-frame po): ")
              (display (procedure-info-frame po))
              (newline)
              ;; Now try viewed-rep
              (display "viewed-rep: ")
              (display (viewed-rep p))
              (newline))))
        (lambda (key . args)
          (display "make-procedure ERROR: ") (display key) (newline)
          (for-each (lambda (a) (display "  ") (display a) (newline)) args)))
      (let ((r (evaluator "(define (sq x) (* x x))")))
        (display "define sq: ") (display r) (newline))
      (let ((r (evaluator "(sq 5)")))
        (display "sq 5: ") (display r) (newline)))
    (lambda (key . args)
      (display "ERROR: ") (display key) (newline)
      (for-each (lambda (a) (display "  ") (display a) (newline)) args))))
