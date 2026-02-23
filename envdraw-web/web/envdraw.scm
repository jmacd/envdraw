;;; envdraw.scm — Hoot entry point for EnvDraw web application
;;;
;;; This is the top-level program compiled to envdraw.wasm via:
;;;   guild compile-wasm -L web -L . -o web/envdraw.wasm web/envdraw.scm
;;;
;;; It replaces src/main.scm for the Wasm build, providing:
;;;   - All FFI bindings (Canvas2D, DOM, app callbacks)
;;;   - Primitives table (replaces Guile's interaction-environment)
;;;   - R7RS compatibility shims
;;;   - Source inclusion and initialization
;;;
;;; Copyright (C) 2026 Josh MacDonald

(import (scheme base)
        (scheme read)
        (scheme write)
        (scheme inexact)
        (scheme cxr)
        (scheme case-lambda)
        (hoot ffi)
        (only (hoot lists) sort))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                 R7RS COMPATIBILITY SHIMS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; R5RS aliases used by some source files
(define inexact->exact exact)
(define exact->inexact inexact)

;;; list-copy is in (scheme base) — no polyfill needed
;;; list-sort: Guile built-in → alias to Hoot's sort
(define list-sort sort)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                 FFI : CANVAS 2D CONTEXT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                 FFI : APP (JS → Scheme callbacks)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Register Scheme procedures for JS to call back
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

;;; Output functions — Scheme calls JS to update DOM
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

(define-foreign console-log "app" "consoleLog"
  (ref string) -> none)

(define-foreign console-error "app" "consoleError"
  (ref string) -> none)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                 INCLUDE SOURCE FILES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; NB: Includes MUST come before the primitives table because
;;; user-print / user-display (defined in web-observer.scm) are
;;; referenced via unquote in the quasiquoted alist.  Evaluating
;;; those unquotes before the definitions exist produces an
;;; uninitialised Wasm table index → "index out of bounds".

;;; Core data structures
(include "../src/core/stacks.scm")

;;; Model layer
(include "../src/model/math.scm")
(include "../src/model/color.scm")

;;; Canvas FFI — already defined above via define-foreign (skip stubs)

;;; Scene graph
(include "../src/model/scene-graph.scm")

;;; Profiles — cons-cell sizing
(include "../src/model/profiles.scm")

;;; Placement — convex-hull layout
(include "../src/model/placement.scm")

;;; Pointer routing
(include "../src/model/pointers.scm")

;;; Renderer
(include "../src/render/renderer.scm")

;;; Observer interface
(include "../src/core/eval-observer.scm")

;;; Web observer
(include "../src/ui/web-observer.scm")

;;; Environment manipulation
(include "../src/core/environments.scm")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                 PRIMITIVES TABLE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Replaces (eval var (interaction-environment)) for the Wasm build.
;;; The meta-evaluator calls (*host-eval* var) to resolve primitive
;;; procedures like +, cons, car, etc.
;;;
;;; Must come AFTER web-observer (defines user-print, user-display)
;;; and BEFORE meta.scm (which references *host-eval*).
;;;
;;; NOTE: Split into small quasiquoted lists and joined with append.
;;; Hoot 0.6.1 crashes at runtime with "index out of bounds" when a
;;; single quasiquote expression contains ~80+ unquotes.

(define *prims-arith*
  `((+ . ,+) (- . ,-) (* . ,*) (/ . ,/)
    (quotient . ,quotient) (remainder . ,remainder) (modulo . ,modulo)
    (abs . ,abs) (max . ,max) (min . ,min)
    (expt . ,expt) (sqrt . ,sqrt)
    (floor . ,floor) (ceiling . ,ceiling)
    (round . ,round) (truncate . ,truncate)
    (exact . ,exact) (inexact . ,inexact)
    (exact->inexact . ,inexact) (inexact->exact . ,exact)))

(define *prims-cmp*
  `((= . ,=) (< . ,<) (> . ,>) (<= . ,<=) (>= . ,>=)))

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

(define *prims-char*
  `((char->integer . ,char->integer)
    (integer->char . ,integer->char)
    (char=? . ,char=?)
    (char<? . ,char<?)))

(define *prims-vec*
  `((make-vector . ,make-vector) (vector . ,vector)
    (vector-ref . ,vector-ref) (vector-set! . ,vector-set!)
    (vector-length . ,vector-length)
    (vector->list . ,vector->list)
    (list->vector . ,list->vector)))

(define *prims-io*
  `((newline . ,newline)
    (read . ,read)
    (write . ,write)
    (display . ,display)
    (user-print . ,user-print)
    (user-display . ,user-display)))

(define *prims-ho*
  `((map . ,map) (for-each . ,for-each)
    (apply . ,apply)))

(define *prims-ctrl*
  `((error . ,error)
    (call-with-current-continuation . ,call-with-current-continuation)
    (call/cc . ,call-with-current-continuation)
    (values . ,values)
    (call-with-values . ,call-with-values)))

(define *primitives-table*
  (append *prims-arith* *prims-cmp* *prims-pred* *prims-list*
          *prims-str* *prims-char* *prims-vec* *prims-io*
          *prims-ho* *prims-ctrl*))

(define (*host-eval* var)
  (let ((entry (assq var *primitives-table*)))
    (if entry
        (cdr entry)
        (error "Unbound variable (no host binding)" var))))

(console-log "envdraw: all includes loaded, primitives ready")

;;; Metacircular evaluator — must come AFTER *host-eval* is defined
;;; since lookup-variable-value calls (*host-eval* var)
(include "../src/core/meta.scm")

(console-log "envdraw: meta.scm loaded")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                 INITIALIZATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (boot!)
  ;; Create scene graph and observer
  (let* ((root (make-group-node 0 0))
         (obs (make-web-observer root))
         (eval-fn (envdraw-init obs))
         (ctx (get-canvas-context)))

    ;; Set up rendering state — override the thunk so each
    ;; render gets a fresh context with current pan/zoom transforms.
    (set! *get-fresh-context* (lambda () (get-canvas-context)))
    (set! *render-ctx* ctx)
    (set! *canvas-width* (exact (floor (get-canvas-width))))
    (set! *canvas-height* (exact (floor (get-canvas-height))))

    ;; Set trace callback to push lines to the DOM trace panel
    (set! *trace-callback*
          (lambda (s) (trace-append s)))

    ;; ── Register callbacks for JS ──

    ;; Eval: called when user presses Enter in the REPL
    (register-eval-handler
     (procedure->external
      (lambda (input-string)
        (guard (exn
                (#t
                 (let ((msg (if (error-object? exn)
                                (string-append "Error: "
                                               (error-object-message exn))
                                "Error: unknown exception")))
                   (trace-append msg)
                   (console-error msg)
                   msg)))
          (let ((result (eval-fn input-string)))
            (set-result-text result)
            result)))))

    ;; Render: called on resize or when JS needs a repaint
    (register-render-handler
     (procedure->external
      (lambda ()
        (set! *canvas-width* (exact (floor (get-canvas-width))))
        (set! *canvas-height* (exact (floor (get-canvas-height))))
        (request-render!))))

    ;; Step: advance one evaluation step
    (register-step-handler
     (procedure->external
      (lambda () (env-step))))

    ;; Continue: run to completion
    (register-continue-handler
     (procedure->external
      (lambda () (env-continue))))

    ;; Toggle stepping mode
    (register-toggle-step-handler
     (procedure->external
      (lambda () (env-toggle-use-step))))

    ;; Resize: update canvas dimensions and re-render
    (register-resize-handler
     (procedure->external
      (lambda ()
        (set! *render-ctx* (get-canvas-context))
        (set! *canvas-width* (exact (floor (get-canvas-width))))
        (set! *canvas-height* (exact (floor (get-canvas-height))))
        (request-render!))))

    ;; Mouse interaction: hit-test and drag scene-graph nodes
    (register-mouse-down-handler
     (procedure->external
      (lambda (x y)
        (handle-mouse-down! x y))))

    (register-mouse-move-handler
     (procedure->external
      (lambda (x y)
        (handle-mouse-move! x y))))

    (register-mouse-up-handler
     (procedure->external
      (lambda (x y)
        (handle-mouse-up! x y))))

    ;; GC: garbage collect unreachable nodes
    (register-gc-handler
     (procedure->external
      (lambda () (handle-gc!))))

    ;; Initial render — show the GLOBAL ENVIRONMENT frame
    (request-render!)

    (console-log "EnvDraw: ready.")))

;; Run!
(boot!)
