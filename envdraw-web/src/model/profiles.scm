;;; profiles.scm — Size profiles for cons-cell layout
;;;
;;; Ported from view-profiles.stk — computes the spatial layout
;;; of cons-cell trees.  A "profile" is a 5-element list describing
;;; the bounding box and child positions:
;;;
;;;   (xsize ysize xpos carpos cdrpos)
;;;
;;; where:
;;;   xsize   — total width of the structure
;;;   ysize   — total height
;;;   xpos    — x displacement of the cell within the area
;;;   carpos  — (dx dy) offset from cell origin to car subtree
;;;   cdrpos  — (dx dy) offset from cell origin to cdr subtree
;;;
;;; Copyright (C) 1995, 1996 Josh MacDonald <jmacd@CS.Berkeley.EDU>
;;; Port Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    PROFILE ACCESSORS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (profile-xsize prof) (list-ref prof 0))
(define (profile-ysize prof) (list-ref prof 1))
(define (profile-xpos  prof) (list-ref prof 2))
(define (profile-carpos prof) (list-ref prof 3))
(define (profile-cdrpos prof) (list-ref prof 4))

(define ZERO-PROFILE (list 0 0 0 (list 0 0) (list 0 0)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    CELL SIZE CONSTANTS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define SCALE 30)
(define CELL_SIZE 30)

;; Derived constants — recalculated if CELL_SIZE changes
(define CELL_X   (list CELL_SIZE 0))        ; basis vector x
(define CELL_Y   (list 0 CELL_SIZE))        ; basis vector y
(define CAR_OFFSET  (vec* -1 CELL_X))       ; offset of car half-rect
(define CDR_OFFSET  (list 0 0))             ; offset of cdr half-rect

;; Pointer offsets from cell origin to arrow head positions
(define CDRP_OFFSET
  (vec* 0.5 (list CELL_SIZE CELL_SIZE)))

(define CARP_OFFSET
  (vec+ (vec* -0.5 CELL_X) (vec* 0.5 CELL_Y)))

;; Corrections applied at pointer destinations
(define CARP_TOP_CORR  (vec* -1 CARP_OFFSET))
(define CARP_SIDE_CORR (vec* -0.5 CELL_Y))
(define CDRP_TOP_CORR  (vec* -1 CDRP_OFFSET))
(define CDRP_SIDE_CORR (vec* -1.5 CELL_X))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                   PROCEDURE / ENV CONSTANTS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define PROCEDURE_DIAMETER 30)
(define PROCEDURE_RADIUS   (* 0.5 PROCEDURE_DIAMETER))
(define BENT_POINTER_OFFSET (* 0.5 PROCEDURE_DIAMETER))
(define POINTER_WIDTH 2)
(define GCD_POINTER_WIDTH 1)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                  ADD PROFILES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Combine car and cdr profiles.  `istree?` controls whether children
;;; are laid out side-by-side (#t, tree display) or linearly (#f,
;;; normal list display).

(define (add-profiles carprof cdrprof istree?)
  (let ((DEFAULT_LENGTH (* 2 SCALE))
        (DEFAULT_SPACING SCALE)
        (carwidth  (profile-xsize carprof))
        (carheight (profile-ysize carprof))
        (cdrwidth  (profile-xsize cdrprof))
        (cdrheight (profile-ysize cdrprof))
        (caroffset (profile-xpos  carprof))
        (cdroffset (profile-xpos  cdrprof)))
    (if istree?
        ;; Tree layout: children side by side below the cell
        (let ((position (max DEFAULT_LENGTH carwidth)))
          (list (+ DEFAULT_SPACING
                   (max (* 2 DEFAULT_LENGTH) (+ carwidth cdrwidth)))
                (+ DEFAULT_LENGTH (max carheight cdrheight))
                (+ position (* 0.5 DEFAULT_SPACING))
                (list (- caroffset position) DEFAULT_LENGTH)
                (list (max cdroffset DEFAULT_LENGTH) DEFAULT_LENGTH)))
        ;; Normal layout: cdr extends to the right, car below
        (let ((offsetcar? (and (>= (- carwidth caroffset)
                                   (* DEFAULT_LENGTH 2))
                               (<= DEFAULT_LENGTH cdrheight))))
          (list (+ DEFAULT_LENGTH DEFAULT_SPACING cdrwidth caroffset)
                (if offsetcar?
                    (+ carheight cdrheight)
                    (max cdrheight (+ DEFAULT_LENGTH carheight)))
                caroffset
                (list 0 (if offsetcar?
                            cdrheight
                            DEFAULT_LENGTH))
                (list (+ DEFAULT_LENGTH DEFAULT_SPACING cdroffset) 0))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;              ATOM OFFSET (for positioning atom children)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (atom-offset display-type child-type)
  ;; Returns the (dx dy) offset for positioning an atom child of a cell.
  ;; display-type is #t (tree) or #f (list).
  ;; child-type is 'car or 'cdr.
  (if display-type
      ;; tree layout
      (if (eq? child-type 'car)
          (list (- CELL_SIZE) CELL_SIZE)
          (list CELL_SIZE CELL_SIZE))
      ;; list layout
      (if (eq? child-type 'car)
          (list (- CELL_SIZE) CELL_SIZE)
          (list CELL_SIZE 0))))
