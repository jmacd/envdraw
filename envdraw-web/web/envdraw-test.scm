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
(define-foreign canvas-round-rect! "ctx" "roundRect"
  (ref null extern) f64 f64 f64 f64 f64 -> none)

(console-log "phase 1: FFI bindings OK")

;;; Additional app FFI bindings (same as envdraw.scm)
(define-foreign register-eval-handler "app" "registerEvalHandler"
  (ref null extern) -> none)
(define-foreign register-render-handler "app" "registerRenderHandler"
  (ref null extern) -> none)
(define-foreign register-step-handler "app" "registerStepHandler"
  (ref null extern) -> none)
(define-foreign register-continue-handler "app" "registerContinueHandler"
  (ref null extern) -> none)
(define-foreign register-toggle-step-handler "app" "registerToggleStepHandler"
  (ref null extern) -> none)
(define-foreign register-resize-handler "app" "registerResizeHandler"
  (ref null extern) -> none)
(define-foreign register-mouse-down-handler "app" "registerMouseDownHandler"
  (ref null extern) -> none)
(define-foreign register-mouse-move-handler "app" "registerMouseMoveHandler"
  (ref null extern) -> none)
(define-foreign register-mouse-up-handler "app" "registerMouseUpHandler"
  (ref null extern) -> none)

(define-foreign register-gc-handler "app" "registerGCHandler"
  (ref null extern) -> none)
(define-foreign trace-append "app" "traceAppend"
  (ref string) -> none)
(define-foreign set-result-text "app" "setResultText"
  (ref string) -> none)
(define-foreign get-canvas-context "app" "getCanvasContext"
  -> (ref null extern))
(define-foreign get-canvas-width "app" "getCanvasWidth"
  -> f64)
(define-foreign get-canvas-height "app" "getCanvasHeight"
  -> f64)
(define-foreign console-error "app" "consoleError"
  (ref string) -> none)

;;; D3 diagram graph-mutation FFI stubs
(define-foreign d3-add-frame "app" "d3AddFrame"
  (ref string) (ref string) (ref string) (ref string) -> none)
(define-foreign d3-add-procedure "app" "d3AddProcedure"
  (ref string) (ref string) (ref string) (ref string) -> none)
(define-foreign d3-add-binding "app" "d3AddBinding"
  (ref string) (ref string) (ref string) (ref string) (ref string) -> none)
(define-foreign d3-update-binding "app" "d3UpdateBinding"
  (ref string) (ref string) (ref string) (ref string) -> none)
(define-foreign d3-remove-node "app" "d3RemoveNode"
  (ref string) -> none)
(define-foreign d3-remove-edge "app" "d3RemoveEdge"
  (ref string) (ref string) -> none)
(define-foreign d3-request-render "app" "d3RequestRender"
  -> none)

(console-log "phase 1b: all app FFI OK")

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

;;; Primitives table — split into groups for debugging
(define *prims-arith*
  `((+ . ,+) (- . ,-) (* . ,*) (/ . ,/)
    (quotient . ,quotient) (remainder . ,remainder) (modulo . ,modulo)
    (abs . ,abs) (max . ,max) (min . ,min)
    (expt . ,expt) (sqrt . ,sqrt)
    (floor . ,floor) (ceiling . ,ceiling)
    (round . ,round) (truncate . ,truncate)
    (exact . ,exact) (inexact . ,inexact)
    (exact->inexact . ,inexact) (inexact->exact . ,exact)))
(console-log "prims: arith OK")

(define *prims-cmp*
  `((= . ,=) (< . ,<) (> . ,>) (<= . ,<=) (>= . ,>=)))
(console-log "prims: cmp OK")

(define *prims-pred*
  `((number? . ,number?) (integer? . ,integer?)
    (symbol? . ,symbol?) (string? . ,string?)
    (boolean? . ,boolean?) (char? . ,char?)
    (pair? . ,pair?) (null? . ,null?)
    (list? . ,list?) (vector? . ,vector?)
    (procedure? . ,procedure?)
    (eq? . ,eq?) (eqv? . ,eqv?) (equal? . ,equal?)
    (not . ,not)
    (zero? . ,zero?) (positive? . ,positive?)
    (negative? . ,negative?)
    (even? . ,even?) (odd? . ,odd?)))
(console-log "prims: pred OK")

(define *prims-list*
  `((cons . ,cons) (car . ,car) (cdr . ,cdr)
    (set-car! . ,set-car!) (set-cdr! . ,set-cdr!)
    (list . ,list) (append . ,append)
    (length . ,length) (reverse . ,reverse)
    (list-ref . ,list-ref)
    (assoc . ,assoc) (assq . ,assq) (assv . ,assv)
    (member . ,member) (memq . ,memq) (memv . ,memv)
    (cadr . ,cadr) (caddr . ,caddr)
    (caar . ,caar) (cdar . ,cdar) (cddr . ,cddr)
    (caaar . ,caaar) (caadr . ,caadr) (cadar . ,cadar)
    (cdaar . ,cdaar) (cdadr . ,cdadr) (cddar . ,cddar)))
(console-log "prims: list OK")

(define *prims-str*
  `((string-append . ,string-append)
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
    (string . ,string)))
(console-log "prims: str OK")

(define *prims-char*
  `((char->integer . ,char->integer)
    (integer->char . ,integer->char)
    (char=? . ,char=?)
    (char<? . ,char<?)))
(console-log "prims: char OK")

(define *prims-vec*
  `((make-vector . ,make-vector) (vector . ,vector)
    (vector-ref . ,vector-ref) (vector-set! . ,vector-set!)
    (vector-length . ,vector-length)
    (vector->list . ,vector->list)
    (list->vector . ,list->vector)))
(console-log "prims: vec OK")

(define *prims-io*
  `((newline . ,newline)
    (read . ,read)
    (write . ,write)
    (display . ,display)
    (user-print . ,user-print)
    (user-display . ,user-display)))
(console-log "prims: io OK")

(define *prims-ho*
  `((map . ,map) (for-each . ,for-each)
    (apply . ,apply)))
(console-log "prims: ho OK")

(define *prims-ctrl*
  `((error . ,error)))
(console-log "prims: ctrl-error OK")

(define *prims-callcc*
  `((call-with-current-continuation . ,call-with-current-continuation)
    (call/cc . ,call-with-current-continuation)))
(console-log "prims: ctrl-callcc OK")

(define *prims-values*
  `((values . ,values)
    (call-with-values . ,call-with-values)))
(console-log "prims: ctrl-values OK")

(define *primitives-table*
  (append *prims-arith* *prims-cmp* *prims-pred* *prims-list*
          *prims-str* *prims-char* *prims-vec* *prims-io*
          *prims-ho* *prims-ctrl* *prims-callcc* *prims-values*))

(define (*host-eval* var)
  (let ((entry (assq var *primitives-table*)))
    (if entry
        (cdr entry)
        (error "Unbound variable (no host binding)" var))))

(console-log "phase 13: primitives OK")

(include "../src/core/meta.scm")
(console-log "phase 14: meta OK — all includes loaded!")

;;; Test boot!
(console-log "phase 15: about to define boot!")

(define (test-boot!)
  (console-log "boot: start")
  (let* ((root (make-group-node 0 0)))
    (console-log "boot: root created")
    (let* ((obs (make-web-observer root)))
      (console-log "boot: observer created")
      (let* ((eval-fn (envdraw-init obs)))
        (console-log "boot: envdraw-init done")
        (let* ((ctx (get-canvas-context)))
          (console-log "boot: got canvas context")
          (set! *render-ctx* ctx)
          (set! *canvas-width* 800)
          (set! *canvas-height* 600)
          (console-log "boot: render state set")
          
          ;; Test procedure->external
          (register-eval-handler
           (procedure->external
            (lambda (input-string)
              (console-log "eval called")
              "ok")))
          (console-log "boot: eval handler registered")
          
          (register-render-handler
           (procedure->external
            (lambda ()
              (console-log "render called"))))
          (console-log "boot: render handler registered")
          
          (console-log "boot: ALL DONE"))))))

(console-log "phase 16: boot! defined")

(test-boot!)

(console-log "EnvDraw incremental test: ALL PHASES PASSED")
