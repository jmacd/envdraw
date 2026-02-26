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
;;;                    UTILITIES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (any pred lst)
  (cond ((null? lst) #f)
        ((pred (car lst)) #t)
        (else (any pred (cdr lst)))))

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

;;; Pointer registry: list of (line-node source-node target-node kind)
;;; Used to recalculate pointer paths when nodes are dragged.
(define *pointers* '())

(define (register-pointer! line-node source-node target-node kind
                          . binding-offset)
  (set! *pointers*
        (cons (list line-node source-node target-node kind
                    (if (null? binding-offset) #f (car binding-offset)))
              *pointers*)))

;;; Recalculate all pointer paths that involve a given node.
(define (update-pointers-for-node! moved-node)
  (for-each
   (lambda (entry)
     (let ((line-node   (car entry))
           (source-node (cadr entry))
           (target-node (caddr entry))
           (kind        (cadddr entry)))
       (when (or (eq? source-node moved-node)
                 (eq? target-node moved-node))
         (let* ((sx (node-x source-node))
                (sy (node-y source-node))
                (sw (node-width source-node))
                (sh (node-height source-node))
                (tx (node-x target-node))
                (ty (node-y target-node))
                (tw (node-width target-node))
                (th (node-height target-node))
                (offset (list-ref entry 4))
                (new-pts
                 (cond
                  ((eq? kind 'binding)
                   ;; Binding arrow: from dot in binding row → left-half dot of proc
                   (let ((dot-x (if offset (car offset) sw))
                         (bind-y (if offset (cdr offset) (* 0.4 sh))))
                     (list (list (+ sx dot-x) (+ sy bind-y))
                           (list (+ tx 15) (+ ty 15)))))
                  ((eq? kind 'proc-env)
                   ;; Proc env arrow: right-half dot → frame center
                   (list (list (+ sx 45) (+ sy 15))
                         (list (+ tx (* 0.5 tw))
                               (+ ty (* 0.5 th)))))
                  (else
                   ;; Env/other pointers: use full routing algorithm
                   (compute-pointer-path
                    kind sx sy sw sh tx ty tw th)))))
           (node-set-prop! line-node 'points new-pts)))))
   *pointers*))

;;; Current rendering context and canvas dimensions
(define *render-ctx* #f)
(define *canvas-width* 800)
(define *canvas-height* 600)

;;; Thunk to obtain a fresh canvas context for each render.
;;; In native/test mode, returns the cached *render-ctx*.
;;; In Wasm mode, boot! overrides this to call the FFI
;;; get-canvas-context which clears the canvas and applies
;;; DPR + pan/zoom transforms.
(define *get-fresh-context* (lambda () *render-ctx*))

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
    (if entry (cdr entry) 28)))  ; start below frame title + separator

(define (advance-insertion-point! frame-id amount)
  (let ((entry (assoc frame-id *frame-insertion-points*)))
    (if entry
        (set-cdr! entry (+ (cdr entry) amount))
        (set! *frame-insertion-points*
              (cons (cons frame-id (+ 28 amount))
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
  ;; Get a fresh context each render — in the browser,
  ;; *get-fresh-context* calls getCanvasContext() which clears
  ;; the canvas and applies DPR + pan/zoom transforms.
  (when *scene-root*
    (let ((ctx (*get-fresh-context*)))
      (when ctx
        (set! *render-ctx* ctx)
        (render-scene ctx *scene-root*
                      *canvas-width* *canvas-height*
                      0 0 1.0)))))

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
  (set! *pointers* '())
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
   ;; For value-type 'procedure, value is the proc-id (scene graph node id).
   ;; For other types, value is the viewed-rep string.
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
           (advance-insertion-point! frame-id 20)
           ;; Grow frame height if needed (with bottom padding)
           (let ((new-h (+ y-offset 30)))
             (when (> new-h (node-height frame-node))
               (set-node-height! frame-node new-h)
               ;; Update the background rectangle height
               (let ((bg-rect (car (node-children frame-node))))
                 (when (eq? (node-type bg-rect) 'rect)
                   (set-node-height! bg-rect new-h)))))
           ;; Draw binding→procedure arrow when binding a procedure
           (when (eq? value-type 'procedure)
             (let ((proc-entry (assoc value *proc-nodes*)))
               (when proc-entry
                 (let* ((proc-node (cdr proc-entry))
                        ;; Arrow from the dot in the binding row
                        (dot-x (or (node-prop binding-node 'dot-x)
                                   (node-width frame-node)))
                        (bx (+ (node-x frame-node) dot-x))
                        (by (+ (node-y frame-node) y-offset))
                        (px (node-x proc-node))
                        ;; Target: left-half dot (center at x+15, y+15)
                        (py (+ (node-y proc-node) 15))
                        (pts (list (list bx by) (list px py)))
                        (ptr (make-line-node pts "#666" 1.2 #t)))
                   (node-add-child! scene-root ptr)
                   (register-pointer! ptr frame-node proc-node 'binding
                                      (cons dot-x y-offset))))))
           (request-render!)
           (node-id binding-node)))))

   ;; on-binding-updated: (frame-id var-name new-value value-type) → void
   (lambda (frame-id var-name new-value value-type)
     (let ((frame-entry (assoc frame-id *frame-nodes*)))
       (when frame-entry
         (let* ((frame-node (cdr frame-entry))
                (var-str (if (symbol? var-name)
                             (symbol->string var-name)
                             var-name)))
           ;; Search frame children for the binding group with matching var-name
           (let loop ((kids (node-children frame-node)))
             (cond
              ((null? kids) #f)
              ((string=? (or (node-prop (car kids) 'var-name) "") var-str)
               ;; Found the binding node; find and update its val-label child
               (let ((binding-node (car kids)))
                 ;; Look for existing val-label child and update its text
                 (let vlp ((ch (node-children binding-node)))
                   (cond
                    ((null? ch)
                     ;; No val-label yet (was a pointer binding, now atom)
                     ;; Add a new value label
                     (when (eq? value-type 'atom)
                       (let ((val-label
                              (make-text-node
                               (+ 14 (* (string-length var-str) 7))
                               0 (if (string? new-value) new-value
                                     (format-sexp new-value))
                               "11px monospace" "#666" "start")))
                         (node-set-prop! val-label 'is-val-label #t)
                         (node-add-child! binding-node val-label))))
                    ((node-prop (car ch) 'is-val-label)
                     ;; Update existing val-label text
                     (node-set-prop! (car ch) 'text
                                     (if (string? new-value) new-value
                                         (format-sexp new-value))))
                    (else (vlp (cdr ch)))))))
              (else (loop (cdr kids))))))))
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
       ;; Draw routed pointer from right-half dot to enclosing frame
       (when frame-entry
         (let* ((frame-node (cdr frame-entry))
                (fx (node-x frame-node))
                (fy (node-y frame-node))
                (fw (node-width frame-node))
                (fh (node-height frame-node))
                (px (node-x proc-node))
                (py (node-y proc-node))
                ;; Right-half dot center: x = px + 45, y = py + 15
                ;; (cell-w=30, so right half center is at 30+15=45, mid-height=15)
                (dot-x (+ px 45))
                (dot-y (+ py 15))
                ;; Target: left edge center of frame
                (tx (+ fx (* 0.5 fw)))
                (ty (+ fy (* 0.5 fh)))
                (pts (list (list dot-x dot-y) (list tx ty)))
                (ptr (make-line-node pts "#666" 1.2 #t)))
           (node-add-child! scene-root ptr)
           (register-pointer! ptr proc-node frame-node 'proc-env)))
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
                (ptr (make-line-node pts "#777" 1.2 #t)))
           (node-add-child! *scene-root* ptr)
           (register-pointer! ptr child-node parent-node 'env)
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
   ;; Not used — GC is handled by handle-gc! which does full mark+sweep
   (lambda (obj-id)
     (values))

   ;; on-gc-sweep: (object-id) → void
   ;; Not used — GC is handled by handle-gc! which does full mark+sweep
   (lambda (obj-id)
     (values))

   ;; on-request-render: () → void
   (lambda ()
     (request-render!))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;             DRAG-AND-DROP (node dragging)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; State for the current drag operation
(define *drag-node* #f)       ; the node being dragged
(define *drag-offset-x* 0)    ; mouse offset from node origin
(define *drag-offset-y* 0)

(define (handle-mouse-down! wx wy)
  ;; Hit-test the scene graph to find the deepest clickable node.
  ;; Walk up to find a draggable container (frame group or proc group).
  ;; Returns #t if a draggable node was found, #f otherwise.
  (if (not *scene-root*)
      #f
      (let ((hit (hit-test *scene-root* wx wy)))
        (if (not hit)
            #f
            (let ((target (find-draggable-ancestor hit)))
              (if (not target)
                  #f
                  (begin
                    (set! *drag-node* target)
                    (set! *drag-offset-x* (- wx (node-absolute-x target)))
                    (set! *drag-offset-y* (- wy (node-absolute-y target)))
                    #t)))))))

(define (handle-mouse-move! wx wy)
  (when *drag-node*
    (let ((new-x (- wx *drag-offset-x*))
          (new-y (- wy *drag-offset-y*)))
      ;; If node has a parent, convert to relative coords
      (if (node-parent *drag-node*)
          (let ((px (node-absolute-x (node-parent *drag-node*)))
                (py (node-absolute-y (node-parent *drag-node*))))
            (set-node-x! *drag-node* (- new-x px))
            (set-node-y! *drag-node* (- new-y py)))
          (begin
            (set-node-x! *drag-node* new-x)
            (set-node-y! *drag-node* new-y)))
      ;; Recalculate any pointer arrows connected to this node
      (update-pointers-for-node! *drag-node*)
      (request-render!))))

(define (handle-mouse-up! wx wy)
  (when *drag-node*
    (update-pointers-for-node! *drag-node*)
    (request-render!)
    (set! *drag-node* #f)))

;;; Walk up the scene graph to find the nearest draggable group —
;;; i.e., a group node that is a direct child of the root (a frame
;;; or procedure top-level group).
(define (find-draggable-ancestor node)
  (cond ((not node) #f)
        ((not (node-parent node)) #f)  ; root itself is not draggable
        ;; Direct child of root → parent's parent is #f
        ((not (node-parent (node-parent node)))
         node)
        (else (find-draggable-ancestor (node-parent node)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;             GARBAGE COLLECTION (sweep unreachable nodes)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (handle-gc!)
  ;; Get reachable ids from the evaluator's environment walk
  (let* ((result (env-gc-reachable-ids))
         (reachable-frames (car result))
         (reachable-procs  (cadr result))
         (removed 0))
    ;; Sweep unreachable frame nodes
    (let loop ((entries *frame-nodes*) (keep '()))
      (if (null? entries)
          (set! *frame-nodes* keep)
          (let ((fid (caar entries))
                (fnode (cdar entries)))
            (if (member fid reachable-frames)
                (loop (cdr entries) (cons (car entries) keep))
                (begin
                  (node-remove-child! *scene-root* fnode)
                  (set! removed (+ removed 1))
                  (loop (cdr entries) keep))))))
    ;; Sweep unreachable proc nodes
    (let loop ((entries *proc-nodes*) (keep '()))
      (if (null? entries)
          (set! *proc-nodes* keep)
          (let ((pid (caar entries))
                (pnode (cdar entries)))
            (if (member pid reachable-procs)
                (loop (cdr entries) (cons (car entries) keep))
                (begin
                  (node-remove-child! *scene-root* pnode)
                  (set! removed (+ removed 1))
                  (loop (cdr entries) keep))))))
    ;; Sweep pointers whose source or target was removed
    (set! *pointers*
          (filter (lambda (entry)
                    (let ((src (cadr entry))
                          (tgt (caddr entry)))
                      (and (node-parent src) (node-parent tgt))))
                  *pointers*))
    ;; Remove orphan line nodes (pointers) from scene root
    (let loop ((kids (node-children *scene-root*)))
      (unless (null? kids)
        (let ((child (car kids)))
          (when (and (eq? (node-type child) 'line)
                     (not (node-parent (car kids))))
            ;; Already removed via pointer sweep; skip
            #f))
        (loop (cdr kids))))
    ;; Clean up orphan line-nodes whose source/target were removed
    (for-each
     (lambda (child)
       (when (eq? (node-type child) 'line)
         ;; Check if this line is still in *pointers*
         (let ((still? (any (lambda (entry) (eq? (car entry) child))
                            *pointers*)))
           (unless still?
             (node-remove-child! *scene-root* child)
             (set! removed (+ removed 1))))))
     ;; Copy the children list since we're modifying it
     (list-copy (node-children *scene-root*)))
    ;; Clean up proc-frame-map
    (set! *proc-frame-map*
          (filter (lambda (entry) (member (car entry) reachable-procs))
                  *proc-frame-map*))
    ;; Clean up insertion points for removed frames
    (set! *frame-insertion-points*
          (filter (lambda (entry) (member (car entry) reachable-frames))
                  *frame-insertion-points*))
    (request-render!)
    (write-trace-line
     (string-append "GC: removed " (number->string removed) " objects"))))
