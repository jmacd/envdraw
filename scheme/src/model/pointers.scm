;;; pointers.scm — Pointer/arrow routing algorithms
;;;
;;; Consolidated port from simple-pointer.stk, env-pointers.stk,
;;; and view-pointers.stk.  These are pure geometry routines that
;;; compute polyline paths between diagram elements.
;;;
;;; In the original, pointers were Tk canvas line items coupled to
;;; STklos objects via motion hooks.  Here, each routing function
;;; takes source/target rectangles and returns a flat list of
;;; coordinates: (x1 y1 x2 y2 ... xN yN).  The caller creates
;;; or updates a scene-graph line node with these points.
;;;
;;; Copyright (C) 1995, 1996 Josh MacDonald <jmacd@CS.Berkeley.EDU>
;;; Port Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    COORDINATE HELPERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Extract first two / last two elements of a flat coordinate list.
(define (first-two lst) (list (car lst) (cadr lst)))
(define (last-two lst)
  (let loop ((l lst))
    (if (null? (cddr l))
        (list (car l) (cadr l))
        (loop (cdr l)))))

;;; Convert a flat coordinate list (x1 y1 x2 y2 ...) into a list of
;;; (x y) pairs suitable for make-line-node's `points` property.
(define (flat-coords->points flat)
  (let loop ((rest flat) (acc '()))
    (if (null? rest)
        (reverse acc)
        (loop (cddr rest) (cons (list (car rest) (cadr rest)) acc)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                 POINTER RECORD
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; A <pointer-state> tracks the current offset corrections needed
;;; to update pointer geometry when objects move.
(define-record-type <pointer-state>
  (%make-pointer-state kind head-off tail-off spacing
                       source-node target-node line-node)
  pointer-state?
  (kind         pointer-kind)           ; 'env 'cell 'atom 'to-proc 'from-proc 'to-view 'cell-to-proc
  (head-off     pointer-head-off set-pointer-head-off!)
  (tail-off     pointer-tail-off set-pointer-tail-off!)
  (spacing      pointer-spacing)
  (source-node  pointer-source-node)    ; scene-graph node (source/parent)
  (target-node  pointer-target-node)    ; scene-graph node (target/child)
  (line-node    pointer-line-node set-pointer-line-node!))  ; the scene-graph line

(define (make-pointer-state kind source target line)
  (%make-pointer-state kind (list 0 0) (list 0 0)
                       (random-spacing)
                       source target line))

(define (random-spacing)
  ;; Randomized offset to prevent overlapping parallel pointers
  (modulo (* 7 *next-node-id*) (max 1 (inexact->exact (floor (/ CELL_SIZE 3))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;           ENVIRONMENT POINTER ROUTING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Route a pointer between two rectangles (used for env→env pointers).
;;; Arguments are x-range and y-range for each rectangle:
;;;   r1x = (left right), r1y = (top bottom)
;;;   r2x = (left right), r2y = (top bottom)
;;; Returns a flat coordinate list for the polyline path.

(define (find-env-pointer r1x r1y r2x r2y)
  (let* ((x-ordering (env-merge r1x r2x))
         (y-ordering (env-merge r1y r2y))
         (x-overlap? (check-overlap x-ordering))
         (y-overlap? (check-overlap y-ordering)))
    (cond ((and x-overlap? (not y-overlap?))
           (find-straight-x-pointer x-ordering y-ordering))
          ((and y-overlap? (not x-overlap?))
           (find-straight-y-pointer y-ordering x-ordering))
          ((not (and y-overlap? x-overlap?))
           (find-bent-pointer x-ordering y-ordering))
          (else
           (list (car r2x) (car r2y) (car r1x) (car r1y))))))

(define (env-merge one two)
  (cond ((and (null? one) (null? two)) '())
        ((null? one) (cons (cons (car two) 2) (env-merge one (cdr two))))
        ((null? two) (cons (cons (car one) 1) (env-merge (cdr one) two)))
        ((< (car one) (car two))
         (cons (cons (car one) 1) (env-merge (cdr one) two)))
        (else
         (cons (cons (car two) 2) (env-merge one (cdr two))))))

(define (check-overlap ordering)
  (or (= (cdar ordering) (cdar (cddr ordering)))      ; overlap
      (= (cdar ordering) (cdar (cdddr ordering)))))   ; one inside another

(define (find-straight-x-pointer normal-order parallel-order)
  (let ((normal-coord (* 0.5 (+ (caadr normal-order) (caaddr normal-order)))))
    (if (= 2 (cdadr parallel-order))
        (list normal-coord (caar (cdr parallel-order))
              normal-coord (caar (cddr parallel-order)))
        (list normal-coord (caar (cddr parallel-order))
              normal-coord (caar (cdr parallel-order))))))

(define (find-straight-y-pointer normal-order parallel-order)
  (let ((normal-coord (* 0.5 (+ (caadr normal-order) (caaddr normal-order)))))
    (if (= 2 (cdadr parallel-order))
        (list (caar (cdr parallel-order)) normal-coord
              (caar (cddr parallel-order)) normal-coord)
        (list (caar (cddr parallel-order)) normal-coord
              (caar (cdr parallel-order)) normal-coord))))

(define (find-bent-pointer x-order y-order)
  (let* ((x-diff (- (caar (cdr x-order)) (caar (cddr x-order))))
         (y-diff (- (caar (cdr y-order)) (caar (cddr y-order))))
         (head-x-lower (= 1 (cdar x-order)))
         (head-y-lower (= 1 (cdar y-order)))
         (x-basis (if head-x-lower (- BENT_POINTER_OFFSET)
                      BENT_POINTER_OFFSET))
         (y-basis (if head-y-lower (- BENT_POINTER_OFFSET)
                      BENT_POINTER_OFFSET))
         (tail-x (if head-x-lower (caar (cddr x-order)) (caar (cdr x-order))))
         (tail-y (if head-y-lower (caar (cddr y-order)) (caar (cdr y-order))))
         (head-x (if head-x-lower (caar (cdr x-order)) (caar (cddr x-order))))
         (head-y (if head-y-lower (caar (cdr y-order)) (caar (cddr y-order)))))
    (if (> (abs y-diff) (abs x-diff))
        (list tail-x             (- tail-y y-basis)
              (+ head-x x-basis) (- tail-y y-basis)
              (+ head-x x-basis) head-y)
        (list (- tail-x x-basis) tail-y
              (- tail-x x-basis) (+ head-y y-basis)
              head-x             (+ head-y y-basis)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;    COMPUTE ENV POINTER FROM NODE POSITIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Convenience: compute env pointer given two nodes' positions/dimensions.
(define (compute-env-pointer-coords source-x source-y source-w source-h
                                     target-x target-y target-w target-h)
  (let ((coords (find-env-pointer
                 (list target-x (+ target-x target-w))
                 (list target-y (+ target-y target-h))
                 (list source-x (+ source-x source-w))
                 (list source-y (+ source-y source-h)))))
    (flat-coords->points coords)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;              CELL POINTER ROUTING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Route a pointer between cons cells.
;;; `tail` and `head` are (x y) coordinates.
;;; `randoff` is a random offset; `ptype` is 'car or 'cdr.
;;; Returns a flat coordinate list.

(define (find-cell-pointer tail head randoff ptype)
  (let* ((dx (- (car tail) (car head)))
         (dy (- (cadr tail) (cadr head)))
         (adx (abs dx))
         (ady (abs dy)))
    (cond ((and (>= adx CELL_SIZE)
                (>= ady CELL_SIZE))
           (if (> dy 0)
               (append tail (vec+ head CELL_Y))
               (append tail head)))
          ((<= adx CELL_SIZE)
           (if (>= ady CELL_SIZE)
               (let ((can-drop?
                      (or (and (equal? ptype 'car)
                               (>= dx (- CELL_SIZE))
                               (<= dx (* 1.5 CELL_SIZE)))
                          (and (equal? ptype 'cdr)
                               (>= dx (* -1.5 CELL_SIZE))
                               (<= dx CELL_SIZE)))))
                 (if can-drop?
                     (if (< dy 0)
                         (append tail (vec+ head (list dx 0)))
                         (append tail (vec+ head CELL_Y (list dx 0))))
                     (append tail (vec+ CELL_Y head))))
               (let ((basis-y (list 0 (- CELL_SIZE)))
                     (basis-x (if (equal? ptype 'car)
                                  (list (- CELL_SIZE) 0)
                                  (list (+ CELL_SIZE) 0)))
                     (offset (if (equal? ptype 'car)
                                 (list (- randoff) 0)
                                 (list randoff 0))))
                 (append tail
                         (vec+ tail basis-x)
                         (vec+ tail basis-x basis-y)
                         (vec+ head (list 0 dy) basis-y offset)
                         (vec+ offset head)))))
          (else
           (let ((basis-y (list 0 (- CELL_SIZE)))
                 (basis-x (list (if (> dx 0) CELL_SIZE (- CELL_SIZE)) 0))
                 (cut-corner? (or (and (equal? ptype 'car) (> dx 0))
                                  (and (equal? ptype 'cdr) (< dx 0)))))
             (cond (cut-corner?
                    (cond
                     ((and (<= ady CELL_SIZE) (>= dy 0))
                      (append tail (vec+ head basis-x (list 0 dy))))
                     (else
                      (append tail
                              (vec+ head (list (- randoff) dy))
                              (vec+ (list (- randoff) 0) head)))))
                   (else
                    (append tail
                            (vec+ tail basis-y (list 0 (- randoff)))
                            (vec+ head (list 0 dy) basis-y
                                  (list randoff (- randoff)))
                            (vec+ (list randoff 0) head)))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;              ATOM POINTER ROUTING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Route a pointer from a cell to an atom (simple textual value).
(define (find-atom-pointer tail head)
  (if (>= (cadr head) (cadr tail))
      (append tail head)
      (append tail (list (car head) (+ 15 (cadr head))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;         FRAME → PROCEDURE POINTER ROUTING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Route a pointer from a frame binding to a procedure object.
;;; `tail` = top-left of frame, `head` = top-center of procedure circle
;;; `textoff` = right edge of symbol text (dx dy from tail)
;;; `height`/`width` = frame dimensions, `spacing` = random offset

(define (to-proc-find-pointer tail head textoff height width spacing)
  (let ((end-of-tail
         (find-off-frame-tail tail head textoff height width spacing)))
    (append end-of-tail
            (find-procedure-head (last-two end-of-tail) head))))

(define (find-off-frame-tail tail head textoff height width spacing)
  (let ((go-right? (> (car head) (+ (car tail) (* 0.5 width))))
        (go-up? (< (+ (* 2 PROCEDURE_DIAMETER) (cadr head)) (cadr tail)))
        (go-down? (> (cadr head) (+ (cadr tail) height))))
    (append (if go-right?
                (append (vec+ tail textoff)
                        (vec+ tail (list (+ width spacing) (cadr textoff))))
                (append (vec+ tail (list 3 (cadr textoff)))
                        (vec+ tail (list (- spacing) (cadr textoff)))))
            (cond (go-up?
                   (if go-right?
                       (vec+ tail (list (+ width spacing) (- spacing)))
                       (vec+ tail (list (- spacing) (- spacing)))))
                  (go-down?
                   (if go-right?
                       (vec+ tail (list (+ spacing width) (+ height spacing)))
                       (vec+ tail (list (- spacing) (+ spacing height)))))
                  (else '())))))

(define (find-procedure-head from head)
  (if (> (cadr from) (+ (cadr head) PROCEDURE_RADIUS))
      ;; going up
      (let ((diff (- (car head) (car from))))
        (cond ((> diff PROCEDURE_DIAMETER)
               ;; going right
               (list (car from) (+ (cadr head) PROCEDURE_RADIUS)
                     (- (car head) PROCEDURE_DIAMETER)
                     (+ (cadr head) PROCEDURE_RADIUS)))
              ((< diff (- PROCEDURE_DIAMETER))
               ;; going left
               (list (car from) (+ (cadr head) PROCEDURE_RADIUS)
                     (+ (car head) PROCEDURE_DIAMETER)
                     (+ (cadr head) PROCEDURE_RADIUS)))
              ((> diff 0)
               (append (list (- (car head) (* 2 PROCEDURE_DIAMETER))
                             (cadr from))
                       (vec+ head (list (* -2 PROCEDURE_DIAMETER)
                                        PROCEDURE_RADIUS))
                       (vec+ head (list (- PROCEDURE_DIAMETER)
                                        PROCEDURE_RADIUS))))
              (else
               (append (list (+ (car head) (* 2 PROCEDURE_DIAMETER))
                             (cadr from))
                       (vec+ head (list (* 2 PROCEDURE_DIAMETER)
                                        PROCEDURE_RADIUS))
                       (vec+ head (list PROCEDURE_DIAMETER
                                        PROCEDURE_RADIUS))))))
      ;; going down
      (if (> (car from) (car head))
          ;; going left
          (vec+ head (list PROCEDURE_RADIUS 0))
          ;; going right
          (vec+ head (list (- PROCEDURE_RADIUS) 0)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;         PROCEDURE → FRAME POINTER ROUTING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Route a pointer from a procedure to a frame (for the body-env pointer).
(define (from-proc-find-pointer tail head height width)
  (append tail
          (vec- tail (list 0 PROCEDURE_DIAMETER))
          (let* ((x (car tail))
                 (y (- (cadr tail) PROCEDURE_DIAMETER))
                 (minx (car head))
                 (maxx (+ minx width))
                 (miny (cadr head))
                 (maxy (+ (cadr head) height)))
            (cond ((< y miny)
                   (cond ((< x minx)
                          ;; shoot right
                          (append (list (max (+ minx BENT_POINTER_OFFSET)
                                             (+ x PROCEDURE_DIAMETER))
                                        y)
                                  (vec+ head (list (max BENT_POINTER_OFFSET
                                                        (+ PROCEDURE_DIAMETER
                                                           (- x minx)))
                                                   0))))
                         ((> x (+ maxx (* 1.5 PROCEDURE_DIAMETER)))
                          ;; shoot left
                          (append (list (- maxx BENT_POINTER_OFFSET) y)
                                  (vec+ head (list (- width BENT_POINTER_OFFSET)
                                                   0))))
                         ((< x (- maxx (* 1.5 PROCEDURE_DIAMETER)))
                          (append (list (+ x PROCEDURE_DIAMETER) y)
                                  (list (+ x PROCEDURE_DIAMETER) miny)))
                         (else
                          (append (list (- x (* 2 PROCEDURE_DIAMETER)) y)
                                  (list (- x (* 2 PROCEDURE_DIAMETER)) miny)))))
                  ((< y (- maxy BENT_POINTER_OFFSET))
                   (if (< x minx)
                       (list minx y)
                       (list maxx y)))
                  ((< x minx)
                   (append (list x (- maxy BENT_POINTER_OFFSET))
                           (list minx (- maxy BENT_POINTER_OFFSET))))
                  ((> x maxx)
                   (append (list x (- maxy BENT_POINTER_OFFSET))
                           (list maxx (- maxy BENT_POINTER_OFFSET))))
                  (else
                   (list x maxy))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;    CELL → PROCEDURE POINTER ROUTING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Route a pointer from a cons cell to a procedure circle.
(define (cell-to-proc-find-pointer tail head)
  (append tail (find-procedure-head tail head)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; VIEW POINTER ROUTING (frame → viewed cell tree)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (to-view-find-pointer tail head textoff height width spacing)
  (let ((end-of-tail
         (find-off-frame-tail tail head textoff height width spacing)))
    (append end-of-tail
            (find-view-head (last-two end-of-tail) head))))

(define (find-view-head from head)
  (find-cell-pointer from head 0 (if (> (car head) (car from)) 'cdr 'car)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;    HIGH-LEVEL: COMPUTE POINTER FOR TWO NODES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Given source and target scene-graph node positions and dimensions,
;;; compute pointer path as a list of (x y) points.

(define (compute-pointer-path kind
                              src-x src-y src-w src-h
                              tgt-x tgt-y tgt-w tgt-h
                              . extra)
  (let ((coords
         (case kind
           ((env)
            (find-env-pointer
             (list tgt-x (+ tgt-x tgt-w))
             (list tgt-y (+ tgt-y tgt-h))
             (list src-x (+ src-x src-w))
             (list src-y (+ src-y src-h))))
           ((cell)
            (let ((randoff (if (null? extra) 0 (car extra)))
                  (ptype   (if (or (null? extra) (null? (cdr extra)))
                               'cdr (cadr extra))))
              (find-cell-pointer (list src-x src-y) (list tgt-x tgt-y)
                                 randoff ptype)))
           ((atom)
            (find-atom-pointer (list src-x src-y) (list tgt-x tgt-y)))
           ((to-proc)
            (let ((textoff (if (null? extra) (list 50 10) (car extra)))
                  (spacing (if (or (null? extra) (null? (cdr extra)))
                               15 (cadr extra))))
              (to-proc-find-pointer (list src-x src-y) (list tgt-x tgt-y)
                                    textoff src-h src-w spacing)))
           ((from-proc)
            (from-proc-find-pointer (list src-x src-y) (list tgt-x tgt-y)
                                    tgt-h tgt-w))
           ((cell-to-proc)
            (cell-to-proc-find-pointer (list src-x src-y) (list tgt-x tgt-y)))
           (else
            ;; Fallback: straight line
            (list src-x src-y tgt-x tgt-y)))))
    (flat-coords->points coords)))
