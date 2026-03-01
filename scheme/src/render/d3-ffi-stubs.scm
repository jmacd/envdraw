;;; d3-ffi-stubs.scm — No-op stubs for D3 FFI functions (native testing)
;;;
;;; In the Wasm build, these are define-foreign bindings that call
;;; into JavaScript.  For native Guile testing, they are no-ops that
;;; optionally log to stdout for debugging.

(define (d3-add-frame id name parent-id color)
  ;; (format #t "[d3-stub] addFrame ~a ~a~%" id name)
  (values))

(define (d3-add-procedure id lambda-text frame-id color)
  ;; (format #t "[d3-stub] addProcedure ~a ~a~%" id lambda-text)
  (values))

(define (d3-add-binding frame-id var-name value value-type proc-id)
  ;; (format #t "[d3-stub] addBinding ~a ~a ~a~%" frame-id var-name value)
  (values))

(define (d3-update-binding frame-id var-name new-value value-type)
  ;; (format #t "[d3-stub] updateBinding ~a ~a ~a~%" frame-id var-name new-value)
  (values))

(define (d3-remove-node id)
  ;; (format #t "[d3-stub] removeNode ~a~%" id)
  (values))

(define (d3-remove-edge from-id to-id)
  ;; (format #t "[d3-stub] removeEdge ~a ~a~%" from-id to-id)
  (values))

(define (d3-request-render)
  ;; (format #t "[d3-stub] requestRender~%")
  (values))
