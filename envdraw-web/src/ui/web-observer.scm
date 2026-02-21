;;; web-observer.scm — Concrete observer that builds scene graph nodes
;;;
;;; This is the glue between the metacircular evaluator and the
;;; visual output.  When the evaluator calls observer hooks, this
;;; creates scene graph nodes, places them, and triggers re-rendering.
;;;
;;; Phase 2 upgrade: uses convex-hull placement (placement.scm),
;;; proper pointer routing (pointers.scm), and cell profiles
;;; (profiles.scm) instead of simple grid layout.
;;;
;;; Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    STATE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; The root node of the scene graph
(define *scene-root* #f)

;;; Map from frame-id → frame display node
(define *frame-nodes* '())

;;; Map from proc-id → procedure display node
(define *proc-nodes* '())

;;; Map from proc-id → enclosing frame-id (for pointer routing)
(define *proc-frame-map* '())

;;; Current rendering context and canvas dimensions
(define *render-ctx* #f)
(define *canvas-width* 800)
(define *canvas-height* 600)

;;; Camera state
(define *camera-x* 0)
(define *camera-y* 0)
(define *camera-zoom* 1.0)

;;; Render pending flag (coalesce multiple updates)
(define *render-pending?* #f)

;;; Current color (cycles through palette)
(define *color-index* 0)
(define *color-palette*
  (list color-palegreen color-lemonchiffon color-lightblue
        color-lightyellow color-pink color-lavender))

(define (next-color!)
  (let ((c (list-ref *color-palette*
                     (modulo *color-index* (length *color-palette*)))))
    (set! *color-index* (+ 1 *color-index*))
    c))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;             PLACEMENT STATE (convex hull)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; One-element list holding the metropolis record, or (list #f).
(define *metro-box* (list #f))

;;; Collect all placed objects for hull regeneration.
;;; Each entry: (node-id . ((x y) . (w h)))
(define *placed-rects* '())

(define (register-placed-rect! node)
  (set! *placed-rects*
        (cons (cons (node-id node)
                    (cons (list (node-x node) (node-y node))
                          (list (node-width node) (node-height node))))
              *placed-rects*)))

(define (get-node-center node)
  (list (+ (node-x node) (* 0.5 (node-width node)))
        (+ (node-y node) (* 0.5 (node-height node)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;             LAYOUT: PLACE A NODE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Place a new node near `near-node` (or at default position if #f).
(define (place-node! node near-node)
  (let* ((dim (list (node-width node) (node-height node)))
         (near-center (if near-node
                          (get-node-center near-node)
                          PLACEMENT_INITIAL_POSITION))
         (pos (place-widget! *metro-box* near-center dim)))
    (set-node-x! node (car pos))
    (set-node-y! node (cadr pos))
    (register-placed-rect! node)))

;;; Insertion tracking per frame (y-offset for next binding)
(define *frame-insertion-points* '())

(define (get-insertion-point frame-id)
  (let ((entry (assoc frame-id *frame-insertion-points*)))
    (if entry (cdr entry) 24)))  ; start below frame title

(define (advance-insertion-point! frame-id amount)
  (let ((entry (assoc frame-id *frame-insertion-points*)))
    (if entry
        (set-cdr! entry (+ (cdr entry) amount))
        (set! *frame-insertion-points*
              (cons (cons frame-id (+ 24 amount))
                    *frame-insertion-points*)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    TRACE OUTPUT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; *trace-callback* — set by the UI layer to a procedure that
;;; appends text to the trace panel DOM element.
(define *trace-callback* #f)

(define (write-trace-line s)
  (when *trace-callback*
    (*trace-callback* s)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    REQUEST RENDER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (request-render!)
  ;; Immediate render for now (in browser, use requestAnimationFrame)
  (when (and *render-ctx* *scene-root*)
    (render-scene *render-ctx* *scene-root*
                  *canvas-width* *canvas-height*
                  *camera-x* *camera-y* *camera-zoom*)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                  MAKE WEB OBSERVER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-web-observer scene-root)
  (set! *scene-root* scene-root)
  (set! *metro-box* (list #f))
  (set! *placed-rects* '())
  (set! *frame-nodes* '())
  (set! *proc-nodes* '())
  (set! *proc-frame-map* '())
  (set! *frame-insertion-points* '())
  (set! *color-index* 0)
  (make-eval-observer
   ;; on-frame-created: (env-name parent-env-id width height) → frame-id
   (lambda (env-name parent-env-id width height)
     (let* ((color (next-color!))
            (frame-node (make-frame-display-node
                         0 0  ; positioned later by placement
                         width height
                         env-name color))
            (frame-id (node-id frame-node))
            ;; Find parent frame node for placement heuristic
            (parent-node
             (if parent-env-id
                 (let ((entry (assoc parent-env-id *frame-nodes*)))
                   (if entry (cdr entry) #f))
                 #f)))
       (node-add-child! scene-root frame-node)
       ;; Place using convex-hull algorithm
       (place-node! frame-node parent-node)
       ;; Track this frame node
       (set! *frame-nodes* (cons (cons frame-id frame-node) *frame-nodes*))
       (request-render!)
       frame-id))

   ;; on-binding-placed: (frame-id var-name value value-type) → binding-id
   (lambda (frame-id var-name value value-type)
     (let ((frame-entry (assoc frame-id *frame-nodes*)))
       (when frame-entry
         (let* ((frame-node (cdr frame-entry))
                (y-offset (get-insertion-point frame-id))
                (binding-node (make-binding-display-node
                               0 y-offset
                               (if (symbol? var-name)
                                   (symbol->string var-name)
                                   var-name)
                               (if (string? value) value
                                   (format-sexp value))
                               value-type)))
           (node-add-child! frame-node binding-node)
           (advance-insertion-point! frame-id 18)
           ;; Grow frame height if needed
           (let ((new-h (+ y-offset 24)))
             (when (> new-h (node-height frame-node))
               (set-node-height! frame-node new-h)
               ;; Update the background rectangle height
               (let ((bg-rect (car (node-children frame-node))))
                 (when (eq? (node-type bg-rect) 'rect)
                   (set-node-height! bg-rect new-h)))))
           (request-render!)
           (node-id binding-node)))))

   ;; on-binding-updated: (frame-id var-name new-value value-type) → void
   (lambda (frame-id var-name new-value value-type)
     ;; TODO: find and update the binding display node
     (request-render!))

   ;; on-procedure-created: (lambda-text frame-id) → proc-id
   (lambda (lambda-text frame-id)
     (let* ((color (next-color!))
            (proc-node (make-procedure-node
                        0 0   ; positioned by placement
                        lambda-text color))
            (proc-id (node-id proc-node))
            ;; Find enclosing frame for placement
            (frame-entry (assoc frame-id *frame-nodes*))
            (near-node (if frame-entry (cdr frame-entry) #f)))
       (node-add-child! scene-root proc-node)
       ;; Place near the enclosing frame
       (place-node! proc-node near-node)
       ;; Draw routed pointer from procedure to enclosing frame
       (when frame-entry
         (let* ((frame-node (cdr frame-entry))
                (fx (node-x frame-node))
                (fy (node-y frame-node))
                (fw (node-width frame-node))
                (fh (node-height frame-node))
                (px (node-x proc-node))
                (py (node-y proc-node))
                (pw (node-width proc-node))
                (ph (node-height proc-node))
                ;; Use env pointer routing between the proc and frame
                (pts (compute-pointer-path
                      'env
                      px py pw ph
                      fx fy fw fh))
                (ptr (make-line-node pts "black" 1.5 #t)))
           (node-add-child! scene-root ptr)))
       (set! *proc-nodes* (cons (cons proc-id proc-node) *proc-nodes*))
       (set! *proc-frame-map* (cons (cons proc-id frame-id) *proc-frame-map*))
       (request-render!)
       proc-id))

   ;; on-env-pointer: (child-frame-id parent-frame-id) → void
   (lambda (child-frame-id parent-frame-id)
     (let ((child-entry (assoc child-frame-id *frame-nodes*))
           (parent-entry (assoc parent-frame-id *frame-nodes*)))
       (when (and child-entry parent-entry)
         (let* ((child-node (cdr child-entry))
                (parent-node (cdr parent-entry))
                (cx (node-x child-node))
                (cy (node-y child-node))
                (cw (node-width child-node))
                (ch (node-height child-node))
                (px (node-x parent-node))
                (py (node-y parent-node))
                (pw (node-width parent-node))
                (ph (node-height parent-node))
                ;; Use proper pointer routing between frames
                (pts (compute-pointer-path
                      'env
                      cx cy cw ch
                      px py pw ph))
                (ptr (make-line-node pts "#555" 1.5 #t)))
           (node-add-child! *scene-root* ptr)
           (request-render!)))))

   ;; on-before-eval: (expr env-name indent-level) → void
   (lambda (expr env-name indent)
     (write-trace-line
      (string-append (make-string indent #\space)
                     "EVAL in " env-name ": " expr)))

   ;; on-after-eval: (result indent-level) → void
   (lambda (result indent)
     (write-trace-line
      (string-append (make-string indent #\space)
                     "RETURNING: " result)))

   ;; on-reduce: (indent-level) → void
   (lambda (indent)
     ;; No trace output for reductions (matches original behavior)
     (values))

   ;; on-wait-for-step: (message) → void
   (lambda (message)
     (write-trace-line message)
     ;; TODO: suspend fiber until Step/Continue button is clicked
     (values))

   ;; on-write-trace: (string) → void
   (lambda (s)
     (write-trace-line s))

   ;; on-error: (string) → void
   (lambda (s)
     (write-trace-line (string-append "*** Error: " s)))

   ;; on-gc-mark: (object-id) → void
   (lambda (obj-id)
     ;; TODO: reduce opacity of garbage nodes
     (values))

   ;; on-gc-sweep: (object-id) → void
   (lambda (obj-id)
     ;; TODO: remove garbage nodes from scene graph
     (values))

   ;; on-request-render: () → void
   (lambda ()
     (request-render!))))
