;;; main.scm — EnvDraw entry point
;;;
;;; This file is the top-level module that loads all components
;;; and initializes the application.
;;;
;;; For native Guile testing (run from envdraw-web/):
;;;   guile src/main.scm
;;;
;;; For Hoot Wasm compilation:
;;;   (compile-file "src/main.scm" ...)
;;;
;;; Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    GUILE COMPATIBILITY
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-modules (ice-9 rdelim)        ;; read-line
             (ice-9 format)        ;; format
             (ice-9 textual-ports) ;; get-string-all etc.
             (srfi srfi-9)         ;; define-record-type
             (srfi srfi-9 gnu)     ;; set- fields (mutable records)
             (srfi srfi-1)         ;; list-copy, fold, etc.
             (ice-9 receive))      ;; receive

;; Determine the directory containing this file, so loads work
;; regardless of the working directory.
(define %main-dir
  (let ((s (current-filename)))
    (if s
        (dirname s)
        "src")))

(define (load-relative path)
  (load (string-append %main-dir "/" path)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    LOAD ORDER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Core data structures (no dependencies)
(load-relative "core/stacks.scm")

;;; Model layer (depends on nothing external)
(load-relative "model/math.scm")
(load-relative "model/color.scm")

;;; Canvas FFI stubs (for native testing; replaced by define-foreign in Wasm)
(load-relative "render/canvas-ffi.scm")

;;; Scene graph (depends on color)
(load-relative "model/scene-graph.scm")

;;; Profiles — cons-cell size computation (depends on math)
(load-relative "model/profiles.scm")

;;; Placement — convex-hull positioning (depends on math, stacks)
(load-relative "model/placement.scm")

;;; Pointer routing — polyline geometry (depends on math, profiles)
(load-relative "model/pointers.scm")

;;; Renderer (depends on canvas-ffi, scene-graph)
(load-relative "render/renderer.scm")

;;; Observer interface (depends on nothing)
(load-relative "core/eval-observer.scm")

;;; D3 FFI stubs (for native testing; replaced by define-foreign in Wasm)
(load-relative "render/d3-ffi-stubs.scm")

;;; Web observer (depends on scene-graph, renderer, eval-observer, color)
(load-relative "ui/web-observer.scm")

;;; Environment manipulation (depends on eval-observer)
(load-relative "core/environments.scm")

;;; Host eval — Guile's native eval for resolving primitives
(define (*host-eval* var)
  (eval var (interaction-environment)))

;;; Metacircular evaluator (depends on everything above)
(load-relative "core/meta.scm")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    INITIALIZATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (envdraw-start)
  ;; Create the scene graph root
  (let* ((root (make-group-node 0 0))
         ;; Create the web observer
         (obs (make-web-observer root))
         ;; Initialize the evaluator
         (eval-one (envdraw-init obs)))

    ;; Store canvas context for rendering
    ;; (In browser, this comes from FFI.  For testing, use stub.)
    (set! *render-ctx* (make-test-canvas-context))

    ;; Set trace callback (for testing, print to stdout)
    (set! *trace-callback*
          (lambda (s)
            (display s)
            (newline)))

    ;; Return the evaluator function for the REPL
    eval-one))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    REPL (for terminal testing)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (envdraw-repl)
  (let ((eval-one (envdraw-start)))
    (let loop ()
      (display "EnvDraw> ")
      (force-output)
      (let ((line (read-line (current-input-port))))
        (cond ((eof-object? line)
               (newline)
               (display "Bye.\n"))
              ((string=? (string-trim-both line) "")
               (loop))
              (else
               (let ((result
                      (catch #t
                        (lambda () (eval-one line))
                        (lambda (key . args)
                          (display "*** Error: ")
                          (display key)
                          (display " ")
                          (for-each (lambda (a) (display a) (display " ")) args)
                          (newline)
                          #f))))
                 (when result
                   (display result)
                   (newline)))
               (loop)))))))

;;; If run directly, start the REPL
;;; (envdraw-repl)
