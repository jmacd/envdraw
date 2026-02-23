cd /Volumes/sourcecode/src/EnvDraw/envdraw-web/web
python3 -m http.server 8088


(define x 42)
(+ x 10)

(define (make-counter) (let ((n 0)) (lambda () (set! n (+ n 1)) n)))
(define c (make-counter))
(c)
