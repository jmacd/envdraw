# EnvDraw Revival: Detailed Step-by-Step Plan

## Project Goal

Port EnvDraw — a metacircular Scheme evaluator that draws its own
environment diagrams — from STk/Tk (1996) to run in a web browser,
using Guile Hoot (Scheme → WebAssembly) and HTML5 Canvas.

The result is a single-page web application: the user types Scheme
expressions, they are evaluated by a metacircular evaluator running in
WebAssembly, and environment/box-and-pointer diagrams are drawn live
on an HTML5 Canvas.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                     Browser                          │
│                                                      │
│  ┌────────────┐   ┌──────────────────────────────┐   │
│  │  HTML UI    │   │      HTML5 Canvas            │   │
│  │  - REPL     │   │      (diagram output)        │   │
│  │  - toolbar  │   │                              │   │
│  │  - trace    │   │                              │   │
│  └──────┬─────┘   └──────────────┬───────────────┘   │
│         │                        │                   │
│         │    Hoot FFI (define-foreign)                │
│         │        │               │                   │
│  ┌──────▼────────▼───────────────▼───────────────┐   │
│  │           Scheme (compiled to Wasm)            │   │
│  │                                                │   │
│  │  ┌─────────────────────────────────────────┐   │   │
│  │  │  Layer 1: Metacircular Evaluator        │   │   │
│  │  │  (meta.scm, environments.scm, stacks)   │   │   │
│  │  └────────────────┬────────────────────────┘   │   │
│  │                   │ observer callbacks         │   │
│  │  ┌────────────────▼────────────────────────┐   │   │
│  │  │  Layer 2: Scene Graph                   │   │   │
│  │  │  (diagram records, layout, placement)   │   │   │
│  │  └────────────────┬────────────────────────┘   │   │
│  │                   │ draw commands              │   │
│  │  ┌────────────────▼────────────────────────┐   │   │
│  │  │  Layer 3: Canvas Renderer               │   │   │
│  │  │  (FFI calls to Canvas2D API)            │   │   │
│  │  └─────────────────────────────────────────┘   │   │
│  └────────────────────────────────────────────────┘   │
│                                                      │
│  ┌────────────────────────────────────────────────┐   │
│  │  reflect.js  +  JS bootstrap glue             │   │
│  └────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

---

## File-by-file Inventory and Disposition

This section maps every original .stk file to what happens to it.

### Pure logic — port with moderate changes

| Original | New | LOC | Notes |
|----------|-----|-----|-------|
| meta.stk | meta.scm | 798 | Core evaluator. Remove Tk widget calls; replace `<stack>` class usage; replace `tkwait` with async-compatible stepping; replace `write-to-listbox` with observer callback; replace `make <procedure-object>` with scene graph call. |
| environments.stk | environments.scm | 192 | Environment/frame/binding manipulation. Remove `<frame-object>` widget creation; replace with scene graph node creation via callback. |
| stacks.stk | stacks.scm | 106 | Stack and doubly-linked list. Replace `define-class <stack>` with `define-record-type`. Replace `define-class <dll>` with `define-record-type`. |
| math.stk | math.scm | 100 | Vector/list arithmetic. Replace `define-generic`/`define-method` polymorphic dispatch with explicit cond-based dispatch on type. |
| color.stk | color.scm | 88 | RGB color manipulation. Replace `widget-color`/`set-widget-color!` with pure record operations. Drop Tk hex parsing. |

### Layout/geometry — port with significant refactoring

| Original | New | LOC | Notes |
|----------|-----|-----|-------|
| placement.stk | placement.scm | 644 | Convex hull, placement near existing objects, scrolling. Core algorithms are pure math. Remove `scroll-canvas-if-neccesary` Tk calls; replace with viewport-update callback. |
| view-profiles.stk | profiles.scm | 299 | Profile computation and `build-tree`. The tree-building algorithm is deeply intertwined with Tk canvas item creation (`make <viewed-cell>`, `make <null-object>`, etc.). Refactor to produce scene graph nodes instead. |
| view-pointers.stk | pointers.scm | 222 | Cell pointer routing, car/cdr pointer creation. Replace `make <line>` with scene graph line nodes. |
| env-pointers.stk | env-pointers.scm | 368 | Environment pointer routing (rectangle-to-rectangle). Geometry is pure; pointer creation needs scene graph adaptation. |
| simple-pointer.stk | simple-pointer.scm | 123 | Base pointer class. Replace class with record type. |

### GUI shell — rewrite entirely

| Original | New | LOC | Notes |
|----------|-----|-----|-------|
| view-toplev.stk | (web-ui.scm) | 285 | Tk toplevel window, menus, scrollbars, mouse bindings. Replaced entirely by HTML/CSS + Hoot FFI DOM calls. |
| env-toplev.stk | (web-ui.scm) | 226 | EnvDraw toplevel with step/continue buttons, listbox trace. Replaced by HTML UI. |
| view-classes.stk | scene-graph.scm | 238 | `<viewed-cell>`, `<viewed-object>`, `<null-object>`. Replace STklos classes with `define-record-type`. |
| env-classes.stk | env-scene.scm | 430 | `<procedure-object>`, `<frame-object>`, `<binding-object>`. Replace with records + scene graph node constructors. |
| move-composite.stk | drag.scm | 371 | `<Tk-moveable-composite-item>`, drag-and-drop, canvas groups. Rewrite using Canvas2D hit-testing + scene graph tree walking. |
| view-updates.stk | updates.scm | 325 | `set-car!`/`set-cdr!` mutation tracking, GC visualization, `set!` symbol rebinding. Logic is mostly portable; widget calls need scene graph adaptation. |
| view-misc.stk | (util.scm) | 194 | Text measurement, print-canvas, `lower`/`raise`. Replace with Canvas2D `measureText` via FFI. |
| view.stk | view.scm | 242 | Entry point, config constants, `view` macro. Refactor: config becomes parameters module; `view` calls scene graph builder. |
| view-debug.stk | (remove) | 28 | Mouse coordinate display for debugging. Trivial to recreate. |

---

## Step-by-Step Plan

### Step 0: Development Environment Setup

**0.1** Install GNU Guix (the package manager).
Hoot's build environment is Guix-based. On macOS, this means either:
- A Guix install inside a Linux VM or container (Docker), or
- Using a remote Linux machine with Guix.

Guix does not run natively on macOS. The recommended setup:
```
# Option A: Docker container with Guix
docker pull guix/guix
# Option B: Linux VM (UTM/Parallels) with Guix system
```

**0.2** Install Guile 3.0.10+ and Hoot 0.7.0.
```
guix shell guile guile-hoot
# verify:
guile -c '(use-modules (hoot compile)) (display "Hoot OK\n")'
```

**0.3** Create project directory structure.
```
envdraw-web/
├── src/
│   ├── core/           # metacircular evaluator (platform-independent)
│   │   ├── meta.scm
│   │   ├── environments.scm
│   │   ├── stacks.scm
│   │   └── eval-observer.scm
│   ├── model/          # scene graph, layout, geometry
│   │   ├── scene-graph.scm
│   │   ├── profiles.scm
│   │   ├── placement.scm
│   │   ├── pointers.scm
│   │   ├── math.scm
│   │   └── color.scm
│   ├── render/         # Canvas2D rendering via FFI
│   │   ├── canvas-ffi.scm
│   │   ├── renderer.scm
│   │   └── text-measure.scm
│   ├── ui/             # DOM-based UI via FFI
│   │   ├── dom-ffi.scm
│   │   ├── web-ui.scm
│   │   └── repl.scm
│   └── main.scm        # entry point
├── web/
│   ├── index.html
│   ├── style.css
│   ├── boot.js          # JS bootstrap (loads Wasm, provides FFI imports)
│   └── reflect.js       # Hoot's JS runtime (copied from Hoot)
├── build.sh             # compilation script
├── guix.scm             # Guix manifest
└── README.md
```

**0.4** Create a build script that compiles `main.scm` → `envdraw.wasm`.
```scheme
;; build.scm — run with: guile build.scm
(use-modules (hoot compile) (hoot reflect))
(compile-file "src/main.scm"
              #:output "web/envdraw.wasm")
```

**0.5** Create a minimal "hello world" that proves the toolchain works:
- A Scheme file that uses `define-foreign` to call `console.log`
- An HTML file that loads the Wasm with `reflect.js`
- Confirm it runs in Chrome/Firefox

**0.6** Set up a local development web server.
```scheme
;; serve.scm — simple file server for testing
;; or use: python3 -m http.server 8080 --directory web/
```

**Deliverable:** A working build pipeline — edit .scm, run build,
refresh browser, see output.

---

### Step 1: Port Data Structures (stacks, math, color)

**1.1** Port `stacks.stk` → `src/core/stacks.scm`.

Replace the STklos `<stack>` class:
```scheme
;; OLD (STklos):
(define-class <stack> ()
  ((l :initform '() :init-keyword :s)))
(define-method push ((self <stack>) it) ...)
(define-method pop ((self <stack>)) ...)

;; NEW (R7RS):
(define-record-type <stack>
  (%make-stack items)
  stack?
  (items stack-items set-stack-items!))

(define (make-stack) (%make-stack '()))
(define (stack-push! s it) (set-stack-items! s (cons it (stack-items s))))
(define (stack-pop! s)
  (let ((items (stack-items s)))
    (set-stack-items! s (cdr items))
    (car items)))
(define (stack-empty! s) (set-stack-items! s '()))
(define (stack-empty? s) (null? (stack-items s)))
(define (stack->list s) (stack-items s))
(define (stack-copy s) (%make-stack (append (stack-items s) '())))
```

Similarly replace `<dll>` (doubly-linked list) with a record type.

**1.2** Port `math.stk` → `src/model/math.scm`.

The original redefines `+`, `-`, `*` using `define-generic`/`define-method`
for polymorphic dispatch over numbers, lists, and vectors. Hoot has no
GOOPS. Replace with explicit dispatch:
```scheme
(define (vec+ a b)
  (cond ((and (number? a) (number? b)) (+ a b))
        ((and (pair? a) (pair? b)) (map vec+ a b))
        ;; vector cases...
        ))
```
Decision: The original overloads `+`/`-`/`*` globally. In the new code,
use explicit `vec+`, `vec-`, `vec*` names to avoid confusion and keep
standard arithmetic available.

**1.3** Port `color.stk` → `src/model/color.scm`.

Replace `make-color` (which was just `list`), keep `asHex`, `darken-color`,
`lighten-color`. Remove `widget-color`/`set-widget-color!` (Tk-specific).
```scheme
(define-record-type <color>
  (make-color r g b)
  color?
  (r color-r) (g color-g) (b color-b))

(define (color->css c)
  (string-append "rgb(" (number->string (color-r c)) ","
                 (number->string (color-g c)) ","
                 (number->string (color-b c)) ")"))
```

**Deliverable:** Three standalone .scm files that compile under Hoot.
Write unit tests using Hoot's built-in Wasm interpreter.

---

### Step 2: Define the Observer Interface

**2.1** Design `src/core/eval-observer.scm`.

This is the critical architectural seam that decouples the evaluator
from the rendering. In the original, the evaluator directly calls Tk
widget constructors (e.g., `make <frame-object>`, `make <procedure-object>`).
In the new design, the evaluator calls observers which the UI layer implements.

```scheme
(define-record-type <eval-observer>
  (make-eval-observer
   on-frame-created       ; (env-name parent-env-name width height) → frame-id
   on-binding-placed      ; (frame-id var-name value value-type) → void
   on-binding-updated     ; (frame-id var-name new-value value-type) → void
   on-procedure-created   ; (lambda-text frame-id) → proc-id
   on-env-pointer         ; (child-frame-id parent-frame-id) → void
   on-before-eval         ; (expr env-name indent-level) → void
   on-after-eval          ; (result indent-level) → void
   on-reduce              ; (indent-level) → void
   on-wait-for-step       ; (message) → continuation (async)
   on-gc-mark             ; (object-id) → void
   on-gc-sweep            ; (object-id) → void
   )
  eval-observer?
  (on-frame-created      observer-on-frame-created)
  (on-binding-placed     observer-on-binding-placed)
  (on-binding-updated    observer-on-binding-updated)
  (on-procedure-created  observer-on-procedure-created)
  (on-env-pointer        observer-on-env-pointer)
  (on-before-eval        observer-on-before-eval)
  (on-after-eval         observer-on-after-eval)
  (on-reduce             observer-on-reduce)
  (on-wait-for-step      observer-on-wait-for-step)
  (on-gc-mark            observer-on-gc-mark)
  (on-gc-sweep           observer-on-gc-sweep))
```

The metacircular evaluator receives the observer as a parameter and
calls these hooks instead of directly manipulating Tk widgets.

**Deliverable:** The observer record type definition.

---

### Step 3: Port the Metacircular Evaluator

This is the heart of the project. The goal is to preserve every bit
of the evaluator logic — including Max Hailperin's tail-recursion
changes — while replacing all Tk entanglements.

**3.1** Port `meta.stk` → `src/core/meta.scm` — Core eval/apply.

Preserve intact:
- `view-eval` dispatch (self-evaluating, variable, operation)
- `view-apply` (continuation, primitive, compound)
- `before-eval`, `after-eval`, `reduce` — the indentation protocol
- All special form evaluators: `eval-if`, `eval-cond`, `eval-let`,
  `eval-let*`, `eval-and`, `eval-or`, `eval-sequence`, `eval-definition`,
  `eval-assignment`
- `viewed-rep`, `viewable-pair?`, representation predicates
- `make-view-continuation`, `view-call/cc`
- Special form definitions and predicates

Replace:
- `(make <stack>)` → `(make-stack)` (from step 1)
- `(write-to-listbox s)` → `((observer-on-before-eval obs) ...)`
  and similar observer calls
- `(wait-for-confirmation ...)` which uses `tkwait` → observer
  callback `on-wait-for-step` that returns a promise/continuation.
  This is the trickiest change. Options:
  - **Option A:** Use Hoot's fibers/promises for async stepping
  - **Option B:** CPS-transform the evaluator so stepping yields control
  - **Option C:** Run the evaluator in a Web Worker, use `Atomics.wait`

  Recommended: **Option A** — Hoot 0.7.0 supports fibers and promises.
  The evaluator suspends on a channel; the UI posts to the channel
  when the user clicks Step/Continue.
  ```scheme
  (define step-channel (make-channel))

  (define (wait-for-step message)
    ((observer-on-wait-for-step obs) message)
    (get-message step-channel))  ; suspends fiber

  ;; UI side:
  (define (user-clicked-step)
    (put-message step-channel 'step))
  ```

- `(make <procedure-object> ...)` inside `make-procedure` →
  `((observer-on-procedure-created obs) lambda-text frame-id)`
- `(make <frame-object> ...)` inside `make-frame` →
  `((observer-on-frame-created obs) ...)`
- `(format #f ...)` → direct `string-append` or a portable format
  shim (Hoot supports `(ice-9 format)` only partially — verify)

- `define-macro` → `define-syntax` with `syntax-rules` or
  `syntax-case` (Hoot supports `syntax-rules`)

- `provide`/`provided?`/`require`/`unless (provided? ...)` module
  guards → Guile `define-module`/`use-modules` or remove entirely
  (whole-program compilation eliminates the need)

**3.2** Port `environments.scm` — Environment/frame/binding manipulation.

Preserve intact:
- `binding-in-env`, `set-variable-value!`, `define-variable!`
- `extend-environment`, `make-frame`, `make-binding`
- Frame/binding selectors (`first-frame`, `rest-frames`,
  `binding-variable`, `binding-value`, etc.)

Replace:
- `<binding-object>` class → `define-record-type`
  ```scheme
  (define-record-type <binding-object>
    (make-binding-object binding frame var-widget val-widget ptr-widget)
    binding-object?
    (binding  binding-of)
    (frame    binding-frame)
    (var-widget  variable-widget-of  set-variable-widget!)
    (val-widget  value-widget-of     set-value-widget!)
    (ptr-widget  pointer-widget-of   set-pointer-widget!))
  ```
- `make <frame-object>` calls → observer callback
- `place-binding` → observer callback `on-binding-placed`
  with the binding's variable name, value, and type (procedure,
  pair, atom)
- `set-binding-value!` → calls observer `on-binding-updated`
- Remove `slot-ref`/`slot-set!` throughout

**3.3** Write a test harness for the evaluator.

Using Hoot's built-in Wasm interpreter, test the evaluator in
isolation with a no-op observer (all callbacks are identity/void):
```scheme
(define null-observer
  (make-eval-observer
   (lambda args 'frame-0)    ; on-frame-created
   (lambda args (void))      ; on-binding-placed
   ...))

;; Test: (+ 1 2) should return 3
;; Test: (define (square x) (* x x)) then (square 5) → 25
;; Test: factorial-iter shows proper tail recursion (no stack growth)
```

**Deliverable:** `meta.scm` + `environments.scm` that compile under
Hoot and pass basic evaluator tests with a null observer.

---

### Step 4: Define the Scene Graph

The original code uses Tk canvas items (`<oval>`, `<rectangle>`,
`<line>`, `<text-item>`) composed into `<Tk-moveable-composite-item>`
trees. We replace this entire object model with a simple retained-mode
scene graph made of records.

**4.1** Create `src/model/scene-graph.scm`.

```scheme
;; Every drawable thing is a <node>

(define-record-type <node>
  (make-node id type x y width height children props parent)
  node?
  (id       node-id)
  (type     node-type)       ; 'rect, 'oval, 'line, 'text, 'group
  (x        node-x        set-node-x!)
  (y        node-y        set-node-y!)
  (width    node-width    set-node-width!)
  (height   node-height   set-node-height!)
  (children node-children set-node-children!)
  (props    node-props    set-node-props!)   ; alist: fill, stroke, text, font, ...
  (parent   node-parent   set-node-parent!))

;; Composite nodes group children and move together

(define (make-group id x y)
  (make-node id 'group x y 0 0 '() '() #f))

(define (make-rect id x y w h fill)
  (make-node id 'rect x y w h '()
             `((fill . ,fill)) #f))

(define (make-oval-node id x y w h fill)
  (make-node id 'oval x y w h '()
             `((fill . ,fill)) #f))

(define (make-line-node id points stroke width arrow)
  (make-node id 'line 0 0 0 0 '()
             `((points . ,points) (stroke . ,stroke)
               (width . ,width) (arrow . ,arrow)) #f))

(define (make-text-node id x y text font anchor)
  (make-node id 'text x y 0 0 '()
             `((text . ,text) (font . ,font)
               (anchor . ,anchor)) #f))

(define (node-add-child! parent child)
  (set-node-children! parent
    (append (node-children parent) (list child)))
  (set-node-parent! child parent))

;; Move a node and all descendants by dx, dy
(define (node-translate! node dx dy)
  (set-node-x! node (+ (node-x node) dx))
  (set-node-y! node (+ (node-y node) dy)))

;; Absolute position (sum of all ancestor translations)
(define (node-absolute-x node)
  (if (node-parent node)
      (+ (node-x node) (node-absolute-x (node-parent node)))
      (node-x node)))
(define (node-absolute-y node)
  (if (node-parent node)
      (+ (node-y node) (node-absolute-y (node-parent node)))
      (node-y node)))
```

**4.2** Define diagram-specific node constructors.

These replace the STklos class initializers:

- `make-cons-cell-node` → two rectangles (car half, cdr half) + child
  pointers. Replaces `<viewed-cell>` initialize-item.
- `make-procedure-node` → two ovals + text labels for args/body + pointer
  to frame. Replaces `<procedure-object>` initialize-item.
- `make-frame-node` → rectangle + name text + insertion point tracker.
  Replaces `<frame-object>` initialize-item.
- `make-atom-node` → text item. Replaces `<viewed-object>` initialize-item.
- `make-null-node` → diagonal slash line. Replaces `<null-object>`.
- `make-pointer-node` → polyline with arrowhead. Replaces `<simple-pointer>`.

**4.3** Port the profile/layout system from `view-profiles.stk`.

The `add-profiles` function and `build-tree` function are the heart of
layout. `add-profiles` is pure computation — port directly.

`build-tree` currently creates Tk widgets inline. Refactor it to
create scene graph nodes instead:
```scheme
;; OLD: (make <viewed-cell> :parent canvas :coords '(0 0) ...)
;; NEW: (make-cons-cell-node (gensym "vc") 0 0 car-child cdr-child color)
```

The hash table for deduplication (`(hash-table-get ht scheme-obj #f)`)
stays — it now maps Scheme objects to scene graph node IDs.

**4.4** Port pointer routing algorithms.

From `env-pointers.stk`: `find-env-pointer`, `env-merge`,
`check-overlap`, `find-straight-x-pointer`, `find-straight-y-pointer`,
`find-bent-pointer` — these are pure geometry on rectangles.
Port directly with only name changes.

From `view-pointers.stk`: `cell-move-head`, `make-car-pointer`,
`make-cdr-pointer`, `add-car-pointer`, `add-cdr-pointer` — replace
`make <line>` with `make-line-node`.

**4.5** Port `placement.stk` — the convex-hull placement engine.

This file is 644 lines of pure geometry plus a few `scroll-canvas`
calls. The core algorithms:
- `place-new-widget` — finds open space for a new node
- Convex hull computation
- Point/rectangle operations (already in the file)

Port the geometry directly. Replace `scroll-canvas-if-neccesary`
with a viewport-update observer call.

**Deliverable:** A scene graph module that can construct a complete
diagram data structure for a given set of evaluator events. Testable
without a browser — walk the tree, verify node positions.

---

### Step 5: Canvas Renderer

**5.1** Define Canvas2D FFI bindings in `src/render/canvas-ffi.scm`.

```scheme
(define-foreign %get-canvas "canvas" "getCanvas"
  -> (ref null extern))

(define-foreign %get-context "canvas" "getContext"
  (ref null extern) (ref string) -> (ref null extern))

(define-foreign %set-fill-style "ctx" "setFillStyle"
  (ref null extern) (ref string) -> none)

(define-foreign %set-stroke-style "ctx" "setStrokeStyle"
  (ref null extern) (ref string) -> none)

(define-foreign %set-line-width "ctx" "setLineWidth"
  (ref null extern) f64 -> none)

(define-foreign %fill-rect "ctx" "fillRect"
  (ref null extern) f64 f64 f64 f64 -> none)

(define-foreign %stroke-rect "ctx" "strokeRect"
  (ref null extern) f64 f64 f64 f64 -> none)

(define-foreign %clear-rect "ctx" "clearRect"
  (ref null extern) f64 f64 f64 f64 -> none)

(define-foreign %begin-path "ctx" "beginPath"
  (ref null extern) -> none)

(define-foreign %move-to "ctx" "moveTo"
  (ref null extern) f64 f64 -> none)

(define-foreign %line-to "ctx" "lineTo"
  (ref null extern) f64 f64 -> none)

(define-foreign %arc "ctx" "arc"
  (ref null extern) f64 f64 f64 f64 f64 -> none)

(define-foreign %stroke "ctx" "stroke"
  (ref null extern) -> none)

(define-foreign %fill "ctx" "fill"
  (ref null extern) -> none)

(define-foreign %fill-text "ctx" "fillText"
  (ref null extern) (ref string) f64 f64 -> none)

(define-foreign %set-font "ctx" "setFont"
  (ref null extern) (ref string) -> none)

(define-foreign %measure-text "ctx" "measureText"
  (ref null extern) (ref string) -> f64)

(define-foreign %save "ctx" "save"
  (ref null extern) -> none)

(define-foreign %restore "ctx" "restore"
  (ref null extern) -> none)

(define-foreign %translate "ctx" "translate"
  (ref null extern) f64 f64 -> none)

(define-foreign %scale-ctx "ctx" "scale"
  (ref null extern) f64 f64 -> none)
```

**5.2** Write the JS-side FFI implementations in `boot.js`.

```javascript
const imports = {
  canvas: {
    getCanvas() { return document.getElementById("diagram-canvas"); },
    getContext(canvas, type) { return canvas.getContext(type); },
  },
  ctx: {
    setFillStyle(ctx, style) { ctx.fillStyle = style; },
    setStrokeStyle(ctx, style) { ctx.strokeStyle = style; },
    setLineWidth(ctx, w) { ctx.lineWidth = w; },
    fillRect(ctx, x, y, w, h) { ctx.fillRect(x, y, w, h); },
    strokeRect(ctx, x, y, w, h) { ctx.strokeRect(x, y, w, h); },
    clearRect(ctx, x, y, w, h) { ctx.clearRect(x, y, w, h); },
    beginPath(ctx) { ctx.beginPath(); },
    moveTo(ctx, x, y) { ctx.moveTo(x, y); },
    lineTo(ctx, x, y) { ctx.lineTo(x, y); },
    arc(ctx, x, y, r, s, e) { ctx.arc(x, y, r, s, e); },
    stroke(ctx) { ctx.stroke(); },
    fill(ctx) { ctx.fill(); },
    fillText(ctx, text, x, y) { ctx.fillText(text, x, y); },
    setFont(ctx, font) { ctx.font = font; },
    measureText(ctx, text) { return ctx.measureText(text).width; },
    save(ctx) { ctx.save(); },
    restore(ctx) { ctx.restore(); },
    translate(ctx, x, y) { ctx.translate(x, y); },
    scale(ctx, sx, sy) { ctx.scale(sx, sy); },
  },
  // ... DOM imports for UI ...
};
```

**5.3** Implement the scene graph renderer in `src/render/renderer.scm`.

```scheme
(define (render-scene ctx root-node camera-x camera-y zoom)
  ;; Clear canvas
  (%clear-rect ctx 0 0 canvas-width canvas-height)
  ;; Apply camera transform
  (%save ctx)
  (%scale-ctx ctx zoom zoom)
  (%translate ctx (- camera-x) (- camera-y))
  ;; Walk scene graph depth-first
  (render-node ctx root-node)
  (%restore ctx))

(define (render-node ctx node)
  (let ((ax (node-absolute-x node))
        (ay (node-absolute-y node)))
    (case (node-type node)
      ((rect)
       (%set-fill-style ctx (assoc-ref (node-props node) 'fill))
       (%fill-rect ctx ax ay (node-width node) (node-height node))
       (%stroke-rect ctx ax ay (node-width node) (node-height node)))
      ((oval)
       (%begin-path ctx)
       (%arc ctx (+ ax (/ (node-width node) 2))
                 (+ ay (/ (node-height node) 2))
                 (/ (node-width node) 2) 0 (* 2 3.14159))
       (%set-fill-style ctx (assoc-ref (node-props node) 'fill))
       (%fill ctx)
       (%stroke ctx))
      ((line)
       (let ((points (assoc-ref (node-props node) 'points)))
         (%set-stroke-style ctx (assoc-ref (node-props node) 'stroke))
         (%set-line-width ctx (assoc-ref (node-props node) 'width))
         (%begin-path ctx)
         (%move-to ctx (car (car points)) (cadr (car points)))
         (for-each (lambda (p) (%line-to ctx (car p) (cadr p)))
                   (cdr points))
         (%stroke ctx)
         ;; Draw arrowhead if specified
         ))
      ((text)
       (%set-font ctx (or (assoc-ref (node-props node) 'font) "14px monospace"))
       (%set-fill-style ctx "black")
       (%fill-text ctx (assoc-ref (node-props node) 'text) ax ay))
      ((group)
       ;; Groups just contain children
       (void)))
    ;; Render children
    (for-each (lambda (child) (render-node ctx child))
              (node-children node))))
```

**5.4** Implement text measurement.

The original uses `text-width` and `text-height` extensively for layout.
These must work BEFORE rendering (during layout computation). Use a
hidden canvas context for measurement:
```scheme
(define measure-ctx #f)

(define (init-text-measurement!)
  (set! measure-ctx (%get-context (%get-canvas) "2d"))
  (%set-font measure-ctx "14px monospace"))

(define (text-width str)
  (%measure-text measure-ctx str))

(define (text-height font)
  14)  ; Canvas2D doesn't give height directly; use font-size
```

**Deliverable:** A renderer that can take a scene graph and draw it
on an HTML5 Canvas, including rectangles, ovals, lines with arrows,
and text.

---

### Step 6: Implement the Drag System

The original `move-composite.stk` (371 lines) implements a composite
widget system with parent/child relationships and motion hooks.
This needs reimplementation for Canvas2D.

**6.1** Implement hit testing.

Canvas2D doesn't have built-in hit testing like Tk canvas items.
Options:
- Walk the scene graph and test point-in-rectangle/point-in-oval
- Use a secondary "pick canvas" with unique colors per object
- Use Canvas2D `isPointInPath` (requires re-drawing paths)

Recommended: Scene graph walk with bounding-box checks. The diagram
consists of simple rectangles, ovals, and lines — geometric hit
testing is straightforward.

```scheme
(define (hit-test root-node x y)
  ;; Returns the deepest node at (x, y), or #f
  (let loop ((nodes (reverse (node-children root-node))))
    (cond ((null? nodes) #f)
          ((point-in-node? (car nodes) x y)
           (or (hit-test (car nodes) x y) (car nodes)))
          (else (loop (cdr nodes))))))
```

**6.2** Implement drag-and-drop.

Bind mousedown/mousemove/mouseup on the canvas element (via FFI).
On mousedown, hit-test to find which node group is under the cursor.
On mousemove, translate the selected group's root node by the delta.
Re-render after each move.

The original had two drag modes:
- Button-1: move node + all children
- Button-2: move only the node (single-motion)

Replicate both (e.g., left-click = group move, shift+click = solo move).

**6.3** Port motion hooks.

The original's `notify-of-movement` calls a list of functions on each
widget when it moves. These functions update pointer coordinates.
In the new system, after moving a node, walk its pointer list and
call the corresponding pointer-update function to recompute the line
endpoints.

**Deliverable:** Diagram objects can be dragged around the canvas,
and pointers follow their connected nodes.

---

### Step 7: Build the Web UI

**7.1** Create `web/index.html`.

```html
<!DOCTYPE html>
<html>
<head>
  <title>EnvDraw</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div id="app">
    <div id="toolbar">
      <button id="btn-step">Step</button>
      <button id="btn-continue">Continue</button>
      <label><input type="checkbox" id="chk-stepping"> Stepping</label>
      <button id="btn-gc">GC</button>
      <span id="object-label"></span>
    </div>
    <div id="main-area">
      <div id="trace-panel">
        <div id="trace-output"></div>
      </div>
      <canvas id="diagram-canvas" width="2000" height="2000"></canvas>
    </div>
    <div id="repl-area">
      <span class="prompt">EnvDraw&gt;</span>
      <input type="text" id="repl-input" autofocus>
    </div>
  </div>
  <script src="reflect.js"></script>
  <script src="boot.js"></script>
</body>
</html>
```

**7.2** Define DOM FFI bindings in `src/ui/dom-ffi.scm`.

```scheme
(define-foreign %get-element-by-id "document" "getElementById"
  (ref string) -> (ref null extern))
(define-foreign %set-inner-text "element" "setInnerText"
  (ref null extern) (ref string) -> none)
(define-foreign %add-event-listener "element" "addEventListener"
  (ref null extern) (ref string) (ref null extern) -> none)
(define-foreign %get-value "element" "getValue"
  (ref null extern) -> (ref string))
(define-foreign %set-value "element" "setValue"
  (ref null extern) (ref string) -> none)
(define-foreign %append-child "element" "appendChild"
  (ref null extern) (ref null extern) -> (ref null extern))
(define-foreign %create-element "document" "createElement"
  (ref string) -> (ref null extern))
(define-foreign %create-text-node "document" "createTextNode"
  (ref string) -> (ref null extern))
(define-foreign %scroll-to-bottom "element" "scrollToBottom"
  (ref null extern) -> none)
```

**7.3** Implement the REPL in `src/ui/repl.scm`.

```scheme
(define (setup-repl)
  (let ((input (%get-element-by-id "repl-input")))
    (%add-event-listener input "keydown"
      (procedure->external
        (lambda (event)
          ;; Check if Enter key
          (when (enter-key? event)
            (let ((text (%get-value input)))
              (%set-value input "")
              (eval-in-meta text))))))))

(define (eval-in-meta text)
  ;; Parse text as Scheme expression
  ;; Call view-eval with the parsed expression
  ;; Display result in trace panel
  ;; Re-render canvas
  )
```

**7.4** Implement the trace panel.

Replace `write-to-listbox` with appending text to a DOM element:
```scheme
(define (write-to-trace s)
  (let* ((panel (%get-element-by-id "trace-output"))
         (line (%create-element "div"))
         (text (%create-text-node s)))
    (%append-child line text)
    (%append-child panel line)
    (%scroll-to-bottom panel)))
```

**7.5** Implement stepping/continue buttons.

Using Hoot fibers, the evaluator's `wait-for-step` suspends a fiber.
The Step/Continue buttons post a message to the evaluator's channel:
```scheme
(define eval-channel (make-channel))

(%add-event-listener (%get-element-by-id "btn-step") "click"
  (procedure->external
    (lambda (event) (put-message eval-channel 'step))))

(%add-event-listener (%get-element-by-id "btn-continue") "click"
  (procedure->external
    (lambda (event) (put-message eval-channel 'continue))))
```

**7.6** Implement the object inspector.

On mousemove over the canvas, hit-test and display the `viewed-rep`
of the object under the cursor in the `#object-label` span. This
replaces the Tk `<Enter>` binding + label widget.

**7.7** Implement canvas pan/zoom.

- Mouse wheel → zoom (`camera-zoom` variable, re-render)
- Click-drag on empty canvas space → pan (`camera-x`, `camera-y`)
- The original used scrollbars; we use direct canvas interaction

**Deliverable:** A complete web UI with REPL input, trace output,
stepping controls, and interactive canvas.

---

### Step 8: Wire Everything Together

**8.1** Implement the concrete observer.

This is the glue layer. When `meta.scm` calls an observer hook, the
concrete observer:
1. Creates a scene graph node
2. Places it using the placement engine
3. Triggers a re-render

```scheme
(define (make-web-observer scene-root)
  (make-eval-observer
   ;; on-frame-created
   (lambda (env-name parent-name width height)
     (let ((frame (make-frame-node (gensym "f") 0 0 width height
                                   env-name (current-color))))
       (place-node frame scene-root)
       (request-render!)
       frame))
   ;; on-binding-placed
   (lambda (frame var val val-type)
     (add-binding-to-frame-node frame var val val-type)
     (request-render!))
   ;; on-procedure-created
   (lambda (lambda-text frame-id)
     (let ((proc (make-procedure-node (gensym "p") 0 0
                                      lambda-text frame-id
                                      (current-color))))
       (place-node proc scene-root)
       (request-render!)
       proc))
   ;; on-before-eval
   (lambda (expr env-name indent)
     (write-to-trace
       (string-append (make-string indent #\space)
                      "EVAL in " env-name ": " expr)))
   ;; on-after-eval
   (lambda (result indent)
     (write-to-trace
       (string-append (make-string indent #\space)
                      "RETURNING: " result)))
   ;; ... etc
   ))
```

**8.2** Implement `main.scm` — the entry point.

```scheme
;; main.scm — compiled to envdraw.wasm

(include "core/stacks.scm")
(include "core/eval-observer.scm")
(include "model/math.scm")
(include "model/color.scm")
(include "model/scene-graph.scm")
(include "model/profiles.scm")
(include "model/placement.scm")
(include "model/pointers.scm")
(include "render/canvas-ffi.scm")
(include "render/renderer.scm")
(include "render/text-measure.scm")
(include "ui/dom-ffi.scm")
(include "ui/web-ui.scm")
(include "ui/repl.scm")
(include "core/environments.scm")
(include "core/meta.scm")

;; Initialize
(define scene-root (make-group "root" 0 0))
(define obs (make-web-observer scene-root))
(init-text-measurement!)
(setup-repl)
(setup-canvas-events)
;; Start the evaluator fiber
(spawn-fiber
  (lambda ()
    (envdraw obs)))
```

**8.3** Implement the render loop.

Use `requestAnimationFrame` via FFI for smooth rendering:
```scheme
(define render-pending? #f)

(define (request-render!)
  (unless render-pending?
    (set! render-pending? #t)
    (%request-animation-frame
      (procedure->external
        (lambda (timestamp)
          (set! render-pending? #f)
          (render-scene ctx scene-root camera-x camera-y camera-zoom))))))
```

**Deliverable:** A working EnvDraw in the browser. User types
`(define (square x) (* x x))`, the global environment frame appears
with `square` bound to a procedure, the procedure object points to
the global frame.

---

### Step 9: Port Mutation Visualization

**9.1** Port `set-car!`/`set-cdr!` tracking from `view-updates.stk`.

The original redefines `set-car!` and `set-cdr!` so mutations on
viewed objects update the diagram. In the meta-evaluator, we
intercept these at the evaluator level — when the user's code calls
`set-car!`, the evaluator:
1. Performs the mutation on the internal data structure
2. Calls an observer hook
3. The observer updates the scene graph (removes old pointer, adds new)
4. Re-renders

**9.2** Port `set!` / symbol rebinding visualization.

The original's `adjust-symbol-bindings` tracks when a `define`'d symbol
changes value and visually moves the symbol pointer to the new object.
Port this logic through the `on-binding-updated` observer.

**9.3** Port GC visualization.

The original has two GC modes:
- **Automatic:** garbage objects are immediately deleted
- **Manual:** garbage objects are stippled (translucent), clicking
  deletes them

In the browser version:
- Stipple → reduce opacity to 0.3 or use dashed outlines
- Right-click on garbage → delete from scene graph
- The DFS traversal in `gc-view` is pure logic — port directly

**Deliverable:** Complete mutation and GC visualization.

---

### Step 10: Port the Box-and-Pointer Viewer (`view`)

The `view` command works independently from `envdraw` — it diagrams
arbitrary Scheme data structures. It's simpler (no evaluator, no
environments).

**10.1** Port `view` as a standalone function.

In the new code, `view` takes a Scheme object and a symbol name,
creates a scene graph for it using `build-tree`, places it, and
renders. It's the same render pipeline minus the evaluator.

**10.2** Support `(view l)` at the REPL.

Inside the meta-evaluator, bind `view` as a primitive that calls
the box-and-pointer viewer on the user's data.

**Deliverable:** `(define l (list 1 2 3))` then `(view l)` draws a
box-and-pointer diagram.

---

### Step 11: Polish and Deploy

**11.1** Visual polish.
- Color palette matching the original (PaleGreen, LemonChiffon, etc.)
- Proper arrowheads on lines (Canvas2D requires manual triangle drawing)
- Font selection (monospace for code, proportional for labels)
- Smooth animation for node placement (optional, use `requestAnimationFrame`)

**11.2** Canvas export.
- "Print" button → export canvas as PNG (`canvas.toDataURL()`)
- Optional: export as SVG (walk scene graph, emit SVG elements)

**11.3** Responsive layout.
- Canvas fills available space
- Trace panel is resizable (drag handle)
- Mobile-friendly touch events for pan/zoom

**11.4** Help/documentation.
- Port the HTML help files from `Help/` directory
- Add inline tooltips for buttons
- Link to the Berkeley CS61A textbook page

**11.5** Deployment.
The entire application is static files:
```
envdraw.wasm    (~100-300 KB gzipped, estimate)
reflect.js      (~30 KB)
boot.js         (~5 KB)
index.html      (~2 KB)
style.css       (~2 KB)
```
Host on GitHub Pages, Netlify, or any static file server.
No backend required.

**11.6** Testing.
- Port test cases from `test/envtest.stk` and `test/viewtest.stk`
- Automated visual regression tests (screenshot comparison)
- Cross-browser testing (Chrome, Firefox, Safari — all support Wasm GC)

---

## Risk Mitigation Checklist

| # | Risk | Check |
|---|------|-------|
| 1 | Hoot doesn't support a needed Scheme feature | Test each feature in isolation before deep porting: `call/cc`, `define-syntax`, `hash-table`, `format`, dynamic `eval`. |
| 2 | `eval` in Wasm is too slow | Benchmark early. The evaluator processes one expression at a time interactively — latency matters more than throughput. |
| 3 | Fibers don't work for stepping | Have a fallback: CPS-transform the evaluator, or use `call/cc` to suspend/resume. |
| 4 | Text measurement before rendering | Initialize a hidden canvas context at startup; all `text-width` calls go through it. |
| 5 | Scene graph re-render is too slow | Only re-render dirty regions. Alternatively, use `OffscreenCanvas` in a Worker. For diagrams of typical classroom size (<100 objects), full re-render at 60fps should be fine. |
| 6 | Binary size too large | Use Hoot's tree-shaking (only used stdlib parts are included). Monitor .wasm size at each step. |
| 7 | Hoot API changes in future releases | Pin to v0.7.0. Wrap all Hoot-specific API calls in adapter modules. |

---

## Milestone Summary

| Milestone | Steps | Key Deliverable |
|-----------|-------|-----------------|
| M0: Toolchain works | 0.1–0.6 | "Hello World" in browser via Hoot |
| M1: Data structures compile | 1.1–1.3 | stacks, math, color under Hoot |
| M2: Evaluator runs headless | 2.1, 3.1–3.3 | `(+ 1 2)` → `3` in Wasm interpreter |
| M3: Scene graph renders | 4.1–4.5, 5.1–5.4 | Static diagram on Canvas |
| M4: Interactive diagrams | 6.1–6.3 | Draggable nodes with pointers |
| M5: Full web app | 7.1–7.7, 8.1–8.3 | REPL → eval → diagram in browser |
| M6: Feature parity | 9.1–9.3, 10.1–10.2 | Mutation, GC, `view` command |
| M7: Ship it | 11.1–11.6 | Deployed, documented, tested |
