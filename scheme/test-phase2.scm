;;; test-phase2.scm — Tests for D3 observer integration
;;;
;;; Run: guile --no-auto-compile test-phase2.scm
;;;
;;; Phase 5: The old placement, profiles, and pointer routing tests
;;; have been removed since those modules are no longer part of the
;;; build — D3.js handles all layout and rendering.

(load "src/main.scm")

(define pass-count 0)
(define fail-count 0)

(define (check name expected actual)
  (if (equal? expected actual)
      (begin
        (display (string-append "  " name " ... PASS\n"))
        (set! pass-count (+ 1 pass-count)))
      (begin
        (display (string-append "  " name " ... FAIL\n"))
        (display "    expected: ") (write expected) (newline)
        (display "    actual:   ") (write actual) (newline)
        (set! fail-count (+ 1 fail-count)))))

(define (check-pred name pred actual)
  (if (pred actual)
      (begin
        (display (string-append "  " name " ... PASS\n"))
        (set! pass-count (+ 1 pass-count)))
      (begin
        (display (string-append "  " name " ... FAIL\n"))
        (display "    actual: ") (write actual) (newline)
        (set! fail-count (+ 1 fail-count)))))

(display "\n=== Phase 2 Tests (D3 integration) ===\n\n")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "--- D3 observer integration ---\n")

;; Full integration: create observer and evaluate expressions
;; (D3 FFI calls go to no-op stubs; we verify the tracked state)
(let* ((obs (make-web-observer))
       (eval-one (envdraw-init obs)))

  ;; Define a variable — should register a frame
  (eval-one "(define x 42)")
  (check-pred "frame-ids tracked after define"
              pair? *frame-ids*)
  (check-pred "at least 1 frame after define"
              (lambda (n) (>= n 1))
              (length *frame-ids*))

  ;; Define a procedure — should register a proc
  (eval-one "(define square (lambda (n) (* n n)))")
  (check-pred "proc-ids tracked after lambda"
              pair? *proc-ids*)
  (check-pred "proc-frame-map tracked"
              pair? *proc-frame-map*)

  ;; Apply the procedure — should create another frame
  (let ((frames-before (length *frame-ids*)))
    (eval-one "(square 5)")
    (check-pred "more frames after application"
                (lambda (n) (> n frames-before))
                (length *frame-ids*)))

  ;; All frame IDs should be strings
  (for-each
   (lambda (fid)
     (check-pred (string-append "frame-id " fid " is string") string? fid))
   *frame-ids*)

  ;; All proc IDs should be strings
  (for-each
   (lambda (pid)
     (check-pred (string-append "proc-id " pid " is string") string? pid))
   *proc-ids*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n\n=== Results ===\n")
(display (string-append (number->string pass-count) " passed, "
                        (number->string fail-count) " failed, "
                        (number->string (+ pass-count fail-count)) " total\n"))

(if (= fail-count 0)
    (display "\nAll tests passed!\n")
    (begin
      (display "\nSome tests FAILED.\n")
      (exit 1)))
