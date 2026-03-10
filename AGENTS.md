# Agent Instructions for EnvDraw

## Project overview

EnvDraw is a browser-based environment diagram visualizer for Scheme. Users
type Scheme expressions into a REPL and a force-directed SVG graph renders
frames, bindings, closures, and pair structures in real time — following the
SICP environment model of evaluation.

The evaluator is a metacircular Scheme interpreter compiled to WebAssembly
via [Guile Hoot](https://spritely.institute/hoot/). As it creates frames and
bindings, an observer emits FFI calls that JavaScript bridges to a
[D3.js](https://d3js.org/) force-directed graph.

**Live site:** <https://jmacd.github.io/envdraw/>

## Architecture

```
Browser
├── index.html              Loads D3 v7 (CDN), reflect.js, d3-diagram.js, boot.js
├── boot.js                 Loads envdraw.wasm, wires REPL & toolbar, bridges FFI
├── d3-diagram.js           D3-force SVG rendering (frames, bindings, closures, pairs)
├── reflect.js              Guile Hoot WebAssembly runtime (DO NOT EDIT)
└── style.css

Scheme → WebAssembly (via Guile Hoot)
├── web/envdraw.scm         Entry point: FFI bindings, primitives, boot!
├── src/core/meta.scm       Metacircular evaluator (view-eval, view-apply)
├── src/core/environments.scm   Environment/frame/binding model
├── src/core/eval-observer.scm  Observer interface (decouples evaluator from UI)
├── src/core/stacks.scm         Stack and doubly-linked list structures
├── src/model/color.scm         RGB color utilities
└── src/ui/web-observer.scm     Emits D3 FFI calls for diagram updates
```

### Data flow

```
User types Scheme in REPL
  → boot.js eval handler calls Scheme callback
  → Evaluator (meta.scm) interprets, calls observer hooks
  → web-observer.scm emits FFI calls (d3-add-frame, etc.)
  → boot.js appImports receive FFI calls, queue D3 mutations (if stepping)
  → EnvDiagram updates force simulation → SVG re-renders
  → Trace output sent to trace panel via traceAppend FFI
```

### Compilation model

`web/envdraw.scm` is the single compilation unit. It uses `(include ...)`
to pull in `src/` files at compile time — there is no linking step. The
compiler is Guile Hoot (`guild compile-wasm`), producing `web/envdraw.wasm`.

**Include order matters:**

```scheme
web/envdraw.scm
  ├── (include "../src/core/stacks.scm")
  ├── (include "../src/model/color.scm")
  ├── (include "../src/core/eval-observer.scm")
  ├── (include "../src/ui/web-observer.scm")
  ├── (include "../src/core/environments.scm")
  └── (include "../src/core/meta.scm")       ← must be last (uses *host-eval*)
```

`meta.scm` references `*host-eval*` (the primitives table), defined in
`envdraw.scm` between the includes. The primitives table references
`user-print` and `user-display` from `web-observer.scm`, so the observer
must be included first.

### FFI boundary

Scheme declares FFI imports with `(define-foreign ...)` from the Hoot FFI
module. Each foreign function names a module and export:

```scheme
(define-foreign d3-add-frame "app" "d3AddFrame"
  (ref string) (ref string) (ref string) (ref string) -> none)
```

On the JS side, `boot.js` provides these as the `app` import object when
calling `Scheme.load_main()`. There are three FFI modules:

- **`app`** — callback registration, D3 graph mutations, trace output
- **`ctx`** — Canvas2D stubs (all no-ops, kept for Wasm import compatibility)
- **`dom`** — console.log, alert

### Stepping (record-and-replay)

The evaluator runs synchronously to completion. When stepping is active,
D3 mutations and trace output are queued as closures in `boot.js`. The
Scheme side calls `notify-step-boundary` at each `apply`, which finalizes a
step group. The user clicks Step to replay one group, or Continue to flush
all. This is entirely a JS-side mechanism — the Scheme callback returns
immediately.

## Building and running

### Prerequisites

| Tool | Version | Install (macOS) |
|------|---------|-----------------|
| Guile | 3.0.x | `brew install guile` |
| Guile Hoot | 0.6.1 | `brew install guile-hoot` |
| Python 3 | any | pre-installed on macOS |

You only need Guile + Hoot if you modify `.scm` files. For JS/CSS/HTML
changes, skip straight to `./build.sh serve`.

### Commands

```sh
./build.sh          # compile web/envdraw.wasm (~30s on M1)
./build.sh clean    # remove envdraw.wasm (keeps runtime .wasm files)
./build.sh serve    # start local dev server on http://localhost:8088/
```

The build runs:
```sh
guild compile-wasm -L web -L . -o web/envdraw.wasm web/envdraw.scm
```

### Edit → rebuild cycle

1. Edit `.scm` file(s) under `src/` or `web/envdraw.scm`
2. Run `./build.sh`
3. Hard-refresh the browser (Cmd+Shift+R)

For JS/CSS/HTML changes, just save and refresh.

`boot.js` is loaded with a cache-buster query param (`boot.js?v=N`). Bump
the version number in `index.html` if you change `boot.js` and want to
ensure clients pick up the new version without hard-refresh.

### Deployment

Pushes to `main` deploy `web/` to GitHub Pages via
`.github/workflows/deploy-pages.yml`. The workflow validates that 8 required
files exist (`index.html`, `boot.js`, `reflect.js`, `d3-diagram.js`,
`style.css`, `reflect.wasm`, `wtf8.wasm`, `envdraw.wasm`) then deploys.

There is no CI build step — the compiled `envdraw.wasm` must be committed
to the repo before pushing.

### Browser requirements

WebAssembly GC + tail calls: Chrome 119+ / Firefox 120+ / Safari 18.2+.

## Code conventions

### Scheme

- **Naming:** snake-case for functions and variables. `!` suffix for
  mutators, `?` suffix for predicates.
- **Globals:** ear-muff convention for special variables:
  `*current-observer*`, `*next-id*`, `*eval-indent-level*`.
- **Records:** defined with `define-record-type` (R7RS style) using angle
  brackets: `<eval-observer>`, `<frame-info>`, `<color>`, `<stack>`.
- **Observer pattern:** evaluator and environment code call observer hooks
  (e.g., `on-frame-created`, `on-binding-placed`), never D3 directly. This
  decouples evaluation from visualization.
- **Error handling:** standard Scheme `error` procedure. Errors caught at
  the top level in `boot!` eval handler.
- **No module system:** all code is `(include ...)`d into one compilation
  unit. Namespace discipline is by convention only.

### JavaScript

- **Naming:** camelCase for functions and variables. PascalCase for the
  `EnvDiagram` class.
- **No bundler:** plain ES5-style scripts loaded via `<script>` tags.
  `EnvDiagram` is a class defined as a global. No import/export statements.
- **DOM access:** direct `document.getElementById` / `querySelector`.
  No framework.
- **D3 patterns:** standard enter/update/exit with transitions. Force
  simulation with charge, collide, link, and positional forces.

### CSS

- **Custom properties** for all colors and dimensions (defined in `:root`).
- **Class-based** styling: `.tb-btn`, `.trace-line`, `.repl-log-line`.
- **Status classes:** `.status-ready`, `.status-busy`, `.status-error`,
  `.status-stepping`.

### HTML

- **Script loading order** in `index.html` matters:
  1. D3 v7 (CDN)
  2. `reflect.js` (defines global `Scheme`)
  3. `d3-diagram.js` (defines `EnvDiagram`)
  4. `boot.js` (loaded dynamically with cache-buster)

## File reference

### `web/envdraw.scm` — Hoot entry point (~470 lines)

Top-level compilation unit containing:

- R7RS compatibility shims (`inexact->exact`, `list-sort`)
- ~60 FFI declarations across `ctx`, `dom`, and `app` modules
- `(include ...)` directives for all `src/` modules
- Primitives table split into 10 small quasiquoted alists (workaround for
  Hoot quasiquote bug with >80 unquotes)
- `boot!` procedure — creates observer, registers callback handlers

Key functions: `*host-eval*` (primitive lookup), `boot!` (initialization).

### `web/boot.js` — JavaScript bootstrap (~600 lines)

Loads `envdraw.wasm`, provides all FFI import objects, wires REPL and
toolbar.

Key state objects:

- `callbacks` — stores 10 handler functions registered by Scheme
- `stepping` — record-and-replay state: `active`, `queueing`, `suspended`,
  `queue` (array of step groups), `currentOps` (accumulating closures)

Key functions: `schemeToString()` (Hoot value → JS string),
`finalizeCurrentStep()`, `flushStepQueue()`, `setStatus()`,
`hideEmptyState()`.

The FFI import functions (e.g., `d3AddFrame`, `traceAppend`) wrap their
work in closures when `stepping.queueing` is true, enabling step-by-step
replay.

### `web/d3-diagram.js` — D3 visualization (~1000 lines)

`EnvDiagram` class with methods: `addFrame`, `addProcedure`, `addBinding`,
`updateBinding`, `addPair`, `addPairEdge`, `addPairAtom`, `removeNode`,
`removeEdge`, `clear`, `fitToView`, `zoomBy`.

Data structures:

- `nodes` array: objects with `id`, `type` (frame|procedure|pair|pair-atom|
  pair-null), `name`, `parentId`, dimensions, color
- `edges` array: objects with `id`, `source`, `target`, `edgeType`
  (env|proc-env|binding|car|cdr)
- `bindings` map: frameId → array of `{varName, value, valueType, procId}`

Force simulation configuration:

- manyBody charge: -150
- collide: radius-based, strength 0.8
- link distance/strength varies by edge type
- Y-force for hierarchical layout (global frame at top)
- X-force to spread procedures right of their frame
- velocityDecay 0.7, alphaDecay 0.05

### `src/core/meta.scm` — Metacircular evaluator (~1000 lines)

SICP-style evaluator: `view-eval` / `view-apply`.

Supported forms: lambda, define, set!, if, cond, and, or, begin, let,
let\*, letrec, quote, quasiquote, eval, apply.

Key mechanisms:

- **Tail-call optimization:** `reduce` / `reduce-with-env` track the
  environment to GC on tail calls. `*frame-closures-count*` prevents TCO
  if closures captured the frame.
- **Source-line scanning:** `scan-lambda-lines` parses user input to tag
  procedures with REPL line numbers.
- **Tracing:** `before-eval` / `after-eval` print indented eval traces.
- **Step boundaries:** `wait-for-confirmation` calls observer's
  `on-wait-for-step` at each apply.

Globals: `the-global-environment`, `the-eval-stack`,
`*eval-indent-level*`, `*meta-observer*`, `*tail-call-env*`.

### `src/core/environments.scm` — Environment model (~286 lines)

First-class environment records with frames and bindings.

- Environments are lists of frames: `((frame-info . bindings) ...)`
- Bindings are 3-element lists: `(variable value binding-info)`
- `extend-environment` creates a new frame and calls observer hooks
- `define-variable!` / `set-variable-value!` update bindings and notify
  the observer
- `classify-value` returns `'procedure`, `'pair`, or `'atom`
- Frame width/height estimated from binding character counts (8px per char)

### `src/core/eval-observer.scm` — Observer interface (~178 lines)

`<eval-observer>` record with 15 callback fields:

1. `on-frame-created` → returns frame-id
2. `on-binding-placed` → returns binding-id
3. `on-binding-updated`
4. `on-procedure-created` → returns proc-id
5. `on-env-pointer`
6. `on-before-eval` / `on-after-eval` / `on-reduce`
7. `on-wait-for-step`
8. `on-write-trace` / `on-error`
9. `on-gc-mark` / `on-gc-sweep`
10. `on-request-render`
11. `on-tail-gc`

Also provides `make-null-observer` (no-ops for headless testing) and
`make-trace-observer` (prints eval trace to stdout).

### `src/ui/web-observer.scm` — D3 bridge (~500 lines)

Implements `<eval-observer>` to emit D3 FFI calls.

Key responsibilities:

- **ID generation:** `gen-id("f")` → "f0", "f1", ... for frames,
  procedures, pairs, atoms
- **Pair tree decomposition:** `build-pair-tree` recursively decomposes
  Scheme pairs into D3 cons-cell nodes with car/cdr edges. Detects shared
  structure via `eq?` lookup in `*pair-seen*`.
- **Pair mutation tracking:** `envdraw-set-car!` / `envdraw-set-cdr!` are
  instrumented wrappers that find affected pair trees, remove old nodes,
  and rebuild.
- **Color cycling:** assigns distinct colors from a 6-color palette
- **GC:** `handle-gc!` computes reachable node set and sweeps unreachable

Global state: `*frame-ids*`, `*proc-ids*`, `*pair-ids*`,
`*proc-frame-map*`, `*pair-seen*`, `*pair-tree-registry*`.

### `src/core/stacks.scm` — Data structures (~106 lines)

`<stack>` (LIFO) and `<dll>` (doubly-linked list). Used by the evaluator
for `the-eval-stack` (evaluation trace).

### `src/model/color.scm` — Color utilities (~91 lines)

`<color>` record with `r`, `g`, `b` fields. Conversion functions:
`color->hex`, `color->css`, `color->css-alpha`. Manipulation:
`complement-color`, `darken-color`, `lighten-color`. Default palette of 6
pastel colors.

### `web/reflect.js` — Hoot runtime (DO NOT EDIT)

Auto-generated by Guile Hoot. Defines the `Scheme` global with
`Scheme.load_main(wasmUrl, importObject)`. Updated only when upgrading Hoot.

### `web/index.html` — Application shell (~100 lines)

Toolbar, SVG canvas with zoom controls, empty-state overlay, resizable
trace panel, and REPL input/output area.

### `web/style.css` — Styling (~695 lines)

CSS custom properties, dark-themed REPL, light-themed diagram area,
responsive layout (trace panel floats on tablet), toolbar with toggle
switch, status indicator with pulse animation.

## Important gotchas

1. **Hoot quasiquote bug:** Hoot 0.6.1 crashes with "index out of bounds"
   when a single quasiquote has ~80+ unquotes. The primitives table in
   `envdraw.scm` is split into 10 small groups joined with `append`.

2. **Include order:** `meta.scm` must be included last because it
   references `*host-eval*`. The primitives table must come after
   `web-observer.scm` because it unquotes `user-print`/`user-display`.

3. **Canvas2D FFI stubs:** `envdraw.scm` declares Canvas2D FFI bindings
   (`ctx` module) that are wired to no-ops in `boot.js`. These exist for
   Wasm import compatibility. They can only be removed if the corresponding
   `define-foreign` declarations are also removed from `envdraw.scm`.

4. **Guile load paths:** `build.sh` hardcodes Homebrew paths
   (`/opt/homebrew/...`). Adjust if installed elsewhere.

5. **Hoot runtime files:** `reflect.wasm`, `wtf8.wasm`, and `reflect.js`
   come from the Hoot installation. Do not edit `reflect.js`. Only update
   these when upgrading Hoot versions.

6. **No automated tests.** Validation is limited to file-existence checks
   in the deploy workflow. Test changes manually with `./build.sh serve`.

7. **Cache-buster version:** bump the `?v=N` query param in `index.html`
   when changing `boot.js` to avoid stale cached versions.

8. **Script loading order:** `reflect.js` → `d3-diagram.js` → `boot.js`.
   `boot.js` depends on both `Scheme` (from reflect.js) and `EnvDiagram`
   (from d3-diagram.js) being defined as globals.

9. **Wasm must be committed:** CI does not build the Wasm. After modifying
   `.scm` files, run `./build.sh`, then commit both the `.scm` changes and
   the updated `web/envdraw.wasm`.

10. **Pair mutation tracking:** `set-car!` and `set-cdr!` are instrumented
    as `envdraw-set-car!` / `envdraw-set-cdr!` in the primitives table.
    These wrappers find all pair trees containing the mutated cell, remove
    old D3 nodes, and rebuild. Direct use of `set-car!`/`set-cdr!` from
    Scheme would bypass the diagram update.
