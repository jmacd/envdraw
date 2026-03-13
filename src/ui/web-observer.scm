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

(define (filter pred lst)
  (cond ((null? lst) '())
        ((pred (car lst)) (cons (car lst) (filter pred (cdr lst))))
        (else (filter pred (cdr lst)))))

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
(define *pair-ids* '())     ; list of pair-node-id strings
(define *pair-atom-ids* '()) ; list of atom-node-id strings (leaf values in pair trees)
(define *pair-null-ids* '()) ; list of null-node-id strings
(define *proc-frame-map* '()) ; (proc-id . frame-id) for pointer routing

;;; Hash table for shared/circular pair structure detection.
;;; Maps a Scheme pair object to its already-assigned pair-node id.
;;; Reset at the start of each build-pair-tree traversal.
(define *pair-seen* '())

;;; Accumulates ALL node-ids (pairs, atoms, nulls) created during one
;;; build-pair-tree call, so register-pair-tree! can record them for
;;; cleanup during rebuild.
(define *current-tree-node-ids* '())

;;; Root pair-node id for the tree currently being built.
;;; Set by the first pair created in build-pair-node; passed to every
;;; d3-add-pair call so D3 can group nodes by tree.
(define *current-tree-root-id* #f)

;;; Current color (cycles through palette)
(define *color-index* 0)
(define *color-palette*
  (list color-ice-blue color-seafoam color-cool-sage
        color-pale-steel color-soft-teal color-mist))

(define (next-color!)
  (let ((c (list-ref *color-palette*
                     (modulo *color-index* (length *color-palette*)))))
    (set! *color-index* (+ 1 *color-index*))
    c))

;;; Reset all web-observer mutable state (called on Clear).
(define (reset-web-observer-state!)
  (set! *next-id* 0)
  (set! *frame-ids* '())
  (set! *proc-ids* '())
  (set! *pair-ids* '())
  (set! *pair-atom-ids* '())
  (set! *pair-null-ids* '())
  (set! *proc-frame-map* '())
  (set! *pair-seen* '())
  (set! *current-tree-node-ids* '())
  (set! *color-index* 0)
  (set! *pair-tree-registry* '()))

;;; Variables required by envdraw.scm boot! (kept for compatibility)
;;; These are effectively unused with D3 rendering.
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
;;;              PAIR TREE DECOMPOSITION (box-and-pointer)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Build a box-and-pointer diagram for a cons-cell value.
;;; Recursively walks car/cdr, creating D3 nodes for each cons cell,
;;; atom leaf, and null terminator.  Detects shared structure via
;;; *pair-seen* alist keyed by eq?.
;;;
;;; Returns the node-id of the root pair node.  If the pair was
;;; already seen (shared structure), returns its existing id without
;;; creating new nodes.

(define (pair-seen-lookup obj)
  ;; Search *pair-seen* for an entry whose key is eq? to obj
  (let loop ((entries *pair-seen*))
    (cond ((null? entries) #f)
          ((eq? (caar entries) obj) (cdar entries))
          (else (loop (cdr entries))))))

(define (pair-seen-add! obj id)
  (set! *pair-seen* (cons (cons obj id) *pair-seen*)))

(define (build-pair-tree obj)
  "Decompose a viewable pair into D3 cons-cell nodes and edges.
   Returns the root pair-node id string."
  (set! *pair-seen* '())
  (set! *current-tree-node-ids* '())
  (set! *current-tree-root-id* #f)
  (build-pair-node obj))

(define (build-pair-node obj)
  "Recursive helper: emit D3 nodes/edges for OBJ.
   Returns the node-id for OBJ's visual representation."
  (cond
   ;; Already seen this exact pair → shared structure
   ((and (pair? obj) (pair-seen-lookup obj))
    => (lambda (existing-id) existing-id))

   ;; Cons cell → create a pair node, recurse on car and cdr
   ((viewable-pair? obj)
    (let ((pair-id (gen-id "c")))
      ;; Register before recursing (handles circular structures)
      (pair-seen-add! obj pair-id)
      (set! *pair-ids* (cons pair-id *pair-ids*))
      (set! *current-tree-node-ids* (cons pair-id *current-tree-node-ids*))
       ;; First pair created becomes the tree root
       (when (not *current-tree-root-id*)
         (set! *current-tree-root-id* pair-id))
      ;; Compute short labels for inline display of atomic car/cdr.
      ;; Null is represented as "/" which the D3 side renders as a
      ;; diagonal slash inside the cell half (classic SICP style).
      (let* ((car-val (car obj))
             (cdr-val (cdr obj))
             (car-label (cond ((null? car-val) "/")
                              ((viewable-pair? car-val) "")
                              ((compound-procedure? car-val) "")
                              (else (viewed-rep car-val))))
             (cdr-label (cond ((null? cdr-val) "/")
                              ((viewable-pair? cdr-val) "")
                              ((compound-procedure? cdr-val) "")
                              (else (viewed-rep cdr-val)))))
        ;; Create the cons-cell node in D3 with tree-root id
        (d3-add-pair pair-id car-label cdr-label *current-tree-root-id*)
        ;; Process car child — create edges for non-inline children
        (cond
         ((null? car-val)
          ;; Null is drawn inline as "/" — no edge needed
          (values))
         ((viewable-pair? car-val)
          (let ((child-id (build-pair-node car-val)))
            (d3-add-pair-edge pair-id child-id "car")))
         ((compound-procedure? car-val)
          (let ((pid (*extract-proc-id* car-val)))
            (when pid
              (d3-add-pair-edge pair-id pid "car"))))
         ;; Atom: inline if short, external node if long
         (else
          (when (> (string-length car-label) 6)
            (let ((atom-id (gen-id "a")))
              (d3-add-pair-atom atom-id car-label)
              (set! *pair-atom-ids* (cons atom-id *pair-atom-ids*))
              (set! *current-tree-node-ids* (cons atom-id *current-tree-node-ids*))
              (d3-add-pair-edge pair-id atom-id "car")))))
        ;; Process cdr child
        (cond
         ((null? cdr-val)
          ;; Null is drawn inline as "/" — no edge needed
          (values))
         ((viewable-pair? cdr-val)
          (let ((child-id (build-pair-node cdr-val)))
            (d3-add-pair-edge pair-id child-id "cdr")))
         ((compound-procedure? cdr-val)
          (let ((pid (*extract-proc-id* cdr-val)))
            (when pid
              (d3-add-pair-edge pair-id pid "cdr"))))
         ;; Atom: inline if short, external node if long
         (else
          (when (> (string-length cdr-label) 6)
            (let ((atom-id (gen-id "a")))
              (d3-add-pair-atom atom-id cdr-label)
              (set! *pair-atom-ids* (cons atom-id *pair-atom-ids*))
              (set! *current-tree-node-ids* (cons atom-id *current-tree-node-ids*))
              (d3-add-pair-edge pair-id atom-id "cdr")))))
        pair-id)))

   ;; Not a pair — should not happen at top-level, but handle anyway
   (else
    (let ((atom-id (gen-id "a")))
      (d3-add-pair-atom atom-id (viewed-rep obj))
      (set! *pair-atom-ids* (cons atom-id *pair-atom-ids*))
      (set! *current-tree-node-ids* (cons atom-id *current-tree-node-ids*))
      atom-id))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;           PAIR TREE TRACKING & MUTATION SUPPORT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; *pair-tree-registry* — alist mapping root Scheme pair objects (by eq?)
;;; to records of their D3 visualization:
;;;   ((root-pair . (root-node-id frame-id var-name (node-id ...))) ...)
;;; This allows us to find and rebuild pair trees when set-car!/set-cdr!
;;; mutates a cell somewhere in the structure.
(define *pair-tree-registry* '())

(define (register-pair-tree! root-pair root-node-id frame-id var-name)
  "Record a pair tree so we can rebuild it on mutation."
  ;; Use *current-tree-node-ids* which tracks ALL nodes (pairs + atoms)
  ;; created during this build-pair-tree call.
  (let ((node-ids *current-tree-node-ids*))
    (set! *pair-tree-registry*
          (cons (list root-pair root-node-id frame-id var-name node-ids)
                ;; Remove any previous entry for same frame+var
                (let loop ((reg *pair-tree-registry*) (keep '()))
                  (cond ((null? reg) (reverse keep))
                        ((and (equal? (caddr (car reg)) frame-id)
                              (equal? (cadddr (car reg)) var-name))
                         (loop (cdr reg) keep))
                        (else (loop (cdr reg) (cons (car reg) keep)))))))))

(define (pair-tree-entry-root-pair  e) (car e))
(define (pair-tree-entry-root-id    e) (cadr e))
(define (pair-tree-entry-frame-id   e) (caddr e))
(define (pair-tree-entry-var-name   e) (cadddr e))
(define (pair-tree-entry-node-ids   e) (car (cddddr e)))

(define (cleanup-pair-trees-for-frame! frame-id)
  "Remove all pair-tree entries and their D3 nodes for FRAME-ID."
  (let loop ((reg *pair-tree-registry*) (keep '()))
    (cond
     ((null? reg)
      (set! *pair-tree-registry* (reverse keep)))
     ((equal? (pair-tree-entry-frame-id (car reg)) frame-id)
      (let ((node-ids (pair-tree-entry-node-ids (car reg))))
        (for-each (lambda (nid) (d3-remove-node nid)) node-ids)
        (set! *pair-ids*
              (filter (lambda (id) (not (member id node-ids))) *pair-ids*))
        (set! *pair-atom-ids*
              (filter (lambda (id) (not (member id node-ids))) *pair-atom-ids*)))
      (loop (cdr reg) keep))
     (else
      (loop (cdr reg) (cons (car reg) keep))))))

(define (find-pair-trees-containing cell)
  "Find all registered pair trees that contain CELL (by eq?)."
  (let loop ((reg *pair-tree-registry*) (found '()))
    (if (null? reg)
        found
        (let ((entry (car reg)))
          (if (pair-tree-contains? (pair-tree-entry-root-pair entry) cell '())
              (loop (cdr reg) (cons entry found))
              (loop (cdr reg) found))))))

(define (pair-tree-contains? root target seen)
  "Walk the pair structure rooted at ROOT looking for TARGET (by eq?).
   SEEN is used for cycle detection."
  (cond ((eq? root target) #t)
        ((not (pair? root)) #f)
        ((memq root seen) #f)  ; cycle — stop
        (else
         (let ((seen2 (cons root seen)))
           (or (pair-tree-contains? (car root) target seen2)
               (pair-tree-contains? (cdr root) target seen2))))))

(define (rebuild-pair-tree-for-entry entry)
  "Remove old D3 nodes for ENTRY's pair tree and rebuild it."
  (let ((old-node-ids (pair-tree-entry-node-ids entry))
        (root-pair    (pair-tree-entry-root-pair entry))
        (frame-id     (pair-tree-entry-frame-id entry))
        (var-name     (pair-tree-entry-var-name entry)))
    ;; Remove old pair nodes from D3
    (for-each (lambda (nid) (d3-remove-node nid)) old-node-ids)
    ;; Also remove old atom nodes that were part of this tree
    (set! *pair-ids*
          (let loop ((ids *pair-ids*) (keep '()))
            (cond ((null? ids) keep)
                  ((member (car ids) old-node-ids)
                   (loop (cdr ids) keep))
                  (else (loop (cdr ids) (cons (car ids) keep))))))
    (set! *pair-atom-ids*
          (let loop ((ids *pair-atom-ids*) (keep '()))
            (cond ((null? ids) keep)
                  ((member (car ids) old-node-ids)
                   (loop (cdr ids) keep))
                  (else (loop (cdr ids) (cons (car ids) keep))))))
    ;; Rebuild
    (let ((new-root-id (build-pair-tree root-pair)))
      ;; Register the new tree
      (register-pair-tree! root-pair new-root-id frame-id var-name)
      ;; Update the binding's pointer to the new root
      (d3-add-binding frame-id var-name
                      (viewed-rep root-pair) "pair" new-root-id)
      (request-render!))))

;;; Instrumented set-car!/set-cdr! for the meta-evaluator's primitives
;;; table.  These perform the mutation and then rebuild any pair trees
;;; that contain the mutated cell.
(define (envdraw-set-car! pair val)
  (set-car! pair val)
  (let ((trees (find-pair-trees-containing pair)))
    (for-each rebuild-pair-tree-for-entry trees)))

(define (envdraw-set-cdr! pair val)
  (set-cdr! pair val)
  (let ((trees (find-pair-trees-containing pair)))
    (for-each rebuild-pair-tree-for-entry trees)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                  MAKE WEB OBSERVER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-web-observer)
  (set! *frame-ids* '())
  (set! *proc-ids* '())
  (set! *pair-ids* '())
  (set! *pair-atom-ids* '())
  (set! *pair-null-ids* '())
  (set! *proc-frame-map* '())
  (set! *pair-seen* '())
  (set! *pair-tree-registry* '())
  (set! *current-tree-node-ids* '())
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
   ;; For pairs, value is the actual pair object (not a string).
   ;; For procedures, value is the proc-id string.
   ;; For atoms, value is a display string.
   (lambda (frame-id var-name value value-type)
     (let* ((var-str (if (symbol? var-name)
                         (symbol->string var-name)
                         var-name))
            (type-str (symbol->string value-type)))
       (cond
        ;; Pair: decompose into cons-cell nodes, then add binding
        ;; with a pointer to the root cons cell
        ((eq? value-type 'pair)
         (let ((root-pair-id (build-pair-tree value)))
           ;; Register for mutation tracking
           (register-pair-tree! value root-pair-id frame-id var-str)
           (d3-add-binding frame-id var-str
                           (viewed-rep value) type-str root-pair-id)
           (request-render!)
           (gen-id "b")))
        ;; Procedure: pass proc-id for binding→proc edge
        ((eq? value-type 'procedure)
         (let ((proc-id (if (string? value) value
                            (format-sexp value))))
           (d3-add-binding frame-id var-str
                           proc-id type-str proc-id)
           (request-render!)
           (gen-id "b")))
        ;; Atom: inline value string
        (else
         (let ((val-str (if (string? value) value
                            (format-sexp value))))
           (d3-add-binding frame-id var-str val-str type-str "")
           (request-render!)
           (gen-id "b"))))))

   ;; on-binding-updated: (frame-id var-name new-value value-type) → void
   ;; For pairs, new-value is the actual pair object.
   (lambda (frame-id var-name new-value value-type)
     (let ((var-str (if (symbol? var-name)
                        (symbol->string var-name)
                        var-name))
           (type-str (symbol->string value-type)))
       (cond
        ((eq? value-type 'pair)
         (let ((root-pair-id (build-pair-tree new-value)))
           (d3-update-binding frame-id var-str
                              (viewed-rep new-value) type-str)
           ;; TODO: update the binding→pair edge target
           (request-render!)))
        ;; Procedure: pass proc-id for binding→proc edge update
        ((eq? value-type 'procedure)
         (let ((proc-id (if (string? new-value) new-value
                            (format-sexp new-value))))
           (d3-update-binding frame-id var-str proc-id type-str)
           (request-render!)))
        (else
         (let ((val-str (if (string? new-value) new-value
                            (format-sexp new-value))))
           (d3-update-binding frame-id var-str val-str type-str)
           (request-render!))))))

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
   ;; Trace output is handled by write-to-trace in meta.scm → on-write-trace.
   (lambda (expr env-name indent)
     (values))

   ;; on-after-eval: (result indent-level) → void
   ;; Trace output is handled by write-to-trace in meta.scm → on-write-trace.
   (lambda (result indent)
     (values))

   ;; on-reduce: (indent-level) → void
   (lambda (indent)
     (values))

   ;; on-wait-for-step: (message) → void
   ;; The trace line is already written by write-to-trace in
   ;; wait-for-confirmation (meta.scm).  Here we only need to mark
   ;; the step boundary for the record-and-replay stepping system.
   (lambda (message)
     (notify-step-boundary))

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
   (lambda () (request-render!))

   ;; on-tail-gc: (frame-id) → void
   ;; Remove a frame that became unreachable due to a tail call.
   (lambda (frame-id)
     ;; Remove pair trees owned by this frame (before removing the frame node)
     (cleanup-pair-trees-for-frame! frame-id)
     ;; Remove the frame node from D3 (also removes edges)
     (d3-remove-node frame-id)
     ;; Remove from tracking list
     (set! *frame-ids*
           (let loop ((ids *frame-ids*) (keep '()))
             (cond ((null? ids) keep)
                   ((equal? (car ids) frame-id)
                    (loop (cdr ids) keep))
                   (else (loop (cdr ids)
                               (cons (car ids) keep))))))
     (request-render!))))

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
                  (cleanup-pair-trees-for-frame! fid)
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
