;;; test-phase2.scm — Tests for placement, profiles, and pointer routing
;;;
;;; Run: guile --no-auto-compile test-phase2.scm

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

(display "\n=== Phase 2 Tests ===\n\n")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "--- Profile computation ---\n")

(check "zero profile xsize" 0 (profile-xsize ZERO-PROFILE))
(check "zero profile ysize" 0 (profile-ysize ZERO-PROFILE))

(let ((p (add-profiles ZERO-PROFILE ZERO-PROFILE #f)))
  (check-pred "list layout has positive width"
              (lambda (x) (> x 0))
              (profile-xsize p))
  (check-pred "list layout has positive height"
              (lambda (x) (> x 0))
              (profile-ysize p)))

(let ((p (add-profiles ZERO-PROFILE ZERO-PROFILE #t)))
  (check-pred "tree layout has positive width"
              (lambda (x) (> x 0))
              (profile-xsize p))
  (check-pred "tree layout has positive height"
              (lambda (x) (> x 0))
              (profile-ysize p)))

;; Test combining non-trivial profiles
(let* ((child-prof (list 60 30 0 (list 0 0) (list 0 0)))
       (p (add-profiles child-prof ZERO-PROFILE #f)))
  (check-pred "combined profile wider than child"
              (lambda (x) (>= x 60))
              (profile-xsize p)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n--- Constants ---\n")

(check "CELL_SIZE" 30 CELL_SIZE)
(check "SCALE" 30 SCALE)
(check "PROCEDURE_DIAMETER" 30 PROCEDURE_DIAMETER)
(check "PROCEDURE_RADIUS" 15.0 PROCEDURE_RADIUS)
(check "POINTER_WIDTH" 2 POINTER_WIDTH)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n--- Placement: metropolis ---\n")

(let ((m (make-metropolis (list 10 10) (list 100 50))))
  (check-pred "metropolis? predicate" metropolis? m)
  (check-pred "hull is dll" dll? (metropolis-hull m)))

;; Place first block
(let ((box (list #f)))
  (let ((pos1 (place-widget! box (list 100 100) (list 80 40))))
    (check-pred "first placement returns list" pair? pos1)
    (check-pred "first placement has x" number? (car pos1))
    (check-pred "first placement has y" number? (cadr pos1))
    (check-pred "metro created" metropolis? (car box))

    ;; Place second block near the first
    (let ((pos2 (place-widget! box (list (car pos1) (cadr pos1))
                               (list 80 40))))
      (check-pred "second placement returns list" pair? pos2)
      ;; Second block should be at a different position
      (check-pred "blocks at different positions"
                  (lambda (x) x)
                  (not (and (= (car pos1) (car pos2))
                            (= (cadr pos1) (cadr pos2))))))))

;; Place multiple blocks and verify they don't overlap
(let ((box (list #f))
      (positions '()))
  (do ((i 0 (+ i 1)))
      ((= i 5))
    (let ((pos (place-widget! box (list 100 100) (list 60 30))))
      (set! positions (cons pos positions))))
  (check "5 blocks placed" 5 (length positions))
  ;; Check they're all distinct
  (let ((unique (let loop ((ps positions) (seen '()))
                  (if (null? ps) seen
                      (if (member (car ps) seen)
                          (loop (cdr ps) seen)
                          (loop (cdr ps) (cons (car ps) seen)))))))
    (check "all positions unique" 5 (length unique))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n--- Pointer routing: env pointers ---\n")

;; Two non-overlapping rectangles side by side
(let ((coords (find-env-pointer '(100 200) '(50 100)  ; rect1: x 100-200, y 50-100
                                 '(300 400) '(50 100)))) ; rect2: x 300-400, y 50-100
  (check-pred "env pointer is flat list" pair? coords)
  (check-pred "env pointer has at least 4 elements"
              (lambda (x) (>= x 4))
              (length coords)))

;; Two rectangles vertically separated
(let ((coords (find-env-pointer '(100 200) '(50 100)
                                 '(100 200) '(200 250))))
  (check-pred "vertical env pointer" pair? coords))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n--- Pointer routing: cell pointers ---\n")

;; Cell pointer: far apart
(let ((coords (find-cell-pointer '(0 0) '(100 100) 5 'cdr)))
  (check-pred "cell pointer far apart" pair? coords))

;; Cell pointer: close together
(let ((coords (find-cell-pointer '(0 0) '(20 20) 5 'car)))
  (check-pred "cell pointer close" pair? coords))

;; Atom pointer
(let ((coords (find-atom-pointer '(0 0) '(50 50))))
  (check "atom pointer length" 4 (length coords))
  (check "atom pointer head" '(0 0 50 50) coords))

;; Atom pointer going up
(let ((coords (find-atom-pointer '(50 50) '(10 10))))
  (check-pred "atom pointer up has 4 elements"
              (lambda (x) (= x 4))
              (length coords)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n--- Pointer routing: procedure pointers ---\n")

;; Find procedure head
(let ((coords (find-procedure-head '(0 200) '(100 50))))
  (check-pred "procedure head coords" pair? coords)
  (check-pred "procedure head even length"
              (lambda (x) (= 0 (modulo x 2)))
              (length coords)))

;; Cell-to-proc pointer
(let ((coords (cell-to-proc-find-pointer '(0 0) '(100 100))))
  (check-pred "cell-to-proc pointer" pair? coords))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n--- Coordinate helpers ---\n")

(check "first-two" '(1 2) (first-two '(1 2 3 4)))
(check "last-two" '(3 4) (last-two '(1 2 3 4)))
(check "flat-coords->points"
       '((1 2) (3 4) (5 6))
       (flat-coords->points '(1 2 3 4 5 6)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n--- compute-pointer-path (high-level) ---\n")

;; Env pointer via high-level API
(let ((pts (compute-pointer-path 'env 0 0 100 50 200 0 100 50)))
  (check-pred "compute-pointer-path returns point list" pair? pts)
  (check-pred "each point is 2-element list"
              (lambda (x) (and (pair? x) (= 2 (length x))))
              (car pts)))

;; Atom pointer via high-level API
(let ((pts (compute-pointer-path 'atom 0 0 30 30 100 100 30 30)))
  (check-pred "atom path returns points" pair? pts))

;; Fallback straight line
(let ((pts (compute-pointer-path 'unknown 10 20 30 40 50 60 70 80)))
  (check "fallback straight line" '((10 20) (50 60)) pts))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(display "\n--- Scene graph + placement integration ---\n")

;; Full integration: create observer and evaluate expressions
(let* ((root (make-group-node 0 0))
       (obs (make-web-observer root))
       (eval-one (envdraw-init obs)))

  (set! *render-ctx* (make-test-canvas-context))

  ;; Define a variable (creates one frame + binding)
  (eval-one "(define x 42)")
  (check-pred "scene root has children after define"
              (lambda (x) (> x 0))
              (length (node-children root)))

  ;; Define a procedure (creates procedure node + pointer)
  (eval-one "(define square (lambda (n) (* n n)))")
  (let ((kid-count (length (node-children root))))
    (check-pred "more nodes after lambda"
                (lambda (x) (>= x 3))  ; frame + proc + pointer at minimum
                kid-count))

  ;; Apply the procedure (creates a new frame)
  (eval-one "(square 5)")
  (let ((kid-count (length (node-children root))))
    (check-pred "more nodes after application"
                (lambda (x) (>= x 4))
                kid-count))

  ;; Check that frame nodes were tracked
  (check-pred "frame-nodes tracked" pair? *frame-nodes*)

  ;; Check that proc nodes were tracked
  (check-pred "proc-nodes tracked" pair? *proc-nodes*)

  ;; Verify all nodes have valid positions
  (for-each
   (lambda (child)
     (when (eq? (node-type child) 'group)
       (check-pred (string-append "node " (node-id child) " has numeric x")
                   number? (node-x child))
       (check-pred (string-append "node " (node-id child) " has numeric y")
                   number? (node-y child))))
   (node-children root)))

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
