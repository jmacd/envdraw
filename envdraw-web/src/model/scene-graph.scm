;;; scene-graph.scm — Retained-mode scene graph for diagram rendering
;;;
;;; Replaces: view-classes.stk, env-classes.stk, move-composite.stk
;;;
;;; Every drawable element is a <node> record.  Nodes form a tree
;;; (parent/children).  The renderer walks the tree depth-first.
;;; Hit testing for drag-and-drop also walks this tree.
;;;
;;; Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                      NODE RECORD
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define *next-node-id* 0)

(define (gen-node-id prefix)
  (set! *next-node-id* (+ 1 *next-node-id*))
  (string-append prefix (number->string *next-node-id*)))

(define-record-type <node>
  (%make-node id type x y width height children props parent visible? opacity)
  node?
  (id       node-id)
  (type     node-type)            ; 'rect 'oval 'line 'text 'group
  (x        node-x    set-node-x!)
  (y        node-y    set-node-y!)
  (width    node-width  set-node-width!)
  (height   node-height set-node-height!)
  (children node-children set-node-children!)
  (props    node-props  set-node-props!)  ; alist of rendering properties
  (parent   node-parent set-node-parent!)
  (visible? node-visible? set-node-visible!)
  (opacity  node-opacity set-node-opacity!))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    NODE CONSTRUCTORS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-group-node x y)
  (%make-node (gen-node-id "g") 'group x y 0 0 '() '() #f #t 1.0))

(define (make-rect-node x y w h fill stroke)
  (%make-node (gen-node-id "r") 'rect x y w h '()
              `((fill . ,fill) (stroke . ,stroke))
              #f #t 1.0))

(define (make-oval-node x y w h fill stroke)
  (%make-node (gen-node-id "o") 'oval x y w h '()
              `((fill . ,fill) (stroke . ,stroke))
              #f #t 1.0))

(define (make-line-node points stroke line-width arrow?)
  (%make-node (gen-node-id "l") 'line 0 0 0 0 '()
              `((points . ,points) (stroke . ,stroke)
                (line-width . ,line-width) (arrow? . ,arrow?))
              #f #t 1.0))

(define (make-text-node x y text font fill anchor)
  (%make-node (gen-node-id "t") 'text x y 0 0 '()
              `((text . ,text) (font . ,font)
                (fill . ,fill) (anchor . ,anchor))
              #f #t 1.0))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    TREE OPERATIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (node-add-child! parent child)
  (set-node-children! parent
                      (append (node-children parent) (list child)))
  (set-node-parent! child parent))

(define (node-remove-child! parent child)
  (set-node-children! parent
                      (filter (lambda (c) (not (eq? c child)))
                              (node-children parent)))
  (set-node-parent! child #f))

(define (filter pred lst)
  (cond ((null? lst) '())
        ((pred (car lst)) (cons (car lst) (filter pred (cdr lst))))
        (else (filter pred (cdr lst)))))

;;; Translate a node by (dx, dy).  Does NOT move children in absolute
;;; terms — children have relative coordinates to their parent.
(define (node-translate! node dx dy)
  (set-node-x! node (+ (node-x node) dx))
  (set-node-y! node (+ (node-y node) dy)))

;;; Absolute position: sum of all ancestor positions
(define (node-absolute-x node)
  (if (node-parent node)
      (+ (node-x node) (node-absolute-x (node-parent node)))
      (node-x node)))

(define (node-absolute-y node)
  (if (node-parent node)
      (+ (node-y node) (node-absolute-y (node-parent node)))
      (node-y node)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    PROPERTY ACCESS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (node-prop node key)
  (let ((pair (assq key (node-props node))))
    (if pair (cdr pair) #f)))

(define (node-set-prop! node key value)
  (let ((pair (assq key (node-props node))))
    (if pair
        (set-cdr! pair value)
        (set-node-props! node (cons (cons key value)
                                    (node-props node))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                 HIT TESTING (for drag-and-drop)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Returns the deepest visible node at world coordinates (wx, wy),
;;; or #f if nothing is hit.

(define (hit-test root wx wy)
  (hit-test-node root wx wy 0 0))

(define (hit-test-node node wx wy parent-ax parent-ay)
  (if (not (node-visible? node))
      #f
      (let ((ax (+ parent-ax (node-x node)))
            (ay (+ parent-ay (node-y node))))
        ;; Check children in reverse order (topmost first)
        (let loop ((kids (reverse (node-children node))))
          (if (null? kids)
              ;; No child hit — check self
              (if (point-in-node? node wx wy ax ay)
                  node
                  #f)
              (let ((hit (hit-test-node (car kids) wx wy ax ay)))
                (if hit
                    hit
                    (loop (cdr kids)))))))))

(define (point-in-node? node wx wy ax ay)
  (case (node-type node)
    ((rect group)
     (and (>= wx ax)
          (<= wx (+ ax (node-width node)))
          (>= wy ay)
          (<= wy (+ ay (node-height node)))))
    ((oval)
     (let ((cx (+ ax (/ (node-width node) 2)))
           (cy (+ ay (/ (node-height node) 2)))
           (rx (/ (node-width node) 2))
           (ry (/ (node-height node) 2)))
       (and (> rx 0) (> ry 0)
            (<= (+ (expt (/ (- wx cx) rx) 2)
                    (expt (/ (- wy cy) ry) 2))
                1.0))))
    ((text)
     ;; Approximate: use a bounding box based on text length estimate
     (let* ((text (or (node-prop node 'text) ""))
            (est-width (* (string-length text) 8))
            (est-height 16))
       (and (>= wx ax)
            (<= wx (+ ax est-width))
            (>= wy (- ay est-height))
            (<= wy ay))))
    ((line) #f)  ; lines are not hit targets
    (else #f)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;              FIND NODE BY ID
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (find-node root id)
  (if (string=? (node-id root) id)
      root
      (let loop ((kids (node-children root)))
        (if (null? kids)
            #f
            (or (find-node (car kids) id)
                (loop (cdr kids)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;            DIAGRAM-SPECIFIC NODE CONSTRUCTORS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; These create the composite nodes that represent diagram elements.
;;; They replace the STklos class initializers from view-classes.stk
;;; and env-classes.stk.

;;; A cons cell: two adjacent half-rectangles with an interior line
;;;
;;;   ┌──────┬──────┐
;;;   │ car  │ cdr  │
;;;   └──────┴──────┘
;;;
(define (make-cons-cell-node x y cell-size fill-color)
  (let* ((w (* 2 cell-size))
         (h cell-size)
         (fill (color->hex fill-color))
         (stroke (color->hex (complement-color fill-color)))
         (group (make-group-node x y)))
    ;; Outer rectangle
    (node-add-child! group (make-rect-node 0 0 w h fill stroke))
    ;; Dividing line
    (node-add-child! group
                     (make-line-node (list (list cell-size 0)
                                          (list cell-size h))
                                    stroke 1 #f))
    (set-node-width! group w)
    (set-node-height! group h)
    group))

;;; A procedure object: two ovals with text
;;;
;;;   (  params  ) ──▶ env frame
;;;   (   body   )
;;;
(define (make-procedure-node x y lambda-text fill-color)
  (let* ((fill (color->hex fill-color))
         (stroke (color->hex (complement-color fill-color)))
         (group (make-group-node x y))
         ;; Top oval (parameters)
         (oval1 (make-oval-node 0 0 80 30 fill stroke))
         ;; Bottom oval (body, slightly offset)
         (oval2 (make-oval-node 0 25 80 30 fill stroke))
         ;; Lambda text label
         (label (make-text-node 40 42 lambda-text "12px monospace" "black" "center")))
    (node-add-child! group oval1)
    (node-add-child! group oval2)
    (node-add-child! group label)
    (set-node-width! group 80)
    (set-node-height! group 55)
    group))

;;; An environment frame: rectangle with name header
;;;
;;;   ┌─────────────────┐
;;;   │  GLOBAL ENV     │
;;;   │  x: 5           │
;;;   │  y: 10          │
;;;   └─────────────────┘
;;;
(define (make-frame-display-node x y width height name fill-color)
  (let* ((fill (color->hex fill-color))
         (stroke (color->hex (complement-color fill-color)))
         (group (make-group-node x y))
         (rect (make-rect-node 0 0 width height fill stroke))
         (title (make-text-node 5 14 name "bold 12px sans-serif"
                                "black" "start")))
    (node-add-child! group rect)
    (node-add-child! group title)
    (set-node-width! group width)
    (set-node-height! group height)
    group))

;;; A binding line inside a frame: "var: value" or "var: ──▶" (pointer)
(define (make-binding-display-node x y var-name val-text value-type)
  (let* ((group (make-group-node x y))
         (var-label (make-text-node 5 0 (string-append var-name ":")
                                   "12px monospace" "#333" "start")))
    (node-add-child! group var-label)
    (cond
     ((eq? value-type 'atom)
      ;; Show value text inline
      (let ((val-label (make-text-node (+ 10 (* (string-length var-name) 8))
                                       0 val-text
                                       "12px monospace" "#555" "start")))
        (node-add-child! group val-label)))
     ;; For 'procedure and 'pair, a pointer line will be added
     ;; by the observer/renderer
     )
    (set-node-height! group 16)
    group))

;;; A null object: diagonal line (represents empty list)
(define (make-null-display-node x y cell-size)
  (let ((group (make-group-node x y)))
    (node-add-child! group
                     (make-line-node (list (list 0 cell-size)
                                          (list cell-size 0))
                                    "black" 1 #f))
    (set-node-width! group cell-size)
    (set-node-height! group cell-size)
    group))

;;; An atom display: just text
(define (make-atom-display-node x y text)
  (let ((group (make-group-node x y)))
    (node-add-child! group
                     (make-text-node 0 12 text "14px monospace" "black" "start"))
    (set-node-width! group (* (string-length text) 8))
    (set-node-height! group 16)
    group))

;;; A pointer arrow from one node to another
(define (make-pointer-line from-x from-y to-x to-y)
  (make-line-node (list (list from-x from-y)
                        (list to-x to-y))
                  "black" 1.5 #t))
