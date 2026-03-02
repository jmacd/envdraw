;;; stacks.scm — Stack and doubly-linked list data structures
;;;
;;; Ported from stacks.stk (STklos classes → R7RS records)
;;;
;;; Copyright (C) 1995, 1996 Josh MacDonald <jmacd@CS.Berkeley.EDU>
;;; Port Copyright (C) 2026 Josh MacDonald
;;;
;;; Permission to use, copy, and/or distribute this software and its
;;; documentation for any purpose and without fee is hereby granted, provided
;;; that both the above copyright notice and this permission notice appear in
;;; all copies and derived works.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                             STACKS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-record-type <stack>
  (%make-stack items)
  stack?
  (items stack-items set-stack-items!))

(define (make-stack)
  (%make-stack '()))

(define (stack-push! s it)
  (set-stack-items! s (cons it (stack-items s))))

(define (stack-pop! s)
  (let ((items (stack-items s)))
    (if (null? items)
        (error "stack-pop!: empty stack")
        (begin
          (set-stack-items! s (cdr items))
          (car items)))))

(define (stack-empty? s)
  (null? (stack-items s)))

(define (stack-empty! s)
  (set-stack-items! s '()))

(define (stack-ref s n)
  (list-ref (stack-items s) n))

(define (stack->list s)
  (stack-items s))

(define (stack-copy s)
  (%make-stack (list-copy (stack-items s))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                        DOUBLY LINKED LISTS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-record-type <dll>
  (%make-dll data next prev)
  dll?
  (data dll-data set-dll-data!)
  (next dll-next set-dll-next!)
  (prev dll-prev set-dll-prev!))

(define (make-dll data prev next)
  (%make-dll data next prev))

(define (insert-after! dll data)
  (let* ((after (dll-next dll))
         (new (%make-dll data after dll)))
    (set-dll-next! dll new)
    (when (dll? after)
      (set-dll-prev! after new))))

(define (insert-before! dll data)
  (let* ((before (dll-prev dll))
         (new (%make-dll data dll before)))
    (when (dll? before)
      (set-dll-next! before new))
    (set-dll-prev! dll new)))

(define (remove-after! dll)
  (let ((after-after (dll-next (dll-next dll))))
    (set-dll-next! dll after-after)
    (when (dll? after-after)
      (set-dll-prev! after-after dll))))

(define (remove-before! dll)
  (let ((before-before (dll-prev (dll-prev dll))))
    (set-dll-prev! dll before-before)
    (when (dll? before-before)
      (set-dll-next! before-before dll))))

(define (make-cdll data)
  (let ((ring (%make-dll data #f #f)))
    (set-dll-next! ring ring)
    (set-dll-prev! ring ring)
    ring))

(define (dll-farthest-prev dll)
  (if (or (not (dll-prev dll)) (not (dll? (dll-prev dll))))
      dll
      (dll-farthest-prev (dll-prev dll))))

(define (dll-farthest-next dll)
  (if (or (not (dll-next dll)) (not (dll? (dll-next dll))))
      dll
      (dll-farthest-next (dll-next dll))))
