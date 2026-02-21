;;; math.scm — Vector and list arithmetic
;;;
;;; Ported from math.stk (STklos generics → explicit dispatch)
;;;
;;; The original overloaded +, -, * globally using define-generic/
;;; define-method.  Hoot/R7RS doesn't support GOOPS, so we use
;;; explicit vec+ / vec- / vec* names, keeping standard arithmetic
;;; unmodified.
;;;
;;; Copyright (C) 1995, 1996 Josh MacDonald <jmacd@CS.Berkeley.EDU>
;;; Port Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                          VECTOR MATH
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; vec+ : add numbers, vectors, or lists element-wise
;;; Supports variadic calls: (vec+ a b c ...)
(define (vec+ a . rest)
  (if (null? rest)
      a  ; identity
      (let ((b (car rest))
            (more (cdr rest)))
        (let ((result (vec2+ a b)))
          (if (null? more)
              result
              (apply vec+ result more))))))

(define (vec2+ a b)
  (cond
   ((and (number? a) (number? b))
    (+ a b))
   ((and (vector? a) (vector? b))
    (let ((len (vector-length a)))
      (let ((v (make-vector len)))
        (let loop ((i 0))
          (if (= i len)
              v
              (begin
                (vector-set! v i (+ (vector-ref a i) (vector-ref b i)))
                (loop (+ i 1))))))))
   ((and (pair? a) (pair? b))
    (map vec2+ a b))
   (else
    (error "vec+: incompatible types" a b))))

;;; vec- : subtract numbers, vectors, or lists element-wise
;;; With one argument, negates.
(define (vec- a . rest)
  (if (null? rest)
      (vec-negate a)
      (let ((b (car rest))
            (more (cdr rest)))
        (let ((result (vec2- a b)))
          (if (null? more)
              result
              (apply vec- result more))))))

(define (vec-negate a)
  (cond
   ((number? a) (- a))
   ((vector? a)
    (let* ((len (vector-length a))
           (v (make-vector len)))
      (let loop ((i 0))
        (if (= i len)
            v
            (begin
              (vector-set! v i (- (vector-ref a i)))
              (loop (+ i 1)))))))
   ((pair? a) (map vec-negate a))
   (else (error "vec-negate: unsupported type" a))))

(define (vec2- a b)
  (cond
   ((and (number? a) (number? b))
    (- a b))
   ((and (vector? a) (vector? b))
    (let ((len (vector-length a)))
      (let ((v (make-vector len)))
        (let loop ((i 0))
          (if (= i len)
              v
              (begin
                (vector-set! v i (- (vector-ref a i) (vector-ref b i)))
                (loop (+ i 1))))))))
   ((and (pair? a) (pair? b))
    (map vec2- a b))
   (else
    (error "vec-: incompatible types" a b))))

;;; vec* : scalar multiplication for numbers, vectors, and lists
;;; (vec* 3 #(1 2 3)) → #(3 6 9)
;;; (vec* 3 '(1 2 3)) → '(3 6 9)
;;; (vec* 2 3) → 6
(define (vec* a . rest)
  (if (null? rest)
      a
      (let ((b (car rest))
            (more (cdr rest)))
        (let ((result (vec2* a b)))
          (if (null? more)
              result
              (apply vec* result more))))))

(define (vec2* a b)
  (cond
   ((and (number? a) (number? b))
    (* a b))
   ((and (number? a) (vector? b))
    (let* ((len (vector-length b))
           (v (make-vector len)))
      (let loop ((i 0))
        (if (= i len)
            v
            (begin
              (vector-set! v i (* a (vector-ref b i)))
              (loop (+ i 1)))))))
   ((and (number? a) (pair? b))
    (map (lambda (x) (* a x)) b))
   ;; commutative: (vec* vec num) = (vec* num vec)
   ((and (vector? a) (number? b))
    (vec2* b a))
   ((and (pair? a) (number? b))
    (vec2* b a))
   (else
    (error "vec*: incompatible types" a b))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                        POINT HELPERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Points are represented as 2-element lists: (x y)
;;; This matches the original "coords" representation.

(define (make-point x y) (list x y))
(define (point-x p) (car p))
(define (point-y p) (cadr p))

(define (point+ a b)
  (make-point (+ (point-x a) (point-x b))
              (+ (point-y a) (point-y b))))

(define (point- a b)
  (make-point (- (point-x a) (point-x b))
              (- (point-y a) (point-y b))))

(define (point-scale k p)
  (make-point (* k (point-x p))
              (* k (point-y p))))

(define (point-distance a b)
  (let ((dx (- (point-x a) (point-x b)))
        (dy (- (point-y a) (point-y b))))
    (sqrt (+ (* dx dx) (* dy dy)))))
