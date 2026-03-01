# EnvDraw Web Port — Progress Report

**Date:** February 21, 2026  
**Author:** Josh MacDonald (original EnvDraw author, 1995)  
**Goal:** Port EnvDraw from STk/Tk to web-native using Guile Hoot (Scheme → WebAssembly) and HTML5 Canvas.

---

## What is EnvDraw?

EnvDraw is a metacircular Scheme evaluator that draws SICP-style environment diagrams in real time as code executes. Originally written in 1995 for UC Berkeley's CS 61A course using STk (a Scheme+Tk system), it hasn't run in decades. This project revives it as a web application.

## Summary

In a single session we:

1. **Analyzed** the complete original codebase (19 `.stk` files, 5,266 LOC)
2. **Ported** the core evaluator and supporting infrastructure to R7RS-compatible Guile Scheme (2,478 LOC across 11 source files)
3. **Built** the web application shell (HTML/CSS/JS)
4. **Installed** the full native toolchain (Guile 3.0.11 + Hoot 0.6.1 via Homebrew)
5. **Passed** 31/31 evaluator tests under Guile
6. **Compiled** and served a Hoot→Wasm hello-world in the browser

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Browser                        │
│  ┌─────────────┐  ┌──────────┐  ┌───────────┐  │
│  │ index.html  │  │ style.css│  │  boot.js   │  │
│  │ (app shell) │  │          │  │ (FFI glue) │  │
│  └──────┬──────┘  └──────────┘  └─────┬──────┘  │
│         │           Hoot FFI          │         │
│  ┌──────┴─────────────────────────────┴──────┐  │
│  │         envdraw.wasm (Scheme→Wasm)        │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │  Core: meta.scm, environments.scm  │  │  │
│  │  │  Model: scene-graph, color, math   │  │  │
│  │  │  Render: canvas-ffi, renderer      │  │  │
│  │  │  UI: web-observer                  │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
│  reflect.js + reflect.wasm + wtf8.wasm (Hoot)   │
└─────────────────────────────────────────────────┘
```

The key architectural decision is the **observer pattern** replacing STklos/Tk widget coupling:
- The evaluator fires hooks (frame created, binding placed, procedure created, etc.)
- The web observer builds scene-graph nodes in response
- The renderer walks the scene graph and draws to Canvas2D

This makes the evaluator core completely platform-independent.

---

## Source Files

### Scheme Core (2,478 LOC)

| File | Lines | Ported From | Description |
|------|------:|-------------|-------------|
| `src/main.scm` | 126 | *(new)* | Entry point, load orchestrator, REPL |
| `src/core/meta.scm` | 666 | `meta.stk` | Metacircular evaluator; Max Hailperin's tail-recursion preserved |
| `src/core/environments.scm` | 262 | `environments.stk` | Frames, bindings, environment operations |
| `src/core/eval-observer.scm` | 169 | *(new)* | Observer protocol with 14 callback slots |
| `src/core/stacks.scm` | 105 | `stacks.stk` | Stack and doubly-linked list (STklos → R7RS records) |
| `src/model/scene-graph.scm` | 302 | `view-classes.stk` et al. | Retained-mode node tree with hit testing |
| `src/model/math.scm` | 155 | `math.stk` | Vector arithmetic (explicit dispatch, no GOOPS) |
| `src/model/color.scm` | 90 | `color.stk` | RGB color records, CSS conversion, palette |
| `src/render/canvas-ffi.scm` | 162 | *(new)* | Canvas2D stubs (native) / `define-foreign` (Hoot) |
| `src/render/renderer.scm` | 177 | *(new)* | Depth-first scene-graph walker, shape renderers |
| `src/ui/web-observer.scm` | 264 | `env-toplev.stk` et al. | Concrete observer wiring evaluator → scene graph |

### Web Shell

| File | Lines | Description |
|------|------:|-------------|
| `web/index.html` | 38 | App shell: toolbar, trace panel, canvas, REPL |
| `web/style.css` | 167 | Dark REPL, light trace panel, responsive canvas |
| `web/boot.js` | 146 | JS FFI bridge: canvas, DOM, events, timers (26+ methods) |

### Tests

| File | Lines | Description |
|------|------:|-------------|
| `test-evaluator.scm` | 115 | 31 tests: self-eval, arithmetic, lambda, recursion, tail calls, mutation |

---

## Toolchain

| Tool | Version | Install Method |
|------|---------|----------------|
| Guile | 3.0.11 | `brew install guile` |
| Guile Hoot | 0.6.1 | `brew tap aconchillo/guile && brew install guile-hoot` |
| macOS | 15.6.1 (arm64) | — |
| Docker | 28.5.2 (OrbStack) | Available but not needed — Homebrew path works |

Environment setup: `source env.sh` sets `GUILE_LOAD_PATH` and `GUILE_LOAD_COMPILED_PATH`.

---

## What Works

### Evaluator (31/31 tests passing)

```
=== EnvDraw Evaluator Tests ===
--- Self-evaluating expressions --- 6/6 PASS
--- Arithmetic (primitives) ---     4/4 PASS
--- Define and lookup ---           4/4 PASS
--- Lambda and application ---      4/4 PASS
--- Conditionals ---                4/4 PASS
--- Let ---                         1/1 PASS
--- Sequencing ---                  1/1 PASS
--- Boolean logic ---               4/4 PASS
--- Recursion ---                   1/1 PASS
--- Tail recursion (Hailperin) ---  1/1 PASS
--- Mutation ---                    1/1 PASS
```

Run with: `guile --no-auto-compile test-evaluator.scm`

### Hoot Compilation Pipeline

```
$ guild compile-wasm -L . -o hello.wasm hello.scm
wrote `hello.wasm'
```

- Scheme → Wasm compilation works via `guild compile-wasm`
- Hoot's built-in VM can execute compiled Wasm: `(compile-value 42)` → `42`
- Browser runtime files deployed: `reflect.js`, `reflect.wasm`, `wtf8.wasm`
- Hello-world test page served and loads successfully in Chrome/Firefox

---

## Guile Compatibility Issues Resolved

| Issue | Cause | Fix |
|-------|-------|-----|
| Load path doubling (`src/src/...`) | `load` relative to CWD, not file | `load-relative` helper using `current-filename`/`dirname` |
| `define-record-type` unbound | SRFI-9 not in default Guile env | `(use-modules (srfi srfi-9))` in main.scm |
| `procedure-info-frame` syntax transformer error | Record defined *after* first use; Guile SRFI-9 accessors are syntax transformers | Moved `<procedure-info>` record to top of meta.scm |
| `eval` wrong arity | Guile requires `(eval expr env)` | Changed to `(eval var (interaction-environment))` |
| `guard`/`condition-message` unbound | R7RS error handling not in Guile default | Replaced with Guile's `catch`/handler |
| `flush-output-port` unbound | R7RS name | Replaced with `force-output` |
| `read-line` unbound | Needs explicit import | `(use-modules (ice-9 rdelim))` |

---

## What Remains

### Phase 2: Complete the Scene Graph & Layout ✅
- [x] Port `placement.stk` → convex-hull placement algorithm (placement.scm, 333 LOC)
- [x] Port `view-profiles.stk` → cell profiles and layout constants (profiles.scm, 130 LOC)
- [x] Port `env-pointers.stk` / `simple-pointer.stk` / `view-pointers.stk` → all pointer routing (pointers.scm, 310 LOC)
- [x] Integrate into web-observer with hull-based placement replacing grid layout
- [x] Fix frame-id propagation (observer returns node-id → stored in frame-info)
- [x] 51 Phase 2 tests passing + 31 evaluator tests still passing

### Phase 3: Wire Up the Web UI
- [ ] Compile full evaluator to `envdraw.wasm` with Hoot
- [ ] Replace canvas-ffi stubs with real `define-foreign` bindings
- [ ] Connect REPL input → evaluator → scene graph → canvas render loop
- [ ] Implement stepping UI (Step/Continue buttons via observer callbacks)
- [ ] Wire toolbar controls (GC, stepping mode toggle)

### Phase 4: Polish
- [ ] Smooth pointer animation (the original had animated arrows)
- [ ] Pan/zoom on the canvas
- [ ] Resize handling
- [ ] Error display in the trace panel
- [ ] Mobile-friendly layout

### Known Limitations
- Safari not supported (no Wasm GC / tail calls)
- Hoot 0.6.1 is R7RS-small; some Guile extensions may need workarounds
- The `--no-auto-compile` flag is needed for Guile tests (compiled cache issues with loaded files)
