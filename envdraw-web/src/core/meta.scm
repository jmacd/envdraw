;;; meta.scm — The Metacircular Evaluator
;;;
;;; Ported from meta.stk — all Tk widget calls replaced with
;;; observer callbacks.  Max Hailperin's tail-recursion changes
;;; (Oct 2, 1995) are preserved faithfully.
;;;
;;; Copyright (C) 1995, 1996 Josh MacDonald <jmacd@CS.Berkeley.EDU>
;;; Port Copyright (C) 2026 Josh MacDonald
;;;
;;; Changes contributed by Max Hailperin <max@gac.edu> Oct 2, 1995.
;;; (Proper tail-recursion: after-eval/reduce protocol)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    PROCEDURE INFO (must be before viewed-rep)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Replaces <procedure-object> STklos class.
;;; procedure-info tracks the scene-graph ID and the frame-info
;;; of the enclosing environment.
;;;
;;; NOTE: This define-record-type MUST precede viewed-rep because
;;; Guile's SRFI-9 accessors are syntax transformers that must exist
;;; before any code references them.

(define-record-type <procedure-info>
  (make-procedure-info id frame source-line)
  procedure-info?
  (id          procedure-info-id)
  (frame       procedure-info-frame)
  (source-line procedure-info-source-line))

;;; Set the late-bound callback used by environments.scm to extract
;;; the scene-graph node ID from a compound procedure value.
(set! *extract-proc-id*
  (lambda (val)
    (if (and (pair? val) (procedure-info? (car val)))
        (procedure-info-id (car val))
        #f)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    EXTERNAL REPRESENTATIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; (VIEWED-REP OBJECT) formats metacircular objects into a viewable
;;; string form.  The metacircular evaluator uses expanded internal
;;; representations, so the normal printed form is not adequate.

(define (viewed-rep object)
  (cond ((compound-procedure? object)
         (let* ((po (procedure-info-of object))
                (fi (procedure-info-frame po)))
           (string-append "#[compound-procedure "
                          (format-sexp
                           (cons 'lambda (cdr (procedure-text object))))
                          " "
                          (frame-info-name fi)
                          "]")))
        ((special-form? object)
         (string-append "#[special-form "
                        (symbol->string (special-form-type object))
                        "]"))
        ((view-continuation? object)
         (string-append "#[continuation #"
                        (number->string (continuation-id object))
                        "]"))
        ((external-binding? object)
         (let ((val (external-value object))
               (var (external-symbol object)))
           (cond ((or (self-evaluating? val)
                      (pair? val)
                      (symbol? val))
                  (format-sexp val))
                 (else (string-append "#[primitive "
                                      (symbol->string var)
                                      "]")))))
        ((list? object)
         (string-append "("
                        (string-join (map viewed-rep object) " ")
                        ")"))
        ((pair? object)
         (format-sexp object))
        (else (format-sexp object))))

;;; (VIEWABLE-PAIR? OBJ) tests whether a given object is a real Scheme
;;; cons cell as opposed to an internal representation that uses lists.
(define (viewable-pair? obj)
  (and (pair? obj)
       (not (or (compound-procedure? obj)
                (view-continuation? obj)
                (special-form? obj)
                (and (external-binding? obj)
                     (not (pair? (external-value obj))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    UTILITY PROCEDURES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Simple S-expression formatter (replaces STk's format ~A for sexps)
(define (format-sexp x)
  (cond ((string? x) (string-append "\"" x "\""))
        ((symbol? x) (symbol->string x))
        ((number? x) (number->string x))
        ((boolean? x) (if x "#t" "#f"))
        ((null? x) "()")
        ((char? x) (string-append "#\\" (string x)))
        ((vector? x)
         (string-append "#("
                        (string-join (map format-sexp (vector->list x)) " ")
                        ")"))
        ((pair? x)
         (string-append "("
                        (let loop ((p x))
                          (cond ((null? (cdr p))
                                 (format-sexp (car p)))
                                ((pair? (cdr p))
                                 (string-append (format-sexp (car p))
                                                " "
                                                (loop (cdr p))))
                                (else
                                 (string-append (format-sexp (car p))
                                                " . "
                                                (format-sexp (cdr p))))))
                        ")"))
        (else (let ((p (open-output-string)))
                (write x p)
                (get-output-string p)))))

;;; String join (not always in R7RS-small)
(define (string-join lst sep)
  (cond ((null? lst) "")
        ((null? (cdr lst)) (car lst))
        (else (string-append (car lst) sep
                             (string-join (cdr lst) sep)))))

;;; Limit nested list depth to prevent infinite printing
(define (safen-list x)
  (if (pair? x)
      (safen-list-depth x 10)
      x))

(define (safen-list-depth x depth)
  (cond ((<= depth 0) '(...))
        ((pair? x)
         (cons (safen-list-depth (car x) (- depth 1))
               (safen-list-depth (cdr x) (- depth 1))))
        (else x)))

;;; n-spaces: return a string of n space characters
(define (n-spaces n)
  (make-string (max 0 n) #\space))

;;; atom? predicate (not in R7RS)
(define (atom? x)
  (not (pair? x)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;          USER-FACING PROCEDURES (bound in meta-environment)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (user-display object)
  (when *meta-observer*
    ((observer-on-write-trace *meta-observer*) (viewed-rep object))))

(define (user-print object)
  (when *meta-observer*
    ((observer-on-write-trace *meta-observer*) (viewed-rep object))
    ((observer-on-write-trace *meta-observer*) "\n")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    GLOBAL STATE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; The global environment, where view-eval begins each REPL loop.
(define the-global-environment '())

;;; Stack of eval arguments for stacktrace on error.
(define the-eval-stack #f)  ; initialized in envdraw-start

;;; Copy of eval stack at time of error.
(define last-error-stack #f)

;;; Current eval trace indent level
(define *eval-indent-level* 0)

;;; Current REPL line number (advanced by number of input lines)
(define *current-repl-line* 0)

;;; Lambda source-line queue: ordered list of absolute line numbers
;;; where (lambda or (define ( appears in the current REPL input.
;;; Consumed by make-procedure during evaluation.
(define *lambda-line-queue* '())

;;; Stepping control
(define view:confirmation #f)
(define view:continue #f)
(define view:use-stepping? #f)

;;; The current observer (set at startup)
(define *meta-observer* #f)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;               SOURCE-LINE SCANNING HELPERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Check whether str contains prefix starting at position pos.
(define (string-match-at? str prefix pos)
  (let ((plen (string-length prefix))
        (slen (string-length str)))
    (and (<= (+ pos plen) slen)
         (let check ((j 0))
           (or (>= j plen)
               (and (char=? (string-ref str (+ pos j))
                            (string-ref prefix j))
                    (check (+ j 1))))))))

;;; Count newlines in a string.
(define (count-newlines str)
  (let ((len (string-length str)))
    (let loop ((i 0) (n 0))
      (if (>= i len)
          n
          (loop (+ i 1)
                (if (char=? (string-ref str i) #\newline)
                    (+ n 1) n))))))

;;; Scan source text for (lambda and (define ( occurrences.
;;; Returns an ordered list of absolute line numbers (ascending).
;;; Skips occurrences inside string literals and comments.
(define (scan-lambda-lines source-text start-line)
  (let ((len (string-length source-text)))
    (let loop ((i 0) (line-offset 0) (in-string #f) (escape #f)
               (result '()))
      (if (>= i len)
          (reverse result)
          (let ((ch (string-ref source-text i)))
            (cond
              ;; After backslash in string — skip one char
              (escape
               (loop (+ i 1) line-offset in-string #f result))
              ;; Backslash inside string
              ((and in-string (char=? ch #\\))
               (loop (+ i 1) line-offset #t #t result))
              ;; Quote toggles string mode
              ((char=? ch #\")
               (loop (+ i 1) line-offset (not in-string) #f result))
              ;; Inside string — just advance
              (in-string
               (if (char=? ch #\newline)
                   (loop (+ i 1) (+ line-offset 1) #t #f result)
                   (loop (+ i 1) line-offset #t #f result)))
              ;; Newline
              ((char=? ch #\newline)
               (loop (+ i 1) (+ line-offset 1) #f #f result))
              ;; Semicolon — skip to end of line (comment)
              ((char=? ch #\;)
               (let skip ((j (+ i 1)))
                 (if (or (>= j len)
                         (char=? (string-ref source-text j) #\newline))
                     (loop j line-offset #f #f result)
                     (skip (+ j 1)))))
              ;; Open paren — check for (lambda or (define (
              ((char=? ch #\()
               (let ((abs-line (+ start-line line-offset)))
                 (cond
                   ((string-match-at? source-text "(lambda" i)
                    (loop (+ i 7) line-offset #f #f
                          (cons abs-line result)))
                   ((string-match-at? source-text "(define (" i)
                    (loop (+ i 9) line-offset #f #f
                          (cons abs-line result)))
                   (else
                    (loop (+ i 1) line-offset #f #f result)))))
              ;; Anything else
              (else
               (loop (+ i 1) line-offset #f #f result))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                         SPECIAL FORMS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define special-forms-list
  '(quote define set! lambda cond if let let* and or begin eval apply))

(define (define-special-forms! env)
  (for-each
   (lambda (x)
     (define-variable! x (list 'special-form x) env #f))
   special-forms-list)
  (define-variable! 'sequence '(special-form begin) env #f))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;          SETUP ENVIRONMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (setup-environment obs)
  (let ((initial-env (make-global-environment obs)))
    ;; Override bindings for user-facing procedures
    (define-variable! 'print
      (lookup-variable-value 'user-print initial-env 'print)
      initial-env #f)
    (define-variable! 'display
      (lookup-variable-value 'user-display initial-env 'display)
      initial-env #f)
    ;; exit and quit are handled by the UI layer
    (define-special-forms! initial-env)
    initial-env))

(define (make-global-environment obs)
  (let ((env (extend-environment '() '() '()
                                 ':name "GLOBAL ENVIRONMENT"
                                 ':height INITIAL_ENV_HEIGHT
                                 ':width INITIAL_ENV_WIDTH)))
    env))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                         TRACING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; write-to-trace sends a string to the observer's trace output.
(define (write-to-trace s)
  (when *meta-observer*
    ((observer-on-write-trace *meta-observer*) s)))

;;; before-eval: push expr on stack, print trace, indent
(define (before-eval exp env)
  (stack-push! the-eval-stack exp)
  (let ((msg (string-append (n-spaces *eval-indent-level*)
                            "EVAL in "
                            (environment-name env)
                            ": "
                            (viewed-rep exp))))
    (write-to-trace msg)
    (when *meta-observer*
      ((observer-on-before-eval *meta-observer*)
       (viewed-rep exp) (environment-name env) *eval-indent-level*)))
  (set! *eval-indent-level* (+ *eval-indent-level* 2)))

;;; after-eval: de-indent, print return value, return it
(define (after-eval ret)
  (set! *eval-indent-level* (max 0 (- *eval-indent-level* 2)))
  (let ((msg (string-append (n-spaces *eval-indent-level*)
                            "RETURNING: "
                            (format-sexp (safen-list (viewed-rep ret))))))
    (write-to-trace msg)
    (when *meta-observer*
      ((observer-on-after-eval *meta-observer*)
       (viewed-rep ret) *eval-indent-level*)))
  ret)

;;; reduce: de-indent without printing — for tail positions
;;; (Max Hailperin's contribution, Oct 2, 1995)
(define (reduce)
  (set! *eval-indent-level* (max 0 (- *eval-indent-level* 2)))
  (when *meta-observer*
    ((observer-on-reduce *meta-observer*) *eval-indent-level*)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    WAIT FOR STEP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Replaces the tkwait-based stepping mechanism.
;;; In the web version, this calls the observer which can suspend
;;; the fiber until the user clicks Step/Continue.

(define (wait-for-confirmation msg)
  (unless view:continue
    (let ((trace-msg (string-append (n-spaces (max 0 (- *eval-indent-level* 2)))
                                    "*** " msg)))
      (write-to-trace trace-msg)
      (when *meta-observer*
        ((observer-on-wait-for-step *meta-observer*) trace-msg)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                         EVAL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Modified as described at top of file (Max Hailperin, Oct 2, 1995).
;;; The (after-eval ...) was removed from the main dispatch and placed
;;; into each base case (self-evaluating, variable).  Recursive cases
;;; use (reduce) for proper tail-recursion.

(define (view-eval exp env)
  (before-eval exp env)
  (cond ((self-evaluating? exp) (after-eval exp))
        ((variable? exp) (after-eval (lookup-variable-value exp env)))
        ((operation? exp)
         (let ((op (view-eval (operator exp) env)))
           (if (special-form? op)
               (eval-special-form op (operands exp) env)
               (view-apply op (list-of-values (operands exp) env)))))
        (else (error "Unknown expression type -- eval" exp))))

(define (list-of-values exps env)
  (cond ((no-operands? exps) '())
        (else (cons (view-eval (first-operand exps) env)
                    (list-of-values (rest-operands exps) env)))))

(define eval-expression cadr)
(define operands cdr)
(define operator car)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                         APPLY
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (view-apply procedure arguments)
  (cond ((view-continuation? procedure)
         (set! the-eval-stack (continuation-stack procedure))
         (set! *eval-indent-level* (continuation-indent-level procedure))
         (write-to-trace "*** Throwing continuation")
         (set-car! (cdr procedure) (stack-copy the-eval-stack))
         ((continuation-continuation procedure) (car arguments)))
        ((primitive-procedure? (lazy-deextern procedure))
         (wait-for-confirmation
          (string-append "APPLY primitive procedure "
                         (symbol->string (external-symbol procedure))
                         " args: "
                         (format-sexp (map (lambda (x)
                                            (viewed-rep (safen-list x)))
                                          arguments))
                         "."))
         (after-eval
          (apply (lazy-deextern procedure) (map lazy-deextern arguments))))
        ((compound-procedure? procedure)
         (let* ((apply-env (procedure-environment procedure))
                (src-line (procedure-info-source-line
                           (procedure-info-of procedure)))
                (frame-name (if (> src-line 0)
                                (string-append
                                 "L" (number->string src-line))
                                (string-append
                                 "E" (number->string
                                      *next-environment-number*)))))
           (wait-for-confirmation
            (string-append
             "APPLY " (viewed-rep procedure)
             " args: "
             (format-sexp (map (lambda (x)
                                 (viewed-rep (safen-list x))) arguments))
             ", making new " frame-name
             "."))
           (eval-sequence (env-procedure-body procedure)
                          (extend-environment
                           (parameters procedure)
                           arguments
                           apply-env
                           ':name frame-name))))
        (else (error "Unknown procedure type -- apply" procedure))))

(define (lazy-deextern x)
  (if (external-binding? x)
      (external-value x)
      x))

(define (compound-procedure? proc)
  (if (atom? proc)
      #f
      (procedure-info? (procedure-info-of proc))))

(define primitive-procedure? procedure?)
(define procedure-info-of car)
(define parameters cadadr)
(define env-procedure-body cddadr)
(define procedure-environment caddr)
(define no-operands? null?)
(define first-operand car)
(define rest-operands cdr)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                    SPECIAL FORMS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; The first four special forms never result in a reduction, so
;;; (after-eval ...) wraps them here. For the rest, (reduce) or
;;; (after-eval ...) is in the specialized evaluator.
;;; (Max Hailperin, Oct 2, 1995)

(define (eval-special-form op args env)
  (let ((exp (cons op args)))
    (case (special-form-type op)
      ((quote)  (after-eval (text-of-quotation exp)))
      ((define) (after-eval (eval-definition exp env)))
      ((set!)   (after-eval (eval-assignment exp env)))
      ((lambda) (after-eval (make-procedure exp env)))
      ((cond)   (eval-cond (clauses exp) env))
      ((if)     (eval-if exp env))
      ((let)    (eval-let exp env))
      ((let*)   (eval-let* exp env))
      ((and)    (eval-and (predicates exp) env))
      ((or)     (eval-or (predicates exp) env))
      ((begin)  (eval-sequence (rest-exps exp) env))
      ((eval)   (view-eval (eval-expression exp) env))
      ((apply)  (eval-apply exp env))
      (else     (error "Unknown special form" op)))))

(define special-form-type cadr)

(define (make-eval-predicate sym)
  (lambda (exp)
    (if (atom? exp)
        #f
        (equal? (car exp) sym))))

;;; quote
(define text-of-quotation cadr)

;;; lookup
(define (lookup-variable-value var env . name)
  (let ((b (binding-in-env var env)))
    (if (found-binding? b)
        (binding-value b)
        (list 'external-binding
              (if (null? name) var (car name))
              (*host-eval* var)))))

(define external-value caddr)
(define external-symbol cadr)
(define external-binding? (make-eval-predicate 'external-binding))

;;; define
(define (eval-definition exp env)
  (define-variable! (definition-variable exp)
    (view-eval (definition-value exp) env)
    env)
  (definition-variable exp))

(define (definition-variable exp)
  (if (variable? (cadr exp))
      (cadr exp)
      (caadr exp)))

(define (definition-value exp)
  (if (variable? (cadr exp))
      (caddr exp)
      (cons 'lambda
            (cons (cdadr exp)
                  (cddr exp)))))

;;; assignment (set!)
(define (eval-assignment exp env)
  (let ((new-value (view-eval (assignment-value exp) env)))
    (set-variable-value! (assignment-variable exp)
                         new-value
                         env)
    new-value))

(define assignment-variable cadr)
(define assignment-value caddr)

;;; lambda — make-procedure
;;; Creates a compound procedure representation and notifies observer.
(define (make-procedure lambda-exp env)
  (let* ((fi (frame-info-of env))
         ;; Reconstruct clean lambda sexp: the car of lambda-exp is the
         ;; special-form object (special-form lambda), not the symbol lambda.
         (clean-exp (cons 'lambda (cdr lambda-exp)))
         (proc-id
          (if *meta-observer*
              ((observer-on-procedure-created *meta-observer*)
               (format-sexp clean-exp)
               (frame-info-id fi))
              "proc-anon"))
         ;; Pop source line from the lambda-line queue if available
         (src-line (if (pair? *lambda-line-queue*)
                       (let ((ln (car *lambda-line-queue*)))
                         (set! *lambda-line-queue* (cdr *lambda-line-queue*))
                         ln)
                       *current-repl-line*))
         (pi (make-procedure-info proc-id fi src-line))
         (it (list pi lambda-exp env)))
    (when *meta-observer*
      ((observer-on-request-render *meta-observer*)))
    it))

(define procedure-text cadr)

;;; cond
;;; (Max Hailperin: added after-eval to oddball case of running off end)
(define (eval-cond clist env)
  (cond ((no-clauses? clist) (after-eval #f))
        ((else-clause? (first-clause clist))
         (eval-sequence (actions (first-clause clist)) env))
        ((view-eval (predicate (first-clause clist)) env)
         (eval-sequence (actions (first-clause clist)) env))
        (else (eval-cond (rest-clauses clist) env))))

(define (else-clause? clause) (eq? (predicate clause) 'else))
(define predicate car)
(define clauses cdr)
(define no-clauses? null?)
(define first-clause car)
(define rest-clauses cdr)
(define actions cdr)

;;; if
;;; (Max Hailperin: reduce before consequent/alternative for tail-recursion)
(define (eval-if exp env)
  (if (null? (cdr exp))
      (error "Empty IF statement")
      (if (view-eval (cadr exp) env)
          (if (null? (cddr exp))
              (error "Not enough IF clauses")
              (begin (reduce)
                     (view-eval (caddr exp) env)))
          (if (not (null? (cdddr exp)))
              (begin (reduce)
                     (view-eval (cadddr exp) env))
              (after-eval (if #f #f))))))

;;; let
;;; (Max Hailperin: evaluating let as application is a reduction)
(define (eval-let exp env)
  (cond ((null? (cdr exp))
         (error "Empty LET statement"))
        ((null? (cddr exp))
         (error "No LET body"))
        (else #t))
  (let ((bindings (cadr exp))
        (body (cddr exp)))
    (reduce)
    (view-eval (cons (cons 'lambda (cons (map car bindings) body))
                     (map cadr bindings))
               env)))

;;; let*
;;; (Max Hailperin: evaluating let* as application is a reduction)
(define (eval-let* exp env)
  (cond ((null? (cdr exp))
         (error "Empty LET* statement"))
        ((null? (cddr exp))
         (error "No LET* body"))
        (else #t))
  (let ((bindings (cadr exp))
        (body (cddr exp)))
    (reduce)
    (if (null? (cdr bindings))
        (view-eval (cons (cons 'lambda (cons (map car bindings) body))
                         (map cadr bindings))
                   env)
        (view-eval (cons (cons 'lambda
                               (cons (list (caar bindings))
                                     (list (cons 'let*
                                                 (cons (cdr bindings)
                                                       body)))))
                         (list (cadar bindings)))
                   env))))

;;; and
;;; (Max Hailperin: special-cased last predicate for tail-recursion,
;;;  fixed to return true values other than #t)
(define (eval-and preds env)
  (cond ((null? preds) (after-eval #t))
        ((null? (cdr preds))
         (reduce)
         (view-eval (car preds) env))
        ((not (view-eval (car preds) env)) (after-eval #f))
        (else (eval-and (cdr preds) env))))

(define predicates cdr)

;;; or
;;; (Max Hailperin: special-cased last predicate for tail-recursion,
;;;  returns non-#t true values)
(define (eval-or preds env)
  (cond ((null? preds) (after-eval #f))
        ((null? (cdr preds))
         (reduce)
         (view-eval (car preds) env))
        ((let ((val (view-eval (car preds) env)))
           (if val (after-eval val) #f)))
        (else (eval-or (cdr preds) env))))

;;; sequence (begin)
;;; (Max Hailperin: last-exp case uses (reduce) for tail-recursion)
(define (eval-sequence exps env)
  (cond ((last-exp? exps) (reduce) (view-eval (first-exp exps) env))
        (else (view-eval (first-exp exps) env)
              (eval-sequence (rest-exps exps) env))))

(define (last-exp? seq) (null? (cdr seq)))
(define first-exp car)
(define rest-exps cdr)

;;; apply (special form, not view-apply)
(define (eval-apply exp env)
  (view-apply (view-eval (cadr exp) env)
              (let loop ((args (cddr exp)))
                (cond ((null? args) '())
                      ((null? (cdr args))
                       (map (lambda (x) (view-eval x env))
                            (view-eval (car args) env)))
                      (else
                       (cons (view-eval (car args) env)
                             (loop (cdr args))))))))

;;; continuations
(define (view-call/cc proc)
  (call/cc
   (lambda (k)
     (view-apply proc (list (make-view-continuation k))))))

(define make-view-continuation
  (let ((id 0))
    (lambda (c)
      (set! id (+ 1 id))
      (list 'continuation
            (stack-copy the-eval-stack)
            *eval-indent-level*
            c
            id))))

(define view-continuation? (make-eval-predicate 'continuation))
(define continuation-stack cadr)
(define continuation-indent-level caddr)
(define continuation-continuation cadddr)
(define (continuation-id x) (car (cddddr x)))
;;; cddddr: provided by (scheme cxr) in R7RS / built-in in Guile

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                         PREDICATES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (self-evaluating? exp)
  (or (null? exp)
      (number? exp)
      (boolean? exp)
      (vector? exp)
      (char? exp)
      (string? exp)))

(define variable? symbol?)
(define operation? pair?)

(define special-form? (make-eval-predicate 'special-form))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;               ENVDRAW ENTRY POINT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Initialize the evaluator with a given observer.
;;; Returns a procedure that evaluates one expression string
;;; and returns the result as a string.

(define (envdraw-init obs)
  (set! *meta-observer* obs)
  (set! *current-observer* obs)
  (set! the-eval-stack (make-stack))
  (set! last-error-stack #f)
  (set! *eval-indent-level* 0)
  (set! *current-repl-line* 0)
  (set! *lambda-line-queue* '())
  (set! *next-environment-number* 1)
  (set! view:confirmation #f)
  (set! view:continue #f)
  (set! view:use-stepping? #f)
  (set! the-global-environment (setup-environment obs))
  ;; Return the REPL evaluator procedure
  envdraw-eval-one)

;;; Evaluate one expression (called from the REPL)
(define (envdraw-eval-one input-string)
  (stack-empty! the-eval-stack)
  (set! *eval-indent-level* 0)
  (let* ((num-input-lines (+ 1 (count-newlines input-string)))
         (start-line (+ 1 *current-repl-line*)))
    ;; Set current line to the start of this input
    (set! *current-repl-line* start-line)
    ;; Scan source for lambda/define positions
    (set! *lambda-line-queue*
          (scan-lambda-lines input-string start-line))
    (set! view:continue (not view:use-stepping?))
    (let ((input (read (open-input-string input-string))))
      ;; Advance past all input lines
      (set! *current-repl-line*
            (+ start-line (- num-input-lines 1)))
      (if (eof-object? input)
          ""
          (let ((result (view-eval input the-global-environment)))
            (viewed-rep result))))))

;;; Stepping controls (called from UI buttons)
(define (env-step)
  (set! view:confirmation (not view:confirmation)))

(define (env-continue)
  (env-step)
  (set! view:continue #t))

(define (env-toggle-use-step)
  (set! view:continue view:use-stepping?)
  (set! view:use-stepping? (not view:use-stepping?)))

;;; Garbage collection — find all reachable frame-ids and proc-ids
;;; by walking from the-global-environment.
;;; Returns (list reachable-frame-ids reachable-proc-ids)
;;; where each is a list of strings.
(define (env-gc-reachable-ids)
  (let ((visited-frames '())
        (visited-procs  '()))
    ;; Walk an environment chain, marking all frames reachable.
    (define (walk-env env)
      (unless (null? env)
        (let ((fid (frame-info-id (frame-info-of env))))
          (unless (member fid visited-frames)
            (set! visited-frames (cons fid visited-frames))
            ;; Walk bindings in this frame for compound procedures
            (let loop ((bindings (first-frame env)))
              (unless (null? bindings)
                (let ((val (binding-value (first-binding bindings))))
                  (when (compound-procedure? val)
                    (walk-proc val)))
                (loop (rest-bindings bindings))))
            ;; Walk parent frames
            (unless (no-more-frames? (rest-frames env))
              (walk-env (rest-frames env)))))))
    ;; Walk a compound procedure: mark its proc-id and enclosing env
    (define (walk-proc proc)
      (let ((pid (procedure-info-id (procedure-info-of proc))))
        (unless (member pid visited-procs)
          (set! visited-procs (cons pid visited-procs))
          (walk-env (procedure-environment proc)))))
    ;; Start from the global environment
    (walk-env the-global-environment)
    (list visited-frames visited-procs)))
