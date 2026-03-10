;;; color.scm — RGB color representation and manipulation
;;;
;;; Ported from color.stk — removed Tk widget coupling
;;;
;;; Copyright (C) 1995, 1996 Josh MacDonald <jmacd@CS.Berkeley.EDU>
;;; Port Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                          COLORS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Colors are represented as records with r, g, b components (0-255).

(define-record-type <color>
  (make-color r g b)
  color?
  (r color-r)
  (g color-g)
  (b color-b))

;;; Convert a color to a CSS hex string: "#rrggbb"
(define (color->hex c)
  (string-append "#"
                 (dec->hex (color-r c))
                 (dec->hex (color-g c))
                 (dec->hex (color-b c))))

;;; Convert a color to a CSS rgb() string
(define (color->css c)
  (string-append "rgb("
                 (number->string (color-r c)) ","
                 (number->string (color-g c)) ","
                 (number->string (color-b c)) ")"))

;;; Convert a color to a CSS rgba() string with an alpha value
(define (color->css-alpha c alpha)
  (string-append "rgba("
                 (number->string (color-r c)) ","
                 (number->string (color-g c)) ","
                 (number->string (color-b c)) ","
                 (number->string alpha) ")"))

;;; Complement color (used for outlines, etc.)
(define (complement-color c)
  (make-color (max 0 (- (color-r c) 20))
              (max 0 (- (color-g c) 20))
              (max 0 (- (color-b c) 20))))

;;; Darken a color by 50 points
(define (darken-color c)
  (make-color (max 20 (- (color-r c) 50))
              (max 20 (- (color-g c) 50))
              (max 20 (- (color-b c) 50))))

;;; Lighten a color by 50 points
(define (lighten-color c)
  (make-color (min 255 (+ (color-r c) 50))
              (min 255 (+ (color-g c) 50))
              (min 255 (+ (color-b c) 50))))

;;; integer 0-255 → two-character hex string
(define (dec->hex n)
  (let ((hi (quotient n 16))
        (lo (remainder n 16)))
    (string-append (number->string hi 16)
                   (number->string lo 16))))

;;; two-character hex string → integer
(define (hex->dec h)
  (string->number h 16))

;;; Parse a CSS hex color string "#rrggbb" into a <color>
(define (hex->color s)
  (make-color (hex->dec (substring s 1 3))
              (hex->dec (substring s 3 5))
              (hex->dec (substring s 5 7))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                     DEFAULT PALETTE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Muted cool pastels — soft blues, greens, slate
(define color-ice-blue    (make-color 198 222 241))
(define color-seafoam     (make-color 189 224 215))
(define color-cool-sage   (make-color 200 219 199))
(define color-pale-steel  (make-color 208 213 225))
(define color-soft-teal   (make-color 183 218 224))
(define color-mist        (make-color 214 220 235))
(define color-white       (make-color 255 255 255))
(define color-black       (make-color 0 0 0))
