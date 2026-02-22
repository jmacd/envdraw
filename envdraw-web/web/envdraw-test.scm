;;; Incremental test — add includes one at a time to find crash
(import (scheme base)
        (scheme read)
        (scheme write)
        (scheme inexact)
        (scheme cxr)
        (scheme case-lambda)
        (hoot ffi)
        (only (hoot lists) sort))

;;; R7RS shims
(define inexact->exact exact)
(define exact->inexact inexact)
(define list-sort sort)

;;; Minimal FFI
(define-foreign console-log "app" "consoleLog"
  (ref string) -> none)

;;; Canvas FFI stubs — needed by renderer but we won't call them
(define-foreign canvas-set-fill-style! "ctx" "setFillStyle"
  (ref null extern) (ref string) -> none)
(define-foreign canvas-set-stroke-style! "ctx" "setStrokeStyle"
  (ref null extern) (ref string) -> none)
(define-foreign canvas-set-line-width! "ctx" "setLineWidth"
  (ref null extern) f64 -> none)
(define-foreign canvas-fill-rect! "ctx" "fillRect"
  (ref null extern) f64 f64 f64 f64 -> none)
(define-foreign canvas-stroke-rect! "ctx" "strokeRect"
  (ref null extern) f64 f64 f64 f64 -> none)
(define-foreign canvas-clear-rect! "ctx" "clearRect"
  (ref null extern) f64 f64 f64 f64 -> none)
(define-foreign canvas-begin-path! "ctx" "beginPath"
  (ref null extern) -> none)
(define-foreign canvas-close-path! "ctx" "closePath"
  (ref null extern) -> none)
(define-foreign canvas-move-to! "ctx" "moveTo"
  (ref null extern) f64 f64 -> none)
(define-foreign canvas-line-to! "ctx" "lineTo"
  (ref null extern) f64 f64 -> none)
(define-foreign canvas-arc! "ctx" "arc"
  (ref null extern) f64 f64 f64 f64 f64 -> none)
(define-foreign canvas-ellipse! "ctx" "ellipse"
  (ref null extern) f64 f64 f64 f64 f64 f64 f64 -> none)
(define-foreign canvas-stroke! "ctx" "stroke"
  (ref null extern) -> none)
(define-foreign canvas-fill! "ctx" "fill"
  (ref null extern) -> none)
(define-foreign canvas-fill-text! "ctx" "fillText"
  (ref null extern) (ref string) f64 f64 -> none)
(define-foreign canvas-set-font! "ctx" "setFont"
  (ref null extern) (ref string) -> none)
(define-foreign canvas-set-text-align! "ctx" "setTextAlign"
  (ref null extern) (ref string) -> none)
(define-foreign canvas-set-text-baseline! "ctx" "setTextBaseline"
  (ref null extern) (ref string) -> none)
(define-foreign canvas-measure-text-width "ctx" "measureTextWidth"
  (ref null extern) (ref string) -> f64)
(define-foreign canvas-save! "ctx" "save"
  (ref null extern) -> none)
(define-foreign canvas-restore! "ctx" "restore"
  (ref null extern) -> none)
(define-foreign canvas-translate! "ctx" "translate"
  (ref null extern) f64 f64 -> none)
(define-foreign canvas-scale! "ctx" "scale"
  (ref null extern) f64 f64 -> none)
(define-foreign canvas-set-global-alpha! "ctx" "setGlobalAlpha"
  (ref null extern) f64 -> none)
(define-foreign canvas-set-line-dash! "ctx" "setLineDash"
  (ref null extern) f64 f64 -> none)
(define-foreign canvas-clear-line-dash! "ctx" "clearLineDash"
  (ref null extern) -> none)

(console-log "phase 1: FFI bindings OK")

;;; Include model files one by one
(include "../src/core/stacks.scm")
(console-log "phase 2: stacks OK")

(include "../src/model/math.scm")
(console-log "phase 3: math OK")

(include "../src/model/color.scm")
(console-log "phase 4: color OK")

(include "../src/model/scene-graph.scm")
(console-log "phase 5: scene-graph OK")

(include "../src/model/profiles.scm")
(console-log "phase 6: profiles OK")

(include "../src/model/placement.scm")
(console-log "phase 7: placement OK")

(include "../src/model/pointers.scm")
(console-log "phase 8: pointers OK")

(include "../src/render/renderer.scm")
(console-log "phase 9: renderer OK")

(include "../src/core/eval-observer.scm")
(console-log "phase 10: eval-observer OK")

(include "../src/ui/web-observer.scm")
(console-log "phase 11: web-observer OK")

(include "../src/core/environments.scm")
(console-log "phase 12: environments OK")

;;; Primitives table
(define *primitives-table*
  `((+ . ,+) (- . ,-) (* . ,*) (/ . ,/)
    (quotient . ,quotient) (remainder . ,remainder) (modulo . ,modulo)
    (abs . ,abs) (max . ,max) (min . ,min)
    (expt . ,expt) (sqrt . ,sqrt)
    (floor . ,floor) (ceiling . ,ceiling)
    (round . ,round) (truncate . ,truncate)
    (exact . ,exact) (inexact . ,inexact)
    (exact->inexact . ,inexact) (inexact->exact . ,exact)
    (= . ,=) (< . ,<) (> . ,>) (<= . ,<=) (>= . ,>=)
    (number? . ,number?) (integer? . ,integer?)
    (symbol? . ,symbol?) (string? . ,string?)
    (boolean? . ,boolean?) (char? . ,char?)
    (pair? . ,pair?) (null? . ,null?)
    (list? . ,list?) (vector? . ,vector?)
    (procedure? . ,procedure?)
    (eq? . ,eq?) (eqv? . ,eqv?) (equal? . ,equal?)
    (not . ,not)
    (zero? . ,zero?) (positive? . ,positive?)
    (negative? . ,negative?)
    (even? . ,even?) (odd? . ,odd?)
    (cons . ,cons) (car . ,car) (cdr . ,cdr)
    (set-car! . ,set-car!) (set-cdr! . ,set-cdr!)
    (list . ,list) (append . ,append)
    (length . ,length) (reverse . ,reverse)
    (list-ref . ,list-ref)
    (assoc . ,assoc) (assq . ,assq) (assv . ,assv)
    (member . ,member) (memq . ,memq) (memv . ,memv)
    (cadr . ,cadr) (caddr . ,caddr)
    (caar . ,caar) (cdar . ,cdar) (cddr . ,cddr)
    (caaar . ,caaar) (caadr . ,caadr) (cadar . ,cadar)
    (cdaar . ,cdaar) (cdadr . ,cdadr) (cddar . ,cddar)
    (string-append . ,string-append)
    (string-length . ,string-length)
    (string-ref . ,string-ref)
    (substring . ,substring)
    (string=? . ,string=?)
    (string<? . ,string<?)
    (string>? . ,string>?)
    (number->string . ,number->string)
    (string->number . ,string->number)
    (symbol->string . ,symbol->string)
    (string->symbol . ,string->symbol)
    (string->list . ,string->list)
    (list->string . ,list->string)
    (string . ,string)
    (char->integer . ,char->integer)
    (integer->char . ,integer->char)
    (char=? . ,char=?)
    (char<? . ,char<?)
    (make-vector . ,make-vector) (vector . ,vector)
    (vector-ref . ,vector-ref) (vector-set! . ,vector-set!)
    (vector-length . ,vector-length)
    (vector->list . ,vector->list)
    (list->vector . ,list->vector)
    (newline . ,newline)
    (read . ,read)
    (write . ,write)
    (display . ,display)
    (map . ,map) (for-each . ,for-each)
    (apply . ,apply)
    (error . ,error)
    (call-with-current-continuation . ,call-with-current-continuation)
    (call/cc . ,call-with-current-continuation)
    (values . ,values)
    (call-with-values . ,call-with-values)))

(define (*host-eval* var)
  (let ((entry (assq var *primitives-table*)))
    (if entry
        (cdr entry)
        (error "Unbound variable (no host binding)" var))))

(console-log "phase 13: primitives OK")

(include "../src/core/meta.scm")
(console-log "phase 14: meta OK — all includes loaded!")

(console-log "EnvDraw incremental test: ALL PHASES PASSED")
