;;; renderer.scm — Scene graph renderer using Canvas2D
;;;
;;; Walks the scene graph depth-first and draws each node
;;; using the canvas-ffi procedures.
;;;
;;; Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    CONSTANTS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define PI 3.141592653589793)
(define TWO-PI (* 2 PI))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    RENDER SCENE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Top-level render call.  Clears the canvas, applies camera
;;; transform, then walks the scene graph.

(define (render-scene ctx root canvas-width canvas-height
                      camera-x camera-y zoom)
  ;; The JS side clears the canvas and sets up DPR + pan/zoom transforms
  ;; via getCanvasContext(), so we just render the scene graph here.
  (render-node ctx root 0 0))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    RENDER NODE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Render a single node and its children.
;;; parent-ax, parent-ay are the accumulated absolute position of the parent.

(define (render-node ctx node parent-ax parent-ay)
  (when (node-visible? node)
    (let ((ax (+ parent-ax (node-x node)))
          (ay (+ parent-ay (node-y node)))
          (alpha (node-opacity node)))

      ;; Set opacity if not 1.0
      (unless (= alpha 1.0)
        (canvas-save! ctx)
        (canvas-set-global-alpha! ctx alpha))

      (case (node-type node)
        ((rect)   (render-rect ctx node ax ay))
        ((oval)   (render-oval ctx node ax ay))
        ((line)   (render-line ctx node ax ay))
        ((text)   (render-text ctx node ax ay))
        ((group)  #t))  ; groups just hold children

      ;; Render children
      (for-each
       (lambda (child)
         (render-node ctx child ax ay))
       (node-children node))

      ;; Restore opacity
      (unless (= alpha 1.0)
        (canvas-restore! ctx)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    SHAPE RENDERERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (render-rect ctx node ax ay)
  (let ((w (node-width node))
        (h (node-height node))
        (fill (node-prop node 'fill))
        (stroke (node-prop node 'stroke))
        (radius (or (node-prop node 'border-radius) 0)))
    (if (> radius 0)
        ;; Rounded rectangle
        (begin
          (when fill
            (canvas-set-fill-style! ctx fill)
            (canvas-round-rect! ctx ax ay w h radius)
            (canvas-fill! ctx))
          (when stroke
            (canvas-set-stroke-style! ctx stroke)
            (canvas-set-line-width! ctx 1)
            (canvas-round-rect! ctx ax ay w h radius)
            (canvas-stroke! ctx)))
        ;; Sharp rectangle
        (begin
          (when fill
            (canvas-set-fill-style! ctx fill)
            (canvas-fill-rect! ctx ax ay w h))
          (when stroke
            (canvas-set-stroke-style! ctx stroke)
            (canvas-set-line-width! ctx 1)
            (canvas-stroke-rect! ctx ax ay w h))))))

(define (render-oval ctx node ax ay)
  (let ((w (node-width node))
        (h (node-height node))
        (fill (node-prop node 'fill))
        (stroke (node-prop node 'stroke)))
    (let ((cx (+ ax (/ w 2)))
          (cy (+ ay (/ h 2)))
          (rx (/ w 2))
          (ry (/ h 2)))
      (canvas-begin-path! ctx)
      (canvas-ellipse! ctx cx cy rx ry 0 0 TWO-PI)
      (when fill
        (canvas-set-fill-style! ctx fill)
        (canvas-fill! ctx))
      (when stroke
        (canvas-set-stroke-style! ctx stroke)
        (canvas-set-line-width! ctx 1)
        (canvas-stroke! ctx)))))

(define (render-line ctx node ax ay)
  (let ((points (node-prop node 'points))
        (stroke (node-prop node 'stroke))
        (lw (or (node-prop node 'line-width) 1))
        (has-arrow? (node-prop node 'arrow?)))
    (when (and points (>= (length points) 2))
      (canvas-set-stroke-style! ctx (or stroke "black"))
      (canvas-set-line-width! ctx lw)
      (canvas-begin-path! ctx)
      (let ((first-pt (car points)))
        (canvas-move-to! ctx
                         (+ ax (car first-pt))
                         (+ ay (cadr first-pt)))
        (for-each
         (lambda (pt)
           (canvas-line-to! ctx
                            (+ ax (car pt))
                            (+ ay (cadr pt))))
         (cdr points)))
      (canvas-stroke! ctx)
      ;; Draw arrowhead at the last point
      (when has-arrow?
        (render-arrowhead ctx points ax ay stroke lw)))))

(define (render-text ctx node ax ay)
  (let ((text (node-prop node 'text))
        (font (node-prop node 'font))
        (fill (or (node-prop node 'fill) "#333"))
        (anchor (or (node-prop node 'anchor) "start")))
    (when text
      (when font (canvas-set-font! ctx font))
      (canvas-set-fill-style! ctx fill)
      (canvas-set-text-align! ctx
                              (cond ((string=? anchor "center") "center")
                                    ((string=? anchor "end") "end")
                                    (else "start")))
      (canvas-set-text-baseline! ctx "middle")
      (canvas-fill-text! ctx text ax ay))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    ARROWHEAD
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Draw a filled triangular arrowhead at the end of a polyline.

(define (render-arrowhead ctx points ax ay stroke lw)
  (let* ((n (length points))
         (end-pt (list-ref points (- n 1)))
         (prev-pt (list-ref points (- n 2)))
         (ex (+ ax (car end-pt)))
         (ey (+ ay (cadr end-pt)))
         (px (+ ax (car prev-pt)))
         (py (+ ay (cadr prev-pt)))
         (dx (- ex px))
         (dy (- ey py))
         (len (sqrt (+ (* dx dx) (* dy dy)))))
    (when (> len 0)
      (let* ((ux (/ dx len))  ; unit vector along line
             (uy (/ dy len))
             (arrow-len 8)
             (arrow-width 4)
             ;; Base of arrowhead
             (bx (- ex (* ux arrow-len)))
             (by (- ey (* uy arrow-len)))
             ;; Perpendicular
             (lx (+ bx (* uy arrow-width)))
             (ly (- by (* ux arrow-width)))
             (rx (- bx (* uy arrow-width)))
             (ry (+ by (* ux arrow-width))))
        (canvas-begin-path! ctx)
        (canvas-move-to! ctx ex ey)
        (canvas-line-to! ctx lx ly)
        (canvas-line-to! ctx rx ry)
        (canvas-close-path! ctx)
        (canvas-set-fill-style! ctx (or stroke "black"))
        (canvas-fill! ctx)))))
