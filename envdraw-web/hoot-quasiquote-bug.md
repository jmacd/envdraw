# Hoot 0.6.1 Bug: Large quasiquote with many unquotes produces invalid Wasm table index

**Component:** Guile Hoot (compile-wasm)  
**Version:** Hoot 0.6.1, Guile 3.0.11  
**Platform:** macOS arm64 (Apple Silicon), Firefox 134  
**Severity:** Runtime crash — compiled Wasm traps on load

---

## Summary

When a single quasiquote expression contains approximately 80 or more unquoted sub-expressions, `guild compile-wasm` produces a `.wasm` file that crashes at load time with `RuntimeError: index out of bounds` inside the Wasm `call` instruction. The compilation itself succeeds without error. Splitting the quasiquote into smaller expressions joined with `append` works around the issue.

## Minimal Reproducer

**`qq-bug.scm`** — crashes:
```scheme
(import (scheme base) (hoot ffi))

(define-foreign console-log "app" "consoleLog"
  (ref string) -> none)

;; A single quasiquote with ~80 unquoted procedure references.
;; Compiles without error but crashes at runtime.
(define *big-table*
  `((a1 . ,car) (a2 . ,cdr) (a3 . ,cons) (a4 . ,list)
    (a5 . ,pair?) (a6 . ,null?) (a7 . ,not) (a8 . ,eq?)
    (a9 . ,equal?) (a10 . ,+) (a11 . ,-) (a12 . ,*)
    (a13 . ,/) (a14 . ,<) (a15 . ,>) (a16 . ,=)
    (a17 . ,<=) (a18 . ,>=) (a19 . ,zero?) (a20 . ,number?)
    (a21 . ,symbol?) (a22 . ,string?) (a23 . ,boolean?) (a24 . ,char?)
    (a25 . ,integer?) (a26 . ,list?) (a27 . ,vector?) (a28 . ,procedure?)
    (a29 . ,abs) (a30 . ,max) (a31 . ,min) (a32 . ,quotient)
    (a33 . ,remainder) (a34 . ,modulo) (a35 . ,expt) (a36 . ,sqrt)
    (a37 . ,floor) (a38 . ,ceiling) (a39 . ,round) (a40 . ,truncate)
    (a41 . ,exact) (a42 . ,inexact) (a43 . ,positive?) (a44 . ,negative?)
    (a45 . ,even?) (a46 . ,odd?) (a47 . ,eqv?) (a48 . ,set-car!)
    (a49 . ,set-cdr!) (a50 . ,append) (a51 . ,length) (a52 . ,reverse)
    (a53 . ,list-ref) (a54 . ,assoc) (a55 . ,assq) (a56 . ,assv)
    (a57 . ,member) (a58 . ,memq) (a59 . ,memv) (a60 . ,string-append)
    (a61 . ,string-length) (a62 . ,string-ref) (a63 . ,substring)
    (a64 . ,string=?) (a65 . ,string<?) (a66 . ,string>?)
    (a67 . ,number->string) (a68 . ,string->number)
    (a69 . ,symbol->string) (a70 . ,string->symbol)
    (a71 . ,char->integer) (a72 . ,integer->char)
    (a73 . ,make-vector) (a74 . ,vector) (a75 . ,vector-ref)
    (a76 . ,vector-set!) (a77 . ,vector-length)
    (a78 . ,map) (a79 . ,for-each) (a80 . ,apply)
    (a81 . ,values) (a82 . ,error) (a83 . ,newline)
    (a84 . ,display) (a85 . ,write) (a86 . ,read)))

(console-log "big-table loaded OK")
```

**`qq-bug-ok.scm`** — same data, split into smaller pieces — works:
```scheme
(import (scheme base) (hoot ffi))

(define-foreign console-log "app" "consoleLog"
  (ref string) -> none)

;; Same entries split into small groups — works fine.
(define *part1*
  `((a1 . ,car) (a2 . ,cdr) (a3 . ,cons) (a4 . ,list)
    (a5 . ,pair?) (a6 . ,null?) (a7 . ,not) (a8 . ,eq?)
    (a9 . ,equal?) (a10 . ,+) (a11 . ,-) (a12 . ,*)
    (a13 . ,/) (a14 . ,<) (a15 . ,>) (a16 . ,=)
    (a17 . ,<=) (a18 . ,>=) (a19 . ,zero?) (a20 . ,number?)))

(define *part2*
  `((a21 . ,symbol?) (a22 . ,string?) (a23 . ,boolean?) (a24 . ,char?)
    (a25 . ,integer?) (a26 . ,list?) (a27 . ,vector?) (a28 . ,procedure?)
    (a29 . ,abs) (a30 . ,max) (a31 . ,min) (a32 . ,quotient)
    (a33 . ,remainder) (a34 . ,modulo) (a35 . ,expt) (a36 . ,sqrt)
    (a37 . ,floor) (a38 . ,ceiling) (a39 . ,round) (a40 . ,truncate)))

(define *part3*
  `((a41 . ,exact) (a42 . ,inexact) (a43 . ,positive?) (a44 . ,negative?)
    (a45 . ,even?) (a46 . ,odd?) (a47 . ,eqv?) (a48 . ,set-car!)
    (a49 . ,set-cdr!) (a50 . ,append) (a51 . ,length) (a52 . ,reverse)
    (a53 . ,list-ref) (a54 . ,assoc) (a55 . ,assq) (a56 . ,assv)
    (a57 . ,member) (a58 . ,memq) (a59 . ,memv) (a60 . ,string-append)))

(define *part4*
  `((a61 . ,string-length) (a62 . ,string-ref) (a63 . ,substring)
    (a64 . ,string=?) (a65 . ,string<?) (a66 . ,string>?)
    (a67 . ,number->string) (a68 . ,string->number)
    (a69 . ,symbol->string) (a70 . ,string->symbol)
    (a71 . ,char->integer) (a72 . ,integer->char)
    (a73 . ,make-vector) (a74 . ,vector) (a75 . ,vector-ref)
    (a76 . ,vector-set!) (a77 . ,vector-length)
    (a78 . ,map) (a79 . ,for-each) (a80 . ,apply)
    (a81 . ,values) (a82 . ,error) (a83 . ,newline)
    (a84 . ,display) (a85 . ,write) (a86 . ,read)))

(define *big-table* (append *part1* *part2* *part3* *part4*))

(console-log "big-table loaded OK")
```

**`qq-bug.html`** — test harness:
```html
<!DOCTYPE html>
<html><body>
<p id="s">Loading...</p>
<script src="reflect.js"></script>
<script>
window.addEventListener("load", async () => {
  const el = document.getElementById("s");
  // Change to "qq-bug-ok.wasm" to test the working version
  const wasm = "qq-bug.wasm?" + Date.now();
  try {
    await Scheme.load_main(wasm, {
      reflect_wasm_dir: ".",
      user_imports: {
        app: { consoleLog(m) { console.log(m); el.textContent = m; } }
      }
    });
    el.textContent = "SUCCESS";
  } catch(e) {
    console.error(e);
    el.textContent = "CRASH: " + e.message;
  }
});
</script>
</body></html>
```

## Steps to Reproduce

```sh
guild compile-wasm -o qq-bug.wasm qq-bug.scm       # compiles OK
guild compile-wasm -o qq-bug-ok.wasm qq-bug-ok.scm  # compiles OK

python3 -m http.server 8080  # serve from same directory as reflect.js
# Open http://localhost:8080/qq-bug.html in Firefox
```

## Expected Result

"big-table loaded OK" appears in the console and on the page.

## Actual Result

`qq-bug.wasm` crashes immediately:
```
RuntimeError: index out of bounds
    call  reflect.js:380
    call  reflect.js:118
    #init_module  reflect.js:280
    load_main  reflect.js:285
```

`qq-bug-ok.wasm` (identical data, split quasiquotes) works correctly.

## Analysis

The crash occurs inside `api.call()` in reflect.js, which calls the Wasm-exported `$load` function (top-level initialization). The `$load` function traps before executing any user code — no `console-log` output appears.

The error `"index out of bounds"` is characteristic of a Wasm `call_indirect` with an out-of-range table index, suggesting the compiler emits an incorrect function reference when constructing the list from a large number of unquoted closures.

The threshold appears to be around 70–80 unquotes in a single quasiquote form. Quasiquotes with ≤20 unquotes work reliably.

## Workaround

Split large quasiquoted lists into smaller sub-lists (≤20 unquotes each) and join with `append`:

```scheme
;; Instead of:
(define *table* `((a . ,x) (b . ,y) ... 80+ entries ...))

;; Use:
(define *part1* `((a . ,x) (b . ,y) ...))
(define *part2* `(...))
(define *table* (append *part1* *part2* ...))
```

## Environment

```
$ guile --version
guile (GNU Guile) 3.0.11

$ guile -c '(use-modules (hoot config)) (display %version) (newline)'
0.6.1

$ uname -a
Darwin ... 24.x.x Darwin Kernel ... arm64

$ firefox --version
Mozilla Firefox 134.x
```
