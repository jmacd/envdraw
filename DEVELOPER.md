# EnvDraw Developer Guide

## Repository layout

```
.
├── build.sh                     Build script (compile, clean, serve)
├── README.md                    User-facing project overview
├── DEVELOPER.md                 This file
├── .github/workflows/
│   └── deploy-pages.yml         GitHub Actions: validate + deploy to Pages
├── .gitignore
├── web/                         Deployable site (this whole dir goes to Pages)
│   ├── index.html               Single-page app shell
│   ├── boot.js                  JS bootstrap — loads Wasm, wires UI, bridges FFI
│   ├── d3-diagram.js            D3.js force-directed SVG diagram module
│   ├── reflect.js               Guile Hoot WebAssembly runtime (do not edit)
│   ├── style.css                All UI styling
│   ├── envdraw.scm              Hoot entry point — FFI bindings, primitives, boot!
│   ├── envdraw.wasm             Compiled output (checked in)
│   ├── reflect.wasm             Hoot runtime support (checked in, from Hoot install)
│   └── wtf8.wasm                Hoot runtime support (checked in, from Hoot install)
├── src/                         Scheme source modules (included by envdraw.scm)
│   ├── core/
│   │   ├── meta.scm             Metacircular evaluator (view-eval, view-apply)
│   │   ├── environments.scm     Environment / frame / binding model
│   │   ├── eval-observer.scm    Observer interface (decouples evaluator from UI)
│   │   └── stacks.scm           Stack and doubly-linked list structures
│   ├── model/
│   │   └── color.scm            RGB color records and hex conversion
│   └── ui/
│       └── web-observer.scm     Observer implementation — emits D3 FFI calls
└── original/                    1996 STk/Tk source (historical reference)
```

## How the code fits together

### Compilation model

`web/envdraw.scm` is the single compilation unit.  It uses `(include ...)` to
pull in the `src/` files at compile time — there is no separate linking step.
The compiler is **Guile Hoot** (`guild compile-wasm`), which produces a single
`envdraw.wasm` file.

```
web/envdraw.scm
  ├── (include "../src/core/stacks.scm")
  ├── (include "../src/model/color.scm")
  ├── (include "../src/core/eval-observer.scm")
  ├── (include "../src/ui/web-observer.scm")
  ├── (include "../src/core/environments.scm")
  └── (include "../src/core/meta.scm")       ← must be last (uses *host-eval*)
```

**Include order matters.** `meta.scm` references `*host-eval*` (the primitives
table), which is defined in `envdraw.scm` between the includes and the final
`(include "../src/core/meta.scm")`.  The primitives table itself references
`user-print` and `user-display` from `web-observer.scm`, so the observer must
be included first.

### Data flow at runtime

```
User types in REPL
  → boot.js calls callbacks.eval(text)
  → Wasm: envdraw-eval parses text, calls view-eval (meta.scm)
  → environments.scm creates frames/bindings
  → observer hooks fire (eval-observer.scm interface)
  → web-observer.scm calls FFI: d3-add-frame, d3-add-binding, d3-add-procedure
  → boot.js bridges FFI to EnvDiagram.addFrame() etc.
  → d3-diagram.js updates force simulation → SVG re-renders
```

### FFI boundary

`envdraw.scm` declares FFI imports with `(define-foreign ...)` from the Hoot
FFI module.  Each foreign function names a module and export:

```scheme
(define-foreign d3-add-frame "app" "d3AddFrame"
  (ref string) (ref string) (ref string) (ref string) -> none)
```

On the JS side, `boot.js` provides these as the `app` import object when
calling `Scheme.load_main()`:

```javascript
await Scheme.load_main("envdraw.wasm", {
  app: {
    d3AddFrame(id, name, parentId, color) {
      diagram.addFrame(schemeToString(id), ...);
    },
    // ...
  }
});
```

There are also `ctx` (Canvas2D context — all no-ops, kept for API
compatibility) and `dom` (console.log, alert, etc.) import modules.

### Hoot runtime files

`reflect.wasm` and `wtf8.wasm` are part of the Guile Hoot runtime.  They are
loaded by `reflect.js` and provide the WebAssembly GC substrate.  These files
come from the Hoot installation and should only be updated when upgrading Hoot
versions:

```sh
cp /opt/homebrew/Cellar/guile-hoot/0.6.1/share/guile-hoot/0.6.1/reflect-wasm/reflect.wasm web/
cp /opt/homebrew/Cellar/guile-hoot/0.6.1/share/guile-hoot/0.6.1/wtf8-wasm/wtf8.wasm web/
```

`reflect.js` is also from the Hoot install — it defines the `Scheme` global
with `Scheme.load_main()`.

### D3.js

Loaded from CDN (`https://d3js.org/d3.v7.min.js`) in `index.html`.  No local
copy.  The `EnvDiagram` class in `d3-diagram.js` uses D3-force, D3-zoom, and
D3-drag for the interactive SVG diagram.

## Prerequisites

| Tool | Version | Install (macOS) |
|------|---------|-----------------|
| Guile | 3.0.x | `brew install guile` |
| Guile Hoot | 0.6.1 | `brew install guile-hoot` |
| Python 3 | any | pre-installed on macOS |

You only need Guile + Hoot if you modify any `.scm` file.  If you only change
JS/CSS/HTML, skip straight to `./build.sh serve`.

Verify your install:

```sh
guile --version          # GNU Guile 3.0.x
guile -c '(use-modules (hoot config)) (display %version) (newline)'
                         # 0.6.1
```

## Local development

### Build the Wasm module

```sh
./build.sh               # compiles web/envdraw.wasm (~30s on M1) + generates web/examples.js
```

This runs:

```sh
guild compile-wasm -L web -L . -o web/envdraw.wasm web/envdraw.scm
```

The `-L web -L .` flags set Guile's load path so `(include "../src/...")` paths
resolve correctly from `web/envdraw.scm`.

It also generates `web/examples.js` from `examples/*.scm` (see below).

### Rebuild examples only

```sh
./build.sh examples       # regenerates web/examples.js from examples/*.scm
```

This reads each `.scm` file in `examples/`, JSON-encodes its contents, and
writes `web/examples.js` — a static array consumed by the toolbar dropdown.
No Wasm recompilation needed.  Use this after adding or editing example files.

### Run the dev server

```sh
./build.sh serve          # python3 -m http.server 8088 from web/
```

Open http://localhost:8088/ in Chrome 119+ or Firefox 120+.

### Edit → rebuild cycle

1. Edit any `.scm` file under `src/` or `web/envdraw.scm`
2. Run `./build.sh`
3. Hard-refresh the browser (Cmd+Shift+R)

For JS/CSS/HTML changes, just save and refresh — no build step needed.

`boot.js` is loaded with a cache-buster query param (`boot.js?v=9`).  Bump the
version number in `index.html` if you change `boot.js` and want to ensure
clients pick up the new version without hard-refresh.

### Clean

```sh
./build.sh clean          # removes web/envdraw.wasm and web/examples.js
```

This does **not** remove `reflect.wasm` or `wtf8.wasm` (they are Hoot runtime
files, not build outputs).

## Deployment (GitHub Pages)

### How it works

The workflow at `.github/workflows/deploy-pages.yml` deploys the `web/`
directory as a static site to GitHub Pages.

- **Trigger:** push to `main`, PR to `main`, or manual dispatch
- **Validate job:** checks that all 8 required files exist in `web/`
- **Deploy job:** (push/dispatch only) uploads `web/` as a Pages artifact and
  deploys it

Since Guile Hoot is difficult to install in CI, the compiled `envdraw.wasm` is
checked into the repository.  The workflow does **not** rebuild the Wasm — it
deploys the checked-in binary.

### Deployment workflow

1. Modify Scheme source locally
2. Run `./build.sh` to produce `web/envdraw.wasm`
3. Test locally with `./build.sh serve`
4. Commit the updated `.scm` files **and** the new `envdraw.wasm`
5. Push to `main`
6. GitHub Actions validates files exist, then deploys `web/` to Pages

### GitHub repo settings required

- **Settings → Pages → Source:** set to "GitHub Actions"
- The workflow needs `pages: write` and `id-token: write` permissions (already
  configured in the YAML)

### Site URL

https://jmacd.github.io/envdraw/

## Known quirks and gotchas

### Hoot quasiquote bug

Hoot 0.6.1 crashes at runtime with "index out of bounds" when a single
quasiquote expression contains ~80+ unquotes.  The primitives table in
`envdraw.scm` works around this by splitting into small groups (`*prims-arith*`,
`*prims-compare*`, etc.) and joining them with `append`.

### Browser requirements

The Wasm output uses **WebAssembly GC** and **tail calls** — proposals that are
not yet universal.  Minimum browser versions:

- Chrome 119+
- Firefox 120+
- Safari 18.2+

Older browsers will fail to load the Wasm module.

### `reflect.js` global

`reflect.js` defines a global `Scheme` object.  It must be loaded as a regular
`<script>` tag **before** `boot.js`.  `d3-diagram.js` must also load before
`boot.js` since boot references `EnvDiagram`.

Script loading order in `index.html`:
1. D3 v7 (CDN)
2. `reflect.js` (defines `Scheme`)
3. `d3-diagram.js` (defines `EnvDiagram`)
4. `boot.js` (via dynamic `<script>` with cache-buster)

### Canvas2D FFI is unused

`envdraw.scm` declares a full set of Canvas2D FFI bindings (`ctx` module) but
they are all wired to no-op stubs in `boot.js`.  These exist because the
original rendering pipeline used Canvas2D; Phase 5 replaced it with D3.js SVG.
They can be removed in a future cleanup, but the Wasm module declares them as
imports so the stubs must remain as long as the FFI declarations do.

### Guile load paths

`build.sh` hardcodes Homebrew paths (`/opt/homebrew/...`).  If Guile/Hoot are
installed elsewhere (e.g., Linux, Nix, or a different Homebrew prefix), adjust
the `GUILE_LOAD_PATH` and `GUILE_LOAD_COMPILED_PATH` exports at the top of
`build.sh`.

## Source file reference

### `web/envdraw.scm` — Hoot entry point (452 lines)

The top-level compilation unit.  Contains:
- R7RS compatibility shims (`inexact->exact`, `list-sort`)
- FFI declarations for `ctx` (Canvas2D), `dom` (console/alert), and `app`
  (callbacks, D3 graph mutations)
- `(include ...)` directives for all `src/` modules
- Primitives table (split across small quasiquoted alists)
- `boot!` procedure — creates observer, initializes evaluator, registers
  callback handlers

### `src/core/meta.scm` — Metacircular evaluator

`view-eval` / `view-apply` implementing a subset of Scheme.  Supports: lambda,
define, set!, if, cond, and, or, begin, let, let*, letrec, quote, quasiquote.
Tail-call optimized via Hoot's native tail calls.  Calls observer hooks on
evaluation steps.

### `src/core/environments.scm` — Environment model

First-class environment records with frames and bindings.  `extend-environment`,
`define-variable!`, `set-variable-value!`, `lookup-variable-value`.  Each
mutation fires the appropriate observer callback.

### `src/core/eval-observer.scm` — Observer interface

Record type `eval-observer` with hook slots: `on-frame-created`,
`on-binding-placed`, `on-binding-updated`, `on-procedure-created`,
`on-env-pointer`, `on-before-eval`, `on-after-eval`, `on-before-apply`,
`on-after-apply`, `on-gc`.

### `src/ui/web-observer.scm` — D3 bridge

`make-web-observer` returns an `eval-observer` whose hooks call the D3 FFI
functions.  Manages frame/procedure ID generation, color cycling, and GC sweep.

### `src/core/stacks.scm` — Data structures

Stack (LIFO) and doubly-linked list used by the evaluator for continuation
management.

### `src/model/color.scm` — Color utilities

`make-color`, `color->hex`, and a palette of named colors used by the observer
to assign distinct colors to frames and procedures.

### `web/boot.js` — JavaScript bootstrap (599 lines)

Loads `envdraw.wasm` via `Scheme.load_main()`.  Provides all FFI import objects.
Wires REPL input, toolbar buttons (step/continue/GC/clear), keyboard shortcuts,
and the resizable trace panel.  Creates an `EnvDiagram` instance and delegates
all graph mutations to it.

### `web/d3-diagram.js` — D3 visualization

`EnvDiagram` class.  Methods: `addFrame`, `addProcedure`, `addBinding`,
`updateBinding`, `removeNode`, `removeEdge`, `clear`, `fitToView`, `zoomBy`.
Uses D3-force simulation with charge, collide, link, and positional forces.
SVG enter/update/exit pattern with transitions.  D3-zoom for pan/zoom, D3-drag
for repositioning nodes.

### `web/reflect.js` — Hoot runtime

Auto-generated by Guile Hoot.  Defines the `Scheme` global with
`Scheme.load_main(wasmUrl, importObject)`.  Handles Wasm value marshalling
between JS and Scheme types.  Do not edit manually.

## Upgrading Guile Hoot

If a new Hoot version is released:

1. Install: `brew upgrade guile-hoot`
2. Rebuild: `./build.sh`
3. Copy updated runtime files:
   ```sh
   cp $(brew --prefix guile-hoot)/share/guile-hoot/*/reflect-wasm/reflect.wasm web/
   cp $(brew --prefix guile-hoot)/share/guile-hoot/*/wtf8-wasm/wtf8.wasm web/
   ```
4. Replace `web/reflect.js` with the version from the new Hoot install
5. Test locally, then commit all updated `.wasm` files + `reflect.js`
