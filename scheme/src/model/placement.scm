;;; placement.scm — Convex-hull–based placement algorithm
;;;
;;; Ported from placement.stk — places new diagram elements around
;;; the perimeter of the existing layout using an incremental convex
;;; hull.  Replaces the simple grid layout in the first prototype.
;;;
;;; Copyright (C) 1995, 1996 Josh MacDonald <jmacd@CS.Berkeley.EDU>
;;; Port Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    CONFIGURATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define PLACEMENT_SPACING (list 30 30))
(define 1/2PLACEMENT_SPACING (vec* 0.5 PLACEMENT_SPACING))
(define PLACEMENT_INITIAL_POSITION (list 50 50))
(define MINIMUM_GAP_WIDTH 100)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                   POINT HELPERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; These operate on 2-element lists (x y) using vec+/vec-/vec* from
;;; math.scm.  Additional geometry helpers specific to placement.

(define (x-coord p) (car p))
(define (y-coord p) (cadr p))

(define (coincident? a b)
  (and (= (x-coord a) (x-coord b))
       (= (y-coord a) (y-coord b))))

(define (orthocolinear? p1 p2 p3)
  (or (= (x-coord p1) (x-coord p2) (x-coord p3))
      (= (y-coord p1) (y-coord p2) (y-coord p3))))

(define (separation-squared p1 p2)
  (let ((d (vec- p1 p2)))
    (+ (let ((x (x-coord d))) (* x x))
       (let ((y (y-coord d))) (* y y)))))

(define (magnitude-squared p1)
  (+ (let ((x (x-coord p1))) (* x x))
     (let ((y (y-coord p1))) (* y y))))

(define (cross-product a b)
  (- (* (x-coord a) (y-coord b))
     (* (x-coord b) (y-coord a))))

(define (counter-clockwise? reference a b)
  (< 0 (cross-product (vec- a reference) (vec- b reference))))

(define (clockwise? reference a b)
  (not (counter-clockwise? reference a b)))

(define (prefered-point? ver1 ver2)
  (let ((ver1y (y-coord ver1))
        (ver2y (y-coord ver2)))
    (if (= ver1y ver2y)
        (< (x-coord ver1) (x-coord ver2))
        (< ver1y ver2y))))

(define (parallel-mask point basis)
  ;; Returns a point with the non-zero coordinate of basis zeroed in point
  (if (= 0 (x-coord basis))
      (list 0 (y-coord point))
      (list (x-coord point) 0)))

(define (ortho-magnitude a)
  ;; Assumes one coord is 0
  (+ (x-coord a) (y-coord a)))

(define (find-intersection line1-1 line1-2 line2-1 line2-2)
  ;; Finds intersection of two perpendicular axis-aligned line segments.
  (if (= (x-coord line1-1) (x-coord line1-2))
      (cond ((ordered? (y-coord line1-1) (y-coord line2-1) (y-coord line1-2))
             (list (x-coord line1-1) (y-coord line2-1)))
            ((ordered? (x-coord line2-1) (x-coord line1-1) (x-coord line2-2))
             (list (x-coord line1-1) (y-coord line2-1)))
            (else #f))
      (cond ((ordered? (x-coord line1-1) (x-coord line2-1) (x-coord line1-2))
             (list (x-coord line2-1) (y-coord line1-1)))
            ((ordered? (y-coord line2-1) (y-coord line1-1) (y-coord line2-2))
             (list (x-coord line2-1) (y-coord line1-1)))
            (else #f))))

(define (convex-hull-vertex? hull)
  (counter-clockwise? (dll-data (dll-prev hull))
                      (dll-data hull)
                      (dll-data (dll-next hull))))

(define (ordered? n1 n2 n3)
  (if (>= n1 n2) (>= n2 n3) (<= n2 n3)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    CENTER / DIMENSION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; For node-based objects, extract geometric properties.
(define (center-of-rect coords dimension)
  (list (+ (x-coord coords) (* 0.5 (x-coord dimension)))
        (+ (y-coord coords) (* 0.5 (y-coord dimension)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    METROPOLIS (Convex Hull)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-record-type <metropolis>
  (%make-metropolis hull)
  metropolis?
  (hull metropolis-hull set-metropolis-hull!))

;;; Create a new metropolis initialized with one rectangle at coords
;;; with the given dimension.
(define (make-metropolis coords dimension)
  (let* ((minx (x-coord coords))
         (miny (y-coord coords))
         (maxx (+ (x-coord coords) (x-coord dimension)))
         (maxy (+ (y-coord coords) (y-coord dimension)))
         (ring (make-cdll (list minx miny))))
    (insert-after! ring (list minx maxy))
    (insert-after! ring (list maxx maxy))
    (insert-after! ring (list maxx miny))
    (%make-metropolis ring)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    FIND CLOSEST POINT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; O(n) scan of the hull to find the point closest to `near-center`.
(define (find-closest-point metro near-center)
  (let* ((hull (metropolis-hull metro))
         (minval (separation-squared near-center (dll-data hull)))
         (minpnt hull))
    (let loop ((h (dll-next hull)))
      (if (eq? h hull)
          minpnt
          (let ((val (separation-squared near-center (dll-data h))))
            (if (< val minval)
                (begin (set! minval val)
                       (set! minpnt h)
                       (loop (dll-next h)))
                (loop (dll-next h))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    OUTWARD PARALLEL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Returns the vector going from point p away from t,
;;; with the magnitude of dimension's coordinate in the same axis.
(define (outward-parallel p t dimension)
  (let ((px (x-coord p))
        (py (y-coord p))
        (tx (x-coord t))
        (ty (y-coord t)))
    (if (= px tx)
        (list 0 (if (< ty py)
                    (y-coord dimension)
                    (- (y-coord dimension))))
        (list (if (< tx px)
                  (x-coord dimension)
                  (- (x-coord dimension)))
              0))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    UPPER-LEFT CORNER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Given a corner point and an offset representing the distance to the
;;; other corner, return the position at the upper-left  (lower y and x).
(define (upper-left-corner point offset)
  (let ((x (x-coord offset))
        (y (y-coord offset)))
    (vec+ point
          (if (> 0 x) (list x 0) (list 0 0))
          (if (> 0 y) (list 0 y) (list 0 0)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    SMOOTH HULL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; O(corners) algorithm to remove coincident and collinear points.
;;; Returns a valid hull point (the input point might be removed).
(define (smooth-hull hull)
  (let ((hull
         (let loop ((stop-at hull)
                    (position (dll-next hull)))
           (cond ((coincident? (dll-data position) (dll-data (dll-prev position)))
                  (remove-before! position)
                  (loop (dll-prev position) position))
                 ((orthocolinear? (dll-data (dll-prev (dll-prev position)))
                                  (dll-data (dll-prev position))
                                  (dll-data position))
                  (remove-before! position)
                  (loop (dll-prev position) position))
                 ((eq? position stop-at) stop-at)
                 (else (loop stop-at (dll-next position)))))))
    ;; Second pass: remove small gaps
    (let loop ((stop-at hull)
               (position (dll-next hull)))
      (cond ((and (not (convex-hull-vertex? (dll-next position)))
                  (not (convex-hull-vertex? (dll-next (dll-next position))))
                  (< (abs (ortho-magnitude
                           (vec- (dll-data (dll-next (dll-next position)))
                                 (dll-data (dll-next position)))))
                     MINIMUM_GAP_WIDTH))
             (let ((int (or (find-intersection
                             (dll-data position)
                             (dll-data (dll-next position))
                             (dll-data (dll-next (dll-next (dll-next position))))
                             (dll-data (dll-next (dll-next (dll-next
                                                            (dll-next position))))))
                            (find-intersection
                             (dll-data (dll-prev position))
                             (dll-data position)
                             (dll-data (dll-next (dll-next position)))
                             (dll-data (dll-next (dll-next
                                                  (dll-next position))))))))
               (remove-after! position)
               (remove-after! position)
               (insert-after! position int)
               (if (orthocolinear? (dll-data (dll-prev position))
                                   (dll-data position)
                                   (dll-data (dll-next position)))
                   (begin (set! position (dll-prev position))
                          (remove-after! position))
                   (remove-after! (dll-next position)))
               (loop (dll-prev position) position)))
            ((eq? position stop-at) stop-at)
            (else (loop stop-at (dll-next position)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;              PLACE NEW BLOCK (main entry point)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Returns coordinates where a new object should be placed,
;;; and updates the hull structure.
(define (place-new-block metro near-center dimension)
  (place-on-corner metro
                   (find-closest-point metro near-center)
                   near-center
                   dimension))

(define (place-on-corner metro point-on-hull near-center dimension)
  (let ((prevhull (dll-prev point-on-hull))
        (nexthull (dll-next point-on-hull)))
    (if (not (convex-hull-vertex? point-on-hull))
        (place-on-concave-corner metro point-on-hull near-center dimension)
        (if (> (separation-squared (dll-data nexthull) near-center)
               (separation-squared (dll-data prevhull) near-center))
            (if (convex-hull-vertex? prevhull)
                (place-on-convex-corner metro prevhull near-center dimension)
                (place-on-concave-corner metro prevhull near-center dimension))
            (if (convex-hull-vertex? nexthull)
                (place-on-convex-corner metro nexthull near-center dimension)
                (place-on-concave-corner metro nexthull near-center dimension))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    CONVEX CORNER PLACEMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (place-on-convex-corner metro point-on-hull near-center dimension)
  (let* ((prev-hull (dll-prev point-on-hull))
         (next-hull (dll-next point-on-hull))
         (next (dll-data next-hull))
         (prev (dll-data prev-hull))
         (point (dll-data point-on-hull))
         (prev-basis (outward-parallel point prev dimension))
         (next-basis (outward-parallel point next dimension)))
    (if (< (separation-squared near-center next)
           (separation-squared near-center prev))
        ;; Place on the next-side
        (begin
          (insert-after! point-on-hull (vec+ point (vec- next-basis)))
          (insert-after! point-on-hull (vec+ point (vec- next-basis) prev-basis))
          (insert-after! point-on-hull (vec+ point prev-basis))
          (set-metropolis-hull! metro (smooth-hull prev-hull))
          (upper-left-corner point (vec+ prev-basis (vec- next-basis))))
        ;; Place on the prev-side
        (begin
          (insert-after! point-on-hull (vec+ point next-basis))
          (insert-after! point-on-hull (vec+ point (vec- prev-basis) next-basis))
          (insert-after! point-on-hull (vec+ point (vec- prev-basis)))
          (set-metropolis-hull! metro (smooth-hull prev-hull))
          (upper-left-corner point (vec+ next-basis (vec- prev-basis)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                   CONCAVE CORNER PLACEMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (place-on-concave-corner metro point-on-hull near-center dimension)
  (let* ((nexthull (dll-next point-on-hull))
         (prevhull (dll-prev point-on-hull))
         (next (dll-data nexthull))
         (prev (dll-data prevhull))
         (point (dll-data point-on-hull))
         (next-basis (vec* -1 (outward-parallel point next dimension)))
         (prev-basis (vec* -1 (outward-parallel point prev dimension))))
    (if (and (or (convex-hull-vertex? nexthull)
                 (> (abs (ortho-magnitude (parallel-mask (vec- next point)
                                                         next-basis)))
                    (abs (ortho-magnitude next-basis))))
             (or (convex-hull-vertex? prevhull)
                 (> (abs (ortho-magnitude (parallel-mask (vec- prev point)
                                                         prev-basis)))
                    (abs (ortho-magnitude prev-basis)))))
        ;; Block fits into the concave gap
        (begin
          (set-dll-next! prevhull nexthull)
          (set-dll-prev! nexthull prevhull)
          (insert-after! prevhull (vec+ point next-basis))
          (insert-after! prevhull (vec+ point prev-basis next-basis))
          (insert-after! prevhull (vec+ point prev-basis))
          (set-metropolis-hull! metro (smooth-hull prevhull))
          (upper-left-corner point (vec+ next-basis prev-basis)))
        ;; Block does not fit — find intersection and recurse
        (let ((nextint
               (let loop ((hull nexthull))
                 (if (convex-hull-vertex? hull)
                     (cons (dll-next hull)
                           (find-intersection
                            (dll-data (dll-next hull))
                            (dll-data hull)
                            (dll-data (dll-prev (dll-prev hull)))
                            (dll-data (dll-prev
                                       (dll-prev (dll-prev hull))))))
                     (loop (dll-next hull)))))
              (prevint
               (let loop ((hull prevhull))
                 (if (convex-hull-vertex? hull)
                     (cons (dll-prev hull)
                           (find-intersection
                            (dll-data (dll-prev hull))
                            (dll-data hull)
                            (dll-data (dll-next (dll-next hull)))
                            (dll-data (dll-next
                                       (dll-next (dll-next hull))))))
                     (loop (dll-prev hull))))))
          (cond ((cdr prevint)
                 (let ((hull (car prevint)))
                   (remove-after! hull)
                   (remove-after! hull)
                   (remove-after! hull)
                   (insert-after! hull (cdr prevint))
                   (place-on-corner metro (dll-next hull)
                                    near-center dimension)))
                ((cdr nextint)
                 (let ((hull (car nextint)))
                   (remove-before! hull)
                   (remove-before! hull)
                   (remove-before! hull)
                   (insert-before! hull (cdr nextint))
                   (place-on-corner metro (dll-prev hull)
                                    near-center dimension)))
                (else (error "placement: malformed hull")))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                  HULL REGENERATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Segment representation for scan-based hull reconstruction.
(define (make-segment scan-coord min-coord max-coord incr)
  (vector scan-coord min-coord max-coord incr))
(define (segment-scan-coordinate x) (vector-ref x 0))
(define (segment-min-coordinate x) (vector-ref x 1))
(define (segment-max-coordinate x) (vector-ref x 2))
(define (segment-type x) (vector-ref x 3))

;;; Build segment ordering from a list of (coords . dimension) pairs.
;;; Each element must be a pair: ((x y) . (w h)).
(define (make-segment-ordering rect-list)
  (list-sort
   (lambda (x y) (< (vector-ref x 0) (vector-ref y 0)))
   (apply append
          (map (lambda (rect)
                 (let* ((c (vec+ (car rect) (vec- 1/2PLACEMENT_SPACING)))
                        (d (vec+ PLACEMENT_SPACING (cdr rect)))
                        (minx (x-coord c))
                        (maxx (+ minx (x-coord d)))
                        (miny (y-coord c))
                        (maxy (+ miny (y-coord d))))
                   (list (make-segment minx miny maxy 1)
                         (make-segment maxx miny maxy -1))))
               rect-list))))

(define (find-next-insertion x)
  (cond ((null? x) (error "placement: shouldn't happen"))
        ((> (segment-scan-coordinate (cadr x))
            (segment-scan-coordinate (car x))) x)
        (else (find-next-insertion (cdr x)))))

;;; Construct one half of the hull from an ordered segment list.
(define (construct-chain ord protect?)
  (let* ((first (car ord))
         (min-half (make-dll
                    (list (segment-scan-coordinate first)
                          (segment-min-coordinate first)) '() '()))
         (max-half (make-dll
                    (list (segment-scan-coordinate first)
                          (segment-max-coordinate first)) '() min-half)))
    (set-dll-prev! min-half max-half)
    (let loop ((ord (cdr ord))
               (scancoord (segment-scan-coordinate first))
               (min-half min-half)
               (max-half max-half))
      (if (null? ord)
          max-half
          (let* ((minpos (y-coord (dll-data min-half)))
                 (maxpos (y-coord (dll-data max-half)))
                 (this (car ord))
                 (thiscoord (segment-scan-coordinate this))
                 (thismin (segment-min-coordinate this))
                 (thismax (segment-max-coordinate this)))
            (let ((new-max-half
                   (if (> thismax maxpos)
                       (let ((corner (make-dll (list thiscoord maxpos)
                                              '() max-half))
                             (newmax (make-dll (list thiscoord thismax)
                                              '() '())))
                         (set-dll-prev! max-half corner)
                         (set-dll-prev! corner newmax)
                         (set-dll-next! newmax corner)
                         (when protect?
                           (let ((next (find-next-insertion ord)))
                             (set-cdr! next (cons (vector (+ 1 thiscoord)
                                                          (- maxpos 1)
                                                          thismax)
                                                  (cdr next)))))
                         newmax)
                       max-half))
                  (new-min-half
                   (if (< thismin minpos)
                       (let ((corner (make-dll (list thiscoord minpos)
                                              min-half '()))
                             (newmin (make-dll (list thiscoord thismin)
                                              '() '())))
                         (set-dll-next! min-half corner)
                         (set-dll-next! corner newmin)
                         (set-dll-prev! newmin corner)
                         (when protect?
                           (let ((next (find-next-insertion ord)))
                             (set-cdr! next (cons (vector (+ 1 thiscoord)
                                                          thismin
                                                          (+ minpos 1))
                                                  (cdr next)))))
                         newmin)
                       min-half)))
              (loop (cdr ord) thiscoord new-min-half new-max-half)))))))

;;; Regenerate the hull from a list of rectangle descriptors.
;;; Each element is ((x y) . (w h)).
(define (regenerate-hull metro rect-list)
  (let* ((ord (make-segment-ordering rect-list))
         (right-left (construct-chain ord #t))
         (left-right (construct-chain (reverse ord) #f)))
    ;; Reverse the left-right chain's link direction
    (let loop ((dll (dll-farthest-prev left-right)))
      (let ((next (dll-next dll)))
        (set-dll-next! dll (dll-prev dll))
        (set-dll-prev! dll next)
        (when (and next (dll? next))
          (loop next))))
    ;; Connect the two chains into a ring
    (let ((rln (dll-farthest-next right-left))
          (rlp (dll-farthest-prev right-left))
          (lrn (dll-farthest-next left-right))
          (lrp (dll-farthest-prev left-right)))
      (set-dll-next! rln lrp)
      (set-dll-prev! lrp rln)
      (set-dll-next! lrn rlp)
      (set-dll-prev! rlp lrn))
    (set-metropolis-hull! metro (smooth-hull right-left))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                  HIGH-LEVEL PLACEMENT API
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Place a new node of the given dimension near `near-center`.
;;; Returns (x y) coordinates for the new node.
;;; Creates the metropolis on first call.
;;; `metro-box` is a one-element list containing the metropolis or #f.
(define (place-widget! metro-box near-center dimension)
  (let ((dim+space (vec+ dimension PLACEMENT_SPACING)))
    (if (not (car metro-box))
        ;; First placement — create the metropolis
        (begin
          (set-car! metro-box
                    (make-metropolis PLACEMENT_INITIAL_POSITION dim+space))
          (vec+ PLACEMENT_INITIAL_POSITION 1/2PLACEMENT_SPACING))
        ;; Subsequent placements — use the hull
        (let ((coords (place-new-block (car metro-box) near-center dim+space)))
          (vec+ coords 1/2PLACEMENT_SPACING)))))
