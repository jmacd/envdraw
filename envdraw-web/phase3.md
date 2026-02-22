# EnvDraw Web Port — Phase 3 Report

**Date:** February 21, 2026  
**Author:** Josh MacDonald  
**Phase:** Wire Up the Web UI

---

## Summary

Phase 3 connected all the pieces from Phases 1 and 2 into a running web application. The metacircular evaluator, scene-graph layout engine, and pointer-routing algorithms are now compiled to WebAssembly via Guile Hoot 0.6.1 and run in the browser. A JavaScript bootstrap layer wires the REPL input, toolbar controls, and Canvas2D rendering to the Scheme core through Hoot's FFI.

**Key result:** EnvDraw runs in Firefox. Users can type Scheme expressions into the REPL, the metacircular evaluator executes them, and environment diagrams are drawn on an HTML5 Canvas in real time.

---

## What Was Done

### 1. Hoot Entry Point (`web/envdraw.scm`, 403 LOC)

Created a new top-level program that replaces `src/main.scm` for the Wasm build. This file is compiled directly to `envdraw.wasm` and contains:

- **R7RS module imports** — `(scheme base)`, `(scheme read/write/inexact/cxr/case-lambda)`, `(hoot ffi)`, `(only (hoot lists) sort)`
- **R5RS compatibility shims** — `inexact->exact`, `exact->inexact`, `list-sort`
- **26 Canvas2D FFI bindings** (module `"ctx"`) — `fillRect`, `strokeRect`, `arc`, `ellipse`, `fillText`, `measureTextWidth`, `save`/`restore`, `translate`, `scale`, etc. Each is a `define-foreign` declaration mapping a Scheme procedure to a JavaScript function
- **13 App FFI bindings** (module `"app"`) — `registerEvalHandler`, `registerRenderHandler`, `traceAppend`, `setResultText`, `getCanvasContext`, `consoleLog`, etc.
- **Primitives table** (~80 entries) — Maps symbol names to native Scheme procedures, replacing `(eval var (interaction-environment))` which isn't available in Hoot
- **`*host-eval*`** — Lookup function used by the metacircular evaluator to resolve primitive bindings
- **`include` directives** — Pulls in all 11 source files in dependency order
- **`boot!` procedure** — Creates the scene graph root, web observer, and evaluator; registers six `procedure->external` callbacks for JS to invoke

### 2. JavaScript Bootstrap (`web/boot.js`, 266 LOC)

Rewrote the JavaScript layer to load and interact with the Hoot-compiled Wasm module:

- **FFI import objects** — `ctxImports` (26 Canvas2D operations) and `appImports` (13 app callbacks) provided as `user_imports` to `Scheme.load_main()`
- **Callback registration** — The Scheme side calls `registerEvalHandler(fn)` etc. during boot, storing wrapped Scheme procedures that JS later invokes on user actions
- **REPL wiring** — Enter key sends input text to the Scheme eval callback; Up/Down arrows navigate command history
- **Toolbar wiring** — Step, Continue, Toggle-stepping, and GC buttons
- **Canvas resize** — `devicePixelRatio`-aware resizing with a resize callback to Scheme
- **Cache-busting** — `"envdraw.wasm?" + Date.now()` ensures fresh loads during development

### 3. Dual-Target Evaluator (`src/core/meta.scm`, modified)

Modified the metacircular evaluator to work in both native Guile and Hoot/Wasm:

- **`lookup-variable-value`** — Changed from `(eval var (interaction-environment))` to `(*host-eval* var)`. The native build defines `*host-eval*` as a wrapper around `eval`; the Wasm build uses the primitives table
- **`user-print` / `user-display`** — Changed from direct `display`/`write` calls to use `*meta-observer*` output callbacks, allowing the web UI to redirect output to the trace panel
- **Removed duplicate definitions** — `cddddr` (in `(scheme cxr)`), `list-copy` (in `(scheme base)`)

### 4. Build Infrastructure (`build.sh`, 74 LOC)

Created a build script for the compile-debug cycle:

```
./build.sh          # compile envdraw.wasm
./build.sh test     # compile envdraw-test.wasm
./build.sh tmp      # compile tmp-test.wasm (bisect debugging)
./build.sh all      # compile main + test
./build.sh clean    # remove outputs, restore runtime .wasm
./build.sh FILE.scm # compile arbitrary .scm
```

Sets up `GUILE_LOAD_PATH` and `GUILE_LOAD_COMPILED_PATH` automatically. Reports output size and compile time.

---

## Bugs Found and Fixed

### 1. Large Quasiquote Crashes Hoot (Root Cause of "index out of bounds")

**Symptom:** `RuntimeError: index out of bounds` immediately when `$load` runs — before any top-level Scheme code executes.

**Root cause:** Hoot 0.6.1 generates an invalid Wasm table index when a single quasiquote expression contains ~80+ unquotes. The primitives table was originally written as one large `` `((+ . ,+) (- . ,-) ... (values . ,values)) `` with 80+ entries.

**Fix:** Split the table into ~10 smaller quasiquoted lists (`*prims-arith*`, `*prims-cmp*`, `*prims-pred*`, etc.) and join with `append`. Each sub-list has ≤20 unquotes.

**Debugging process:** The crash showed no console output at all, making it appear like a loading/caching issue. Systematic bisection using an incremental test file (`envdraw-test.scm`) with checkpoint `console-log` calls between each `include` narrowed the crash to the primitives table definition. Comparing the working (split) test vs. failing (monolithic) main confirmed the quasiquote size as the trigger.

### 2. Forward Reference to `user-print` / `user-display`

The primitives table originally appeared before the `include` directives. Since `user-print` and `user-display` are defined in `web-observer.scm`, the unquoted references `,user-print` evaluated before those definitions existed. Fix: moved all includes before the primitives table.

### 3. Missing Primitives

`user-print` and `user-display` were initially missing from the primitives table entirely, causing `"Unbound variable (no host binding): user-print"` when the evaluator tried to resolve them. Added to the `*prims-io*` group.

### 4. Compilation Errors (R7RS / Hoot Compatibility)

| Issue | Fix |
|-------|-----|
| `(srfi 9)` import fails | Removed — `define-record-type` is in `(scheme base)` |
| `list-copy` duplicate definition | Removed — already in `(scheme base)` |
| `cddddr` duplicate definition | Removed from meta.scm — already in `(scheme cxr)` |
| `vector-ref,` typo (trailing comma) | Fixed to `vector-ref` |
| `list-sort` unbound | Added `(only (hoot lists) sort)` + `(define list-sort sort)` |

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   Browser                        │
│                                                  │
│  ┌──────────┐   ┌──────────┐   ┌──────────────┐ │
│  │ index    │   │ boot.js  │   │ reflect.js   │ │
│  │ .html    │──▶│ (266 LOC)│──▶│ (Hoot runtime│ │
│  │          │   │          │   │  1028 LOC)   │ │
│  └──────────┘   └────┬─────┘   └──────┬───────┘ │
│                      │                │          │
│            user_imports {}    loads & instantiates│
│            ┌─────────┴──────┐         │          │
│            │                │         ▼          │
│      ┌─────┴─────┐   ┌─────┴──────────────────┐ │
│      │ ctx: 26   │   │ envdraw.wasm (931 KB)   │ │
│      │ Canvas2D  │   │                         │ │
│      │ functions │   │  ┌───────────────────┐  │ │
│      └───────────┘   │  │ eval → scene graph│  │ │
│      ┌───────────┐   │  │ → pointer routing │  │ │
│      │ app: 13   │   │  │ → render calls    │  │ │
│      │ callbacks │   │  └───────────────────┘  │ │
│      │ + DOM ops │   │                         │ │
│      └───────────┘   │  boot! registers 6      │ │
│            ▲         │  procedure->external     │ │
│            │         │  callbacks for JS        │ │
│            └─────────┴─────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Data flow:**
1. User types `(define x 42)` in the REPL → JS captures Enter key
2. JS calls the registered `eval` callback → enters Wasm
3. Metacircular evaluator parses and evaluates → observer callbacks fire
4. Observer creates scene-graph nodes, runs placement & pointer routing
5. `request-render!` traverses the scene graph, calling Canvas2D FFI functions
6. Canvas2D FFI functions (`ctx.fillRect`, `ctx.strokeRect`, etc.) draw on the HTML5 Canvas

---

## Files Created or Modified

### New Files

| File | Lines | Description |
|------|------:|-------------|
| `web/envdraw.scm` | 403 | Hoot entry point, FFI bindings, boot! |
| `web/boot.js` | 266 | JS bootstrap, event wiring |
| `web/envdraw-test.scm` | 296 | Incremental test with phase checkpoints |
| `web/envdraw-test.html` | 51 | Test harness with stub imports |
| `build.sh` | 74 | Build script for compile-debug cycle |

### Modified Files

| File | Change |
|------|--------|
| `src/core/meta.scm` | `*host-eval*` dispatch, removed duplicates |
| `src/main.scm` | Added native `*host-eval*` definition |

---

## Test Results

**Compilation:** `envdraw.wasm` compiles in ~6 seconds, producing a 931 KB binary.

**Incremental test (`envdraw-test.html`):** All 16 phases pass:
```
[TMP] phase 1: FFI bindings OK
[TMP] phase 1b: all app FFI OK
[TMP] phase 2–12: all includes OK (stacks, math, color, scene-graph,
      profiles, placement, pointers, renderer, eval-observer,
      web-observer, environments)
[TMP] phase 13: primitives OK
[TMP] phase 14: meta OK
[TMP] phase 15–16: boot! defined and executed
[TMP] EnvDraw incremental test: ALL PHASES PASSED
```

**Full application (`index.html`):** Loads and runs in Firefox. REPL accepts Scheme input.

---

## What Remains

### Phase 4: Polish & Testing
- [ ] Verify existing 82 tests still pass under native Guile
- [ ] End-to-end browser tests (define, lambda, closures, mutation)
- [ ] Stepping UI (Step/Continue buttons invoke observer's stepping protocol)
- [ ] GC button implementation
- [ ] Error display improvements in the trace panel
- [ ] Smooth pointer animation
- [ ] Pan/zoom on the canvas
- [ ] Mobile-friendly layout

### Known Limitations
- **Safari** not supported (no Wasm GC / tail calls)
- **Hoot quasiquote bug** — single quasiquote with 80+ unquotes produces invalid Wasm table indices; work around by splitting into smaller expressions
- **`try` instruction deprecation** — Firefox warns about the deprecated Wasm exception handling `try` instruction; requires Hoot to emit `try_table` instead (upstream fix needed)
