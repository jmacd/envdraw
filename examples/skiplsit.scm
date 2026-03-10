
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

(define (less? a b)
  (or (boolean? b) (< a b)))

(define (insert-tree tree value)
  (or (insert-node tree (tree-head tree) value)
      (update-tail tree)))

(define (insert-node tree node value)
  (or (insert-skip tree node value)
      (insert-node tree (node-down node) value)))

(define (update-tail tree)
  (or (not (= (node-right (tree-head tree)) (tree-tail tree)))
      (let ((newhead (make-node #t (tree-tail tree) (tree-head tree))))
        (tree-set-head! tree newhead)
        #t
        )))

(define (insert-skip tree node value)
  (cond
   ((not (less? value (node-value node)))
    ;; skip right
    (insert-skip tree (node-right node) value))
   ((and (= (tree-bottom tree) (node-down node))
         (= (node-value node) value))
    ;; existing match
    #t)
   ((or (= (tree-bottom tree) (node-down node))
        (= (node-value node) (node-right (node-right (node-right (node-down node))))))
    ;; full child case
    (node-set-right! node (make-node (node-value node)
                                     (node-right node)
                                     (node-right (node-right (node-down node)))))
    (node-set-value! node (node-value (node-right (node-down node))))
    #f
    )
   ;; child is not full
   (else #f)
   )
  )
