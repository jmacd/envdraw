;;; environments.scm — Environment, frame, and binding manipulation
;;;
;;; Ported from environments.stk — decoupled from Tk widgets.
;;; Observer callbacks handle all visual side effects.
;;;
;;; Copyright (C) 1995, 1996 Josh MacDonald <jmacd@CS.Berkeley.EDU>
;;; Port Copyright (C) 2026 Josh MacDonald
;;;
;;; Changes contributed by Max Hailperin <max@gac.edu> Oct 2, 1995.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                         ENVIRONMENTS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Environments are lists of frames: ((frame-info . bindings) ...)
;;; Each frame-info is a <frame-info> record (replacing the old
;;; <frame-object> STklos class).

(define-record-type <frame-info>
  (%make-frame-info name id width height insertion-point environment parent-id)
  frame-info?
  (name            frame-info-name)
  (id              frame-info-id set-frame-info-id!)
  (width           frame-info-width    set-frame-info-width!)
  (height          frame-info-height   set-frame-info-height!)
  (insertion-point frame-info-inspt    set-frame-info-inspt!)
  (environment     frame-info-env      set-frame-info-env!)
  (parent-id       frame-info-parent-id set-frame-info-parent-id!))

;;; Binding records (replacing <binding-object> STklos class)
(define-record-type <binding-info>
  (%make-binding-info frame-info binding-data)
  binding-info?
  (frame-info  binding-info-frame)
  (binding-data binding-info-data))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    ENVIRONMENT SELECTORS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define first-frame cdar)
(define rest-frames cdr)
(define frame-info-of caar)  ; was frame-object
(define no-more-frames? null?)
(define adjoin-frame cons)

(define (set-first-frame! env new-frame)
  (set-cdr! (car env) new-frame))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    BINDING REPRESENTATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Bindings are lists: (variable value binding-info)
;;; This preserves the original representation for evaluator compatibility.

(define first-binding car)
(define rest-bindings cdr)
(define binding-variable car)
(define binding-value cadr)
(define binding-info-of caddr)  ; was binding-object

(define (adjoin-binding binding frame)
  (cons binding frame))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    ENVIRONMENT OPERATIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (binding-in-env var env)
  (if (no-more-frames? env)
      #f
      (let ((b (binding-in-frame var (first-frame env))))
        (if (found-binding? b)
            b
            (binding-in-env var (rest-frames env))))))

(define (binding-in-frame var frame)
  (let loop ((frame frame))
    (cond ((null? frame) #f)
          ((equal? (binding-variable (first-binding frame)) var)
           (first-binding frame))
          (else (loop (rest-bindings frame))))))

(define (found-binding? b) b)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                EXTEND, DEFINE, SET
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; *current-observer* is set by the evaluator at startup.
;;; It is used by environment operations that need to notify the UI.
(define *current-observer* #f)

;;; *extract-proc-id* — callback to get the scene-graph node id
;;; from a compound procedure value.  Set by meta.scm after the
;;; procedure-info record type is defined.  Returns #f for non-procs.
(define *extract-proc-id* (lambda (val) #f))

;;; *next-environment-number* — counter for naming new environments
(define *next-environment-number* 1)

;;; Configuration constants (match original defaults)
(define INITIAL_ENV_WIDTH 100)
(define INITIAL_ENV_HEIGHT 100)
(define MEDIUM_FONT_HEIGHT 14)

(define (extend-environment variables values base-env . args)
  (let* ((frame-data (make-frame variables values args base-env))
         (env (adjoin-frame frame-data base-env))
         (fi (frame-info-of env)))
    (set-frame-info-env! fi env)
    ;; Notify observer about each binding placement
    (when *current-observer*
      (for-each
       (lambda (binding)
         (let* ((var (binding-variable binding))
                (val (binding-value binding))
                (vtype (classify-value val))
                ;; For procedures, pass the proc-id so the observer
                ;; can draw a binding→procedure arrow.
                ;; For pairs, pass the actual pair so the observer
                ;; can decompose it into box-and-pointer structure.
                (vrep (cond ((*extract-proc-id* val) => (lambda (pid) pid))
                            ((eq? vtype 'pair) val)
                            (else (viewed-rep val)))))
           ((observer-on-binding-placed *current-observer*)
            (frame-info-id fi) var vrep vtype)))
       (first-frame env))
      ;; Create environment pointer to parent
      (unless (null? base-env)
        ((observer-on-env-pointer *current-observer*)
         (frame-info-id fi)
         (frame-info-id (frame-info-of base-env)))))
    env))

(define (classify-value val)
  (cond ((compound-procedure? val) 'procedure)
        ((viewable-pair? val)      'pair)
        (else                      'atom)))

(define (set-variable-value! var val env)
  (let ((b (binding-in-env var env)))
    (if (found-binding? b)
        (set-binding-value! b val)
        (error "Unbound variable -- SET!" var))))

(define (define-variable! var val env . place?)
  (let ((b (binding-in-frame var (first-frame env))))
    (if (found-binding? b)
        (set-binding-value! b val)
        (let ((binding (make-binding var val (frame-info-of env))))
          (set-first-frame! env (adjoin-binding binding (first-frame env)))
          (when (and (null? place?) *current-observer*)
            (let* ((pid (*extract-proc-id* val))
                   (vtype (classify-value val))
                   (vrep (cond (pid pid)
                               ((eq? vtype 'pair) val)
                               (else (viewed-rep val)))))
              ((observer-on-binding-placed *current-observer*)
               (frame-info-id (frame-info-of env))
               var
               vrep
               vtype)))))))

(define (set-binding-value! binding value)
  (let ((old-val (binding-value binding)))
    (set-car! (cdr binding) value)
    (when *current-observer*
      (let ((bi (binding-info-of binding)))
        (when (binding-info? bi)
          (let* ((vtype (classify-value value))
                 (vrep (cond ((*extract-proc-id* value) => (lambda (pid) pid))
                             ((eq? vtype 'pair) value)
                             (else (viewed-rep value)))))
            ((observer-on-binding-updated *current-observer*)
             (frame-info-id (binding-info-frame bi))
             (binding-variable binding)
             vrep
             vtype)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    FRAME CONSTRUCTION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (get-keyword key args default)
  (let loop ((a args))
    (cond ((null? a) default)
          ((null? (cdr a)) default)
          ((equal? (car a) key) (cadr a))
          (else (loop (cddr a))))))

(define (binding-width var val)
  ;; Estimate pixel width needed for a binding.
  ;; The original used (text-width ...) from Tk; we'll use a rough
  ;; character-count estimate initially.  The renderer can refine later.
  (let ((var-chars (string-length (safely-format var)))
        (val-chars (string-length (viewed-rep val))))
    (if (or (compound-procedure? val) (viewable-pair? val))
        (+ (* var-chars 8) 25)
        (+ (* (+ var-chars val-chars) 8) 50))))

(define (make-frame variables values args parent-env)
  ;; Validate argument count first
  (let ((argc
         (let loop ((count 0) (var variables) (val values))
           (cond ((and (null? var) (null? val)) count)
                 ((null? var)
                  (error "Too many arguments supplied" values))
                 ((not (pair? var)) count) ; dotted rest-arg
                 ((null? val)
                  (error "Too few arguments supplied" values))
                 (else (loop (+ count 1) (cdr var) (cdr val)))))))
    (let* ((width (apply max
                         (cons (get-keyword ':width args INITIAL_ENV_WIDTH)
                               (let loop ((vars variables) (vals values))
                                 (cond ((null? vars) '())
                                       ((not (pair? vars))
                                        (list (binding-width vars vals)))
                                       (else
                                        (cons (binding-width (car vars)
                                                             (car vals))
                                              (loop (cdr vars)
                                                    (cdr vals)))))))))
           (height (if (< argc 4)
                       (get-keyword ':height args INITIAL_ENV_HEIGHT)
                       (+ INITIAL_ENV_HEIGHT
                          (* (- argc 4) MEDIUM_FONT_HEIGHT))))
           (name (get-keyword ':name args
                              (string-append
                               "E" (number->string
                                    *next-environment-number*))))
           (fi (%make-frame-info
                name
                (string-append "frame-"
                               (number->string *next-environment-number*))
                width height
                MEDIUM_FONT_HEIGHT  ; initial insertion point
                #f                  ; environment, set later
                (if (null? parent-env)
                    #f
                    (frame-info-id (frame-info-of parent-env))))))
      ;; Notify observer to create a frame in the scene graph
      (when *current-observer*
        (let ((obs-id ((observer-on-frame-created *current-observer*)
                       name
                       (frame-info-parent-id fi)
                       width
                       height)))
          (when (string? obs-id)
            (set-frame-info-id! fi obs-id))))
      ;; Increment frame counter unless explicitly named
      (unless (get-keyword ':name args #f)
        (set! *next-environment-number*
              (+ 1 *next-environment-number*)))
      ;; Build the binding list (frame-info . bindings)
      (cons fi
            (let loop ((variables variables) (values values))
              (cond ((and (null? variables) (null? values)) '())
                    ((not (pair? variables))
                     (list (make-binding variables values fi)))
                    (else
                     (adjoin-binding
                      (make-binding (car variables) (car values) fi)
                      (loop (cdr variables) (cdr values))))))))))

(define (make-binding variable value frame-info)
  (let ((it (list variable value 'any)))
    (set-car! (cddr it) (%make-binding-info frame-info it))
    it))

(define (environment-name env)
  (frame-info-name (frame-info-of env)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    UTILITY
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (safely-format x)
  (cond ((symbol? x) (symbol->string x))
        ((string? x) x)
        ((number? x) (number->string x))
        (else (let ((p (open-output-string)))
                (write x p)
                (get-output-string p)))))
