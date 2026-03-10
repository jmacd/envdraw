
;; create a node with value, right, and down
(define (make-node value right down)
  (cons (cons value down) right))

(define (node-down node) (cdar node))
(define (node-right node) (cdr node))
(define (node-value node) (caar node))
(define (node-set-right! node right) (set-cdr! node right))
(define (node-set-value! node value) (set-car! (car node) value))

(define (make-tree)
  (let* ((tail (make-node #t #t #t))
         (bottom (make-node #t #t #t))
         (head (make-node #t tail bottom)))
    (set-cdr! tail tail)
    (set-cdr! bottom bottom)
    (set-cdr! (car bottom) bottom)
    (list head tail bottom)))

(define (tree-head tree) (car tree))
(define (tree-tail tree) (cadr tree))
(define (tree-bottom tree) (caddr tree))
(define (tree-set-head! tree node) (set-car! tree node))

(define (tree-depth tree node)
  (if (eq? (node-down node) (tree-bottom tree))
      1
      (+ 1 (tree-depth tree (node-down node)))))

(define (greater? a b)
  (and (not (boolean? b)) (> a b)))

(define (insert-tree tree value)
  (node-set-value! (tree-bottom tree) value)
  (or (insert-node tree (tree-head tree) value)
      (update-tail tree)))

(define (insert-node tree node value)
  (display "INSERT NODE\n")
  (or (insert-skip tree node value)
      (and (not (eq? node (tree-bottom tree)))
           (insert-node tree (node-down node) value))))

(define (update-tail tree)
  (or (not (eq? (node-right (tree-head tree)) (tree-tail tree)))
      (let ((newhead (make-node #t (tree-tail tree) (tree-head tree))))
        (display "NEW HEAD\n")
        (tree-set-head! tree newhead)
        #t
        )))

(define (insert-skip tree node value)
  (cond
   ((greater? value (node-value node))
    ;; skip right
    (display "SKIP RIGHT\n")
    (insert-skip tree (node-right node) value))
   ((and (eq? (tree-bottom tree) (node-down node))
         (eq? (node-value node) value))
    (display "EXISTING\n")
    ;; existing match
    #t)
   ((or (eq? (tree-bottom tree) (node-down node))
        (eq? (node-value node) (node-value (node-right (node-right (node-right (node-down node)))))))
    ;; full child case
    (display "BOTTOM OR FULL CHILD\n")
    (node-set-right! node (make-node (node-value node)
                                     (node-right node)
                                     (node-right (node-right (node-down node)))))
    (node-set-value! node (node-value (node-right (node-down node))))
    #f
    )
   ;; child is not full
   (else

    (display "NOT FULL\n")
    #f)
   )
  )

(define t (make-tree))
(display "ONE\n")
(insert-tree t 20)
;(display "TWO\n")
;(insert-tree t 30)
;(display "THREE\n")
;(insert-tree t 40)

;(insert-tree t 50)
;(insert-tree t 60)
;(insert-tree t 70)
(display (tree-depth t (tree-head t)))

