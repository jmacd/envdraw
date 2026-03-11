
;; create a node with value, right, and down
(define (make-node value right down)
  (cons (cons value down) right))

(define (node-down node) (cdar node))
(define (node-right node) (cdr node))
(define (node-value node) (caar node))
(define (node-set-right! node right) (set-cdr! node right))
(define (node-set-value! node value) (set-car! (car node) value))

(define *maxkey* 'maxkey)
(define *tailkey* 'tailkey)

(define (make-tree)
  (let* ((tail (make-node *tailkey* #t #t))
         (bottom (make-node *tailkey* #t #t))
         (head (make-node *maxkey* tail bottom)))
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
      0
      (+ 1 (tree-depth tree (node-down node)))))

(define (greater? a b)
  (cond
   ((eq? b *tailkey*) #f)
   ((eq? b *maxkey*) #f)
   (else (> a b))))

(define (insert-tree tree value)
  (node-set-value! (tree-bottom tree) value)
  (or (insert-node tree (tree-head tree) value)
      (update-tail tree)))

(define (insert-node tree node value)
  (or (insert-skip tree node value)
      (and (not (eq? (node-down node) (tree-bottom tree)))
           (insert-node tree (node-down node) value))))

(define (update-tail tree)
  (when (not (eq? (node-right (tree-head tree)) (tree-tail tree)))
    (let ((newhead (make-node *maxkey* (tree-tail tree) (tree-head tree))))
      (tree-set-head! tree newhead)))
  #t)

(define (insert-skip tree node value)
  (cond
   ((greater? value (node-value node))
    ;; skip right
    (insert-skip tree (node-right node) value))
   ((and (eq? (tree-bottom tree) (node-down node))
         (eq? (node-value node) value))
    ;; existing match
    #t)
   ((or (eq? (tree-bottom tree) (node-down node))
        (eq? (node-value node) (node-value (node-right (node-right (node-right (node-down node)))))))
    ;; full child case
    (node-set-right! node (make-node (node-value node)
                                     (node-right node)
                                     (node-right (node-right (node-down node)))))
    (node-set-value! node (node-value (node-right (node-down node))))
    #f
    )
   ;; child is not full
   (else
    #f)
   )
  )

(define t (make-tree))
(insert-tree t 20)
(insert-tree t 30)
(insert-tree t 40)
(insert-tree t 50)
(insert-tree t 60)
(insert-tree t 70)

(display (tree-depth t (tree-head t)))
(display "\n")
