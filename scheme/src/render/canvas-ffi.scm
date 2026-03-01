;;; canvas-ffi.scm — Hoot FFI bindings to Canvas2D API
;;;
;;; These define-foreign declarations import JavaScript functions
;;; from the host environment (boot.js).
;;;
;;; When running under Guile for testing, these are replaced with
;;; stubs.  The actual FFI is only active in the Wasm build.
;;;
;;; Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    CANVAS FFI (Hoot target)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; NOTE: These define-foreign forms are Hoot-specific syntax:
;;;
;;;   (define-foreign name "module" "import" param-types ... -> return-type)
;;;
;;; For native Guile testing, we provide stub implementations below.
;;; When building for Wasm, replace this with the define-foreign forms.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    STUB IMPLEMENTATIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Canvas context record for testing outside the browser.
;;; Accumulates draw commands into a log so tests can inspect them.

(define-record-type <stub-ctx>
  (make-stub-ctx log)
  stub-ctx?
  (log stub-ctx-log set-stub-ctx-log!))

(define (stub-ctx-push! ctx . args)
  (set-stub-ctx-log! ctx (cons args (stub-ctx-log ctx))))

(define (make-test-canvas-context)
  (make-stub-ctx '()))

;;; Stubs — each just logs the call

(define (canvas-set-fill-style! ctx style)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'set-fill-style style)
      #f))

(define (canvas-set-stroke-style! ctx style)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'set-stroke-style style)
      #f))

(define (canvas-set-line-width! ctx w)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'set-line-width w)
      #f))

(define (canvas-fill-rect! ctx x y w h)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'fill-rect x y w h)
      #f))

(define (canvas-stroke-rect! ctx x y w h)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'stroke-rect x y w h)
      #f))

(define (canvas-clear-rect! ctx x y w h)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'clear-rect x y w h)
      #f))

(define (canvas-begin-path! ctx)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'begin-path)
      #f))

(define (canvas-close-path! ctx)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'close-path)
      #f))

(define (canvas-move-to! ctx x y)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'move-to x y)
      #f))

(define (canvas-line-to! ctx x y)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'line-to x y)
      #f))

(define (canvas-arc! ctx x y r start-angle end-angle)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'arc x y r start-angle end-angle)
      #f))

(define (canvas-ellipse! ctx x y rx ry rot start end)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'ellipse x y rx ry rot start end)
      #f))

(define (canvas-stroke! ctx)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'stroke)
      #f))

(define (canvas-fill! ctx)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'fill)
      #f))

(define (canvas-fill-text! ctx text x y)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'fill-text text x y)
      #f))

(define (canvas-set-font! ctx font)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'set-font font)
      #f))

(define (canvas-set-text-align! ctx align)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'set-text-align align)
      #f))

(define (canvas-set-text-baseline! ctx baseline)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'set-text-baseline baseline)
      #f))

(define (canvas-measure-text-width ctx text)
  (if (stub-ctx? ctx)
      (* (string-length text) 8.0)  ; rough estimate for testing
      0.0))

(define (canvas-save! ctx)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'save)
      #f))

(define (canvas-restore! ctx)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'restore)
      #f))

(define (canvas-translate! ctx x y)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'translate x y)
      #f))

(define (canvas-scale! ctx sx sy)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'scale sx sy)
      #f))

(define (canvas-set-global-alpha! ctx a)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'set-global-alpha a)
      #f))

(define (canvas-set-line-dash! ctx seg1 seg2)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'set-line-dash seg1 seg2)
      #f))

(define (canvas-clear-line-dash! ctx)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'clear-line-dash)
      #f))

(define (canvas-round-rect! ctx x y w h r)
  (if (stub-ctx? ctx) (stub-ctx-push! ctx 'round-rect x y w h r)
      #f))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;          Hoot define-foreign forms (for Wasm build)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; When building with Hoot, the stubs above should be replaced with:
;;;
;;; (define-foreign canvas-set-fill-style! "ctx" "setFillStyle"
;;;   (ref null extern) (ref string) -> none)
;;;
;;; (define-foreign canvas-fill-rect! "ctx" "fillRect"
;;;   (ref null extern) f64 f64 f64 f64 -> none)
;;;
;;; ... etc. for each function.
;;;
;;; The stub and FFI versions share the same procedure names so the
;;; rest of the code doesn't change between targets.
