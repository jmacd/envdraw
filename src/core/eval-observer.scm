;;; eval-observer.scm — Observer interface decoupling evaluator from UI
;;;
;;; The metacircular evaluator calls these hooks instead of directly
;;; creating Tk widgets.  The web UI layer provides a concrete
;;; implementation that builds scene graph nodes and triggers rendering.
;;;
;;; Copyright (C) 2026 Josh MacDonald

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                      OBSERVER RECORD
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; The observer is a record of callback procedures.  The evaluator
;;; receives one observer at startup and calls its hooks at each
;;; significant event.

(define-record-type <eval-observer>
  (make-eval-observer
   on-frame-created
   on-binding-placed
   on-binding-updated
   on-procedure-created
   on-env-pointer
   on-before-eval
   on-after-eval
   on-reduce
   on-wait-for-step
   on-write-trace
   on-error
   on-gc-mark
   on-gc-sweep
   on-request-render
   on-tail-gc)
  eval-observer?
  ;; (env-name parent-env width height) → frame-id
  (on-frame-created       observer-on-frame-created)
  ;; (frame-id var-name value value-type) → binding-id
  (on-binding-placed      observer-on-binding-placed)
  ;; (frame-id var-name new-value value-type) → void
  (on-binding-updated     observer-on-binding-updated)
  ;; (lambda-text frame-id) → proc-id
  (on-procedure-created   observer-on-procedure-created)
  ;; (child-frame-id parent-frame-id) → void
  (on-env-pointer         observer-on-env-pointer)
  ;; (expr env-name indent-level) → void
  (on-before-eval         observer-on-before-eval)
  ;; (result indent-level) → void
  (on-after-eval          observer-on-after-eval)
  ;; (indent-level) → void
  (on-reduce              observer-on-reduce)
  ;; (message) → void  (blocks until user clicks Step/Continue)
  (on-wait-for-step       observer-on-wait-for-step)
  ;; (string) → void
  (on-write-trace         observer-on-write-trace)
  ;; (string) → void
  (on-error               observer-on-error)
  ;; (object-id) → void
  (on-gc-mark             observer-on-gc-mark)
  ;; (object-id) → void
  (on-gc-sweep            observer-on-gc-sweep)
  ;; () → void
  (on-request-render      observer-on-request-render)
  ;; (frame-id) → void  (tail-call optimization: remove dead frame)
  (on-tail-gc             observer-on-tail-gc))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    NULL OBSERVER (for testing)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; A no-op observer that can be used for headless evaluator testing.
;;; All hooks do nothing or return stub values.

(define *null-frame-counter* 0)
(define *null-proc-counter* 0)
(define *null-binding-counter* 0)

(define (make-null-observer)
  (set! *null-frame-counter* 0)
  (set! *null-proc-counter* 0)
  (set! *null-binding-counter* 0)
  (make-eval-observer
   ;; on-frame-created
   (lambda (env-name parent-env-id width height)
     (set! *null-frame-counter* (+ 1 *null-frame-counter*))
     (string-append "frame-" (number->string *null-frame-counter*)))
   ;; on-binding-placed
   (lambda (frame-id var-name value value-type)
     (set! *null-binding-counter* (+ 1 *null-binding-counter*))
     (string-append "binding-" (number->string *null-binding-counter*)))
   ;; on-binding-updated
   (lambda (frame-id var-name new-value value-type)
     (values))
   ;; on-procedure-created
   (lambda (lambda-text frame-id)
     (set! *null-proc-counter* (+ 1 *null-proc-counter*))
     (string-append "proc-" (number->string *null-proc-counter*)))
   ;; on-env-pointer
   (lambda (child-frame-id parent-frame-id)
     (values))
   ;; on-before-eval
   (lambda (expr env-name indent)
     (values))
   ;; on-after-eval
   (lambda (result indent)
     (values))
   ;; on-reduce
   (lambda (indent)
     (values))
   ;; on-wait-for-step
   (lambda (message)
     (values))  ; no-op: never blocks
   ;; on-write-trace
   (lambda (s)
     (values))
   ;; on-error
   (lambda (s)
     (values))
   ;; on-gc-mark
   (lambda (obj-id)
     (values))
   ;; on-gc-sweep
   (lambda (obj-id)
     (values))
   ;; on-request-render
   (lambda ()
     (values))
   ;; on-tail-gc
   (lambda (frame-id)
     (values))))

;;; A trace observer that prints eval trace to stdout (for debugging).

(define (make-trace-observer)
  (let ((null-obs (make-null-observer)))
    (make-eval-observer
     (observer-on-frame-created null-obs)
     (observer-on-binding-placed null-obs)
     (observer-on-binding-updated null-obs)
     (observer-on-procedure-created null-obs)
     (observer-on-env-pointer null-obs)
     ;; on-before-eval: print trace
     (lambda (expr env-name indent)
       (display (make-string indent #\space))
       (display "EVAL in ")
       (display env-name)
       (display ": ")
       (display expr)
       (newline))
     ;; on-after-eval: print return
     (lambda (result indent)
       (display (make-string indent #\space))
       (display "RETURNING: ")
       (display result)
       (newline))
     ;; on-reduce
     (lambda (indent)
       (values))
     ;; on-wait-for-step
     (lambda (message)
       (values))
     ;; on-write-trace
     (lambda (s)
       (display s)
       (newline))
     ;; on-error
     (lambda (s)
       (display "*** ERROR: ")
       (display s)
       (newline))
     ;; on-gc-mark
     (observer-on-gc-mark null-obs)
     ;; on-gc-sweep
     (observer-on-gc-sweep null-obs)
     ;; on-request-render
     (observer-on-request-render null-obs)
     ;; on-tail-gc
     (observer-on-tail-gc null-obs))))
