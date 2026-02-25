;;; web-observer.scm — Observer that drives D3.js visualization
;;;
;;; Phase 5: This is the glue between the metacircular evaluator and
;;; the D3.js visualization.  When the evaluator calls observer hooks,
;;; this emits graph-mutation FFI calls (d3-add-frame, d3-add-procedure,
;;; d3-add-binding, etc.) that the JavaScript side handles.
;;;
;;; The scene graph, renderer, placement, and pointer routing modules
;;; are no longer used — all visualization is handled by D3.js.
;;;
;;; Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    UTILITIES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (any pred lst)
  (cond ((null? lst) #f)
        ((pred (car lst)) #t)
        (else (any pred (cdr lst)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    ID GENERATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *next-id* 0)

(define (gen-id prefix)
  (set! *next-id* (+ 1 *next-id*))
  (string-append prefix (number->string *next-id*)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    STATE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Track frame and procedure IDs for GC sweep
(define *frame-ids* '())    ; list of frame-id strings
(define *proc-ids* '())     ; list of proc-id strings
(define *proc-frame-map* '()) ; (proc-id . frame-id) for pointer routing

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

;;; Variables required by envdraw.scm boot! (kept for compatibility)
;;; These are effectively unused with D3 rendering.
(define *scene-root* #f)
(define *render-ctx* #f)
(define *canvas-width* 800)
(define *canvas-height* 600)
(define *get-fresh-context* (lambda () #f))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    TRACE OUTPUT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *trace-callback* #f)

(define (write-trace-line s)
  (when *trace-callback*
    (*trace-callback* s)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    REQUEST RENDER (D3)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; In Phase 5, rendering is driven by D3's force simulation ticks.
;;; This function signals D3 to re-render if needed.
(define (request-render!)
  (d3-request-render))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                  MAKE WEB OBSERVER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-web-observer scene-root)
  (set! *scene-root* scene-root)
  (set! *frame-ids* '())
  (set! *proc-ids* '())
  (set! *proc-frame-map* '())
  (set! *color-index* 0)
  (make-eval-observer
   ;; on-frame-created: (env-name parent-env-id width height) → frame-id
   (lambda (env-name parent-env-id width height)
     (let* ((color (next-color!))
            (color-hex (color->hex color))
            (frame-id (gen-id "f")))
       ;; Tell D3 to add a frame node
       (d3-add-frame frame-id
                     env-name
                     (or parent-env-id "")
                     color-hex)
       ;; Track for GC
       (set! *frame-ids* (cons frame-id *frame-ids*))
       (request-render!)
       frame-id))

   ;; on-binding-placed: (frame-id var-name value value-type) → binding-id
   (lambda (frame-id var-name value value-type)
     (let* ((var-str (if (symbol? var-name)
                         (symbol->string var-name)
                         var-name))
            (val-str (if (string? value) value
                         (format-sexp value)))
            (type-str (symbol->string value-type))
            (proc-id (if (eq? value-type 'procedure)
                         (if (string? value) value val-str)
                         "")))
       ;; Tell D3 to add a binding to the frame
       (d3-add-binding frame-id var-str val-str type-str proc-id)
       (request-render!)
       ;; Return a binding id (not tracked separately)
       (gen-id "b")))

   ;; on-binding-updated: (frame-id var-name new-value value-type) → void
   (lambda (frame-id var-name new-value value-type)
     (let ((var-str (if (symbol? var-name)
                        (symbol->string var-name)
                        var-name))
           (val-str (if (string? new-value) new-value
                        (format-sexp new-value)))
           (type-str (symbol->string value-type)))
       (d3-update-binding frame-id var-str val-str type-str)
       (request-render!)))

   ;; on-procedure-created: (lambda-text frame-id) → proc-id
   (lambda (lambda-text frame-id)
     (let* ((color (next-color!))
            (color-hex (color->hex color))
            (proc-id (gen-id "p")))
       ;; Tell D3 to add a procedure node
       (d3-add-procedure proc-id lambda-text
                         (or frame-id "")
                         color-hex)
       ;; Track for GC
       (set! *proc-ids* (cons proc-id *proc-ids*))
       (set! *proc-frame-map*
             (cons (cons proc-id frame-id) *proc-frame-map*))
       (request-render!)
       proc-id))

   ;; on-env-pointer: (child-frame-id parent-frame-id) → void
   ;; D3 already creates env edges in addFrame when parentId is given.
   ;; This callback handles cases where the pointer is added later.
   (lambda (child-frame-id parent-frame-id)
     ;; The env edge is already created in d3-add-frame.
     ;; If needed, we could add a d3-add-edge call here.
     (values))

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
     (values))

   ;; on-wait-for-step: (message) → void
   (lambda (message)
     (write-trace-line message)
     (values))

   ;; on-write-trace: (string) → void
   (lambda (s)
     (write-trace-line s))

   ;; on-error: (string) → void
   (lambda (s)
     (write-trace-line (string-append "*** Error: " s)))

   ;; on-gc-mark: (object-id) → void
   (lambda (obj-id) (values))

   ;; on-gc-sweep: (object-id) → void
   (lambda (obj-id) (values))

   ;; on-request-render: () → void
   (lambda () (request-render!))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;             DRAG-AND-DROP (handled by D3 — stubs)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (handle-mouse-down! wx wy) #f)
(define (handle-mouse-move! wx wy) (values))
(define (handle-mouse-up! wx wy)   (values))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;             GARBAGE COLLECTION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (handle-gc!)
  (let* ((result (env-gc-reachable-ids))
         (reachable-frames (car result))
         (reachable-procs  (cadr result))
         (removed 0))
    ;; Remove unreachable frames from D3
    (let loop ((ids *frame-ids*) (keep '()))
      (if (null? ids)
          (set! *frame-ids* keep)
          (let ((fid (car ids)))
            (if (member fid reachable-frames)
                (loop (cdr ids) (cons fid keep))
                (begin
                  (d3-remove-node fid)
                  (set! removed (+ removed 1))
                  (loop (cdr ids) keep))))))
    ;; Remove unreachable procedures from D3
    (let loop ((ids *proc-ids*) (keep '()))
      (if (null? ids)
          (set! *proc-ids* keep)
          (let ((pid (car ids)))
            (if (member pid reachable-procs)
                (loop (cdr ids) (cons pid keep))
                (begin
                  (d3-remove-node pid)
                  (set! removed (+ removed 1))
                  (loop (cdr ids) keep))))))
    ;; Clean up proc-frame-map
    (set! *proc-frame-map*
          (filter (lambda (entry) (member (car entry) reachable-procs))
                  *proc-frame-map*))
    (request-render!)
    (write-trace-line
     (string-append "GC: removed " (number->string removed) " objects"))))
