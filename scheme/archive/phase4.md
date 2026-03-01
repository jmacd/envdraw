# EnvDraw Web Port — Phase 4 Report

**Date:** February 21, 2026  
**Author:** Josh MacDonald  
**Phase:** UI Polish, Interactivity & Browser Testing

---

## Summary

Phase 4 addressed three categories of issues inherited from Phase 3: visual layout problems, missing interactivity, and the absence of automated browser tests. The trace panel was moved from the left side (where it obscured the canvas diagram) to a collapsible right sidebar. The entire UI was redesigned with a modern, clean aesthetic. The rendering pipeline was fixed so that environment diagrams actually appear on the canvas (previously all elements rendered on top of each other at the origin). Interactive node dragging and canvas pan/zoom were added. A Puppeteer-based end-to-end test suite was created.

**Key results:**
- Environment diagrams render correctly — frames and procedures are positioned by the placement algorithm and visible on canvas
- Users can drag environment nodes to rearrange the diagram
- Canvas supports pan (mouse drag on empty space) and zoom (scroll wheel, toolbar buttons)
- Trace panel is a resizable, collapsible right sidebar that no longer obscures the diagram
- 22 automated browser tests verify the full stack from REPL input through Wasm evaluation to canvas rendering
- All 82 native Guile tests continue to pass

---

## What Was Done

### 1. UI Redesign (`web/index.html`, 91 LOC; `web/style.css`, 584 LOC)

Complete rewrite of the HTML structure and CSS styling:

- **Layout restructured** — Trace panel moved from left side to a collapsible right sidebar with a drag-to-resize handle. The canvas now occupies the dominant area.
- **Toolbar** — Top bar with branded "EnvDraw" label, Step/Continue buttons, stepping toggle switch, GC button, Clear button, status indicator, and trace panel toggle
- **Zoom controls overlay** — Floating panel on the canvas with +/−/reset/fit buttons showing the current zoom percentage
- **Empty state** — λ icon placeholder with example expressions (clickable to insert into REPL) shown before any evaluation
- **Design tokens** — CSS custom properties for colors, spacing, typography, border radius, transitions — all defined in `:root`
- **Canvas** — White background with subtle dot grid pattern, `devicePixelRatio`-aware sizing
- **REPL** — Dark terminal-style input bar at the bottom with prompt, command history position indicator, consistent monospace font
- **Trace panel** — Syntax-highlighted trace lines (color-coded for input/eval/return/error), scrollable, with clear button
- **Responsive** — Trace panel overlays on viewports < 768px wide; scrollbar styling for WebKit/Firefox

### 2. Rendering Pipeline Fix (`src/render/renderer.scm`, `src/ui/web-observer.scm`, `web/boot.js`)

**Problem:** All environment diagram elements rendered at the origin, stacked on top of each other, producing an unreadable blob.

**Root cause:** A double-transform bug. The JavaScript `getCanvasContext()` function applied DPR scaling, pan offset, and zoom — then the Scheme `render-scene` procedure applied its own camera transforms (scale + translate) on top of that. Additionally, `clearRect` ran in the already-transformed coordinate space, so it only cleared a portion of the physical canvas. Finally, `request-render!` reused a cached stale canvas context rather than getting a fresh one each frame.

**Fix (three parts):**

1. **`renderer.scm`** — Removed all camera transform logic from `render-scene`. It no longer calls `canvas-clear-rect!`, `canvas-save!`, `canvas-scale!`, `canvas-translate!`, or `canvas-restore!`. The function now simply calls `(render-node ctx root 0 0)`. All clearing and transform setup is the responsibility of the JS side.

2. **`web-observer.scm`** — Introduced a `*get-fresh-context*` thunk pattern. In native Guile mode it defaults to `(lambda () *render-ctx*)` (returns the cached stub context). In Wasm mode, `boot!` overrides it to `(lambda () (get-canvas-context))`, which calls the FFI to get a freshly-transformed context each frame. `request-render!` now calls `(*get-fresh-context*)` at the start of every render, ensuring the canvas is cleared and transforms are reapplied. Removed the now-unused `*camera-x*`, `*camera-y*`, `*camera-zoom*` state variables.

3. **`boot.js`** — `getCanvasContext()` performs the full sequence: reset transform → clear entire physical canvas → apply DPR + pan + zoom. This is called by Scheme at the start of each render via `*get-fresh-context*`, ensuring correct layering of transforms.

### 3. Node Dragging (`src/ui/web-observer.scm`, `web/envdraw.scm`, `web/boot.js`)

Added interactive drag-and-drop for environment diagram nodes:

**Scheme side** (`web-observer.scm`, new drag-and-drop section):
- `handle-mouse-down!` — hit-tests the scene graph at the given scene coordinates, walks up to find a draggable ancestor (direct child of root = top-level frame or procedure group), stores the drag target and mouse offset
- `handle-mouse-move!` — updates the drag node's position in the scene graph (converting to relative coordinates if parented), triggers a re-render
- `handle-mouse-up!` — clears drag state
- `find-draggable-ancestor` — walks up the node tree to find a group that is a direct child of the scene root

**FFI bindings** (`web/envdraw.scm`):
- 3 new `define-foreign` declarations: `register-mouse-down-handler`, `register-mouse-move-handler`, `register-mouse-up-handler`
- 3 new `procedure->external` registrations in `boot!` wrapping `handle-mouse-down!`, `handle-mouse-move!`, `handle-mouse-up!`

**JavaScript side** (`boot.js`):
- Mouse down on canvas calls `clientToScene()` to convert to scene coordinates, then calls the Scheme `mouseDown` callback for hit-testing
- If Scheme finds a node under the cursor → node drag mode; subsequent mouse moves send scene coordinates to Scheme's `handle-mouse-move!`
- If no node is hit → pan mode with a 3px deadzone threshold to prevent accidental pans on click
- Mouse up notifies Scheme to clear drag state

### 4. Pan & Zoom (`web/boot.js`)

Canvas interaction for navigating large diagrams:

- **Pan** — Click and drag on empty canvas space; 3px deadzone threshold before committing to pan mode to distinguish from clicks
- **Scroll wheel zoom** — `Math.exp(-deltaY * 0.001)` for smooth zoom, centered on mouse cursor position
- **Zoom buttons** — +/−/reset/fit in the floating zoom overlay; center-of-viewport zooming for button clicks
- **Zoom range** — Clamped between 10% and 500%
- **`clientToScene()`** — Coordinate conversion utility: `(cssPos - pan) / zoom`
- **Keyboard shortcuts** — `T` toggle trace, `0` reset zoom, `+`/`-` zoom in/out, `/` focus REPL, `F10` step, `F5` continue

### 5. Resizable Trace Panel (`web/boot.js`, `web/style.css`)

- Drag handle between canvas and trace panel
- Panel width constrained between 180px and 600px
- Collapse/expand via toolbar toggle button (☰)
- CSS transition for smooth collapse animation

### 6. Puppeteer Test Suite (`test/browser-test.mjs`, 455 LOC)

Created a comprehensive end-to-end browser test framework:

- **Built-in HTTP server** — Serves `web/` directory on port 8089; no external server dependency
- **3 run modes** — `npm test` (headless), `npm run test:headed` (visible browser), `npm run test:debug` (headed + slow + devtools)
- **22 tests across 13 categories:**

| # | Category | Tests |
|---|----------|-------|
| 1 | Page load | Page loads, Wasm boots, no JS errors |
| 2 | Empty state | Placeholder visible before first eval |
| 3 | Define variable | REPL input in trace, result in trace |
| 4 | Canvas rendering | Non-white pixels exist, diagram not at origin, reasonable size |
| 5 | Empty state hidden | Placeholder disappears after first eval |
| 6 | Define function | Diagram grows after function definition |
| 7 | Call function | `(square 5)` → 25 in trace |
| 8 | Multiple definitions | Elements spread across canvas |
| 9 | Closures | `(make-adder 5)` → `(add5 10)` → 15 |
| 10 | Zoom controls | Zoom in changes label, reset returns to 100% |
| 11 | Trace toggle | Collapse/expand trace panel |
| 12 | Clear | Trace panel emptied |
| 13 | Error handling | Division by zero produces error in trace |
| — | Command history | Arrow-up recalls previous input |

- **Diagnostic screenshots** — Saved to `test/screenshot-*.png` at each stage
- **Canvas pixel analysis** — `canvasHasContent()` samples every 10th pixel for non-white content; `getNodePositions()` computes bounding box of all colored pixels to verify diagram layout

### 7. Test Harness Updates (`web/envdraw-test.scm`, `web/envdraw-test.html`)

Added 3 mouse handler FFI stubs to the incremental test harness so it continues to compile:

```scheme
(define-foreign register-mouse-down-handler "app" "registerMouseDownHandler"
  (ref null extern) -> none)
(define-foreign register-mouse-move-handler "app" "registerMouseMoveHandler"
  (ref null extern) -> none)
(define-foreign register-mouse-up-handler "app" "registerMouseUpHandler"
  (ref null extern) -> none)
```

Matching no-op JavaScript stubs added to `envdraw-test.html`.

### 8. Project Infrastructure

- **`package.json`** — Node.js project with Puppeteer dependency and test scripts
- **`.gitignore`** — Excludes `node_modules/`, screenshot PNGs, compiled `.wasm` files (except Hoot runtime files `reflect.wasm`, `wtf8.wasm`)

---

## Bugs Found and Fixed

### 1. Double Canvas Transform (Root Cause of Elements at Origin)

**Symptom:** All environment diagram elements rendered as an unreadable blob at the canvas origin. Frames and procedures were stacked on top of each other despite the placement algorithm computing distinct positions.

**Root cause:** Two layers of coordinate transforms competed:
1. JavaScript's `getCanvasContext()` applied DPR scaling + pan offset + zoom level
2. Scheme's `render-scene` applied its own camera transforms (`canvas-scale!` + `canvas-translate!`) on top

The compound transform effectively squared the zoom and doubled the translation, pushing everything to incorrect coordinates. Additionally, `canvas-clear-rect!` ran in the transformed space, only clearing a fraction of the visible canvas — meaning previous frames ghosted.

**Fix:** Single source of truth — JavaScript owns all canvas transforms. Scheme's `render-scene` was stripped to just `(render-node ctx root 0 0)`. The `*get-fresh-context*` thunk ensures every render frame starts from a clean, correctly-transformed canvas state.

### 2. Stale Cached Canvas Context

**Symptom:** After the first render, subsequent renders might use a stale context reference, causing `clearRect` to fail and transforms to accumulate.

**Root cause:** `request-render!` used a cached `*render-ctx*` that was set once at boot. The HTML5 Canvas 2D context object itself is persistent, but the transform state accumulates across calls if not reset.

**Fix:** `request-render!` calls `(*get-fresh-context*)` each frame, which in Wasm mode calls `getCanvasContext()` — resetting the transform, clearing the canvas, and reapplying DPR + pan + zoom.

### 3. Pan vs. Drag Interference

**Symptom:** Attempting to drag a node would also pan the canvas, or clicking on a node would start an unwanted pan.

**Root cause:** Mouse events weren't differentiated between "user wants to drag a node" and "user wants to pan the view."

**Fix:** On mouse-down, JavaScript first asks Scheme to hit-test the scene graph. If a node is found, Scheme sets `*drag-node*` and the interaction enters node-drag mode. If no node is hit, the interaction enters pan mode — but only after a 3px movement threshold to prevent accidental pans on simple clicks. On entering pan mode, any started drag is cancelled via `mouseUp(0, 0)`.

---

## Architecture Changes

### Before (Phase 3)
```
Mouse event → JS handler → (no scene interaction)
Render: JS getCanvasContext() → Scheme render-scene {clear, save, scale, translate, walk tree, restore}
```

### After (Phase 4)
```
Mouse event → JS clientToScene() → Scheme hit-test → drag OR pan mode
Render: Scheme request-render! → *get-fresh-context* thunk → JS getCanvasContext() {reset, clear, setTransform(DPR+pan+zoom)} → return ctx → Scheme render-node {walk tree}
```

The key architectural insight is the **`*get-fresh-context*` thunk** — a polymorphic hook that allows the same rendering code to work in both environments:
- **Native Guile tests:** Returns a cached stub context (no canvas to clear)
- **Wasm browser:** Calls FFI to reset/clear/transform the real canvas each frame

---

## Files Created or Modified

### New Files

| File | Lines | Description |
|------|------:|-------------|
| `test/browser-test.mjs` | 455 | Puppeteer end-to-end test suite |
| `package.json` | 20 | Node.js project config with test scripts |
| `.gitignore` | 6 | Exclude build artifacts and node_modules |

### Rewritten Files

| File | Lines | Description |
|------|------:|-------------|
| `web/index.html` | 91 | Redesigned app shell — toolbar, canvas, sidebar, REPL |
| `web/style.css` | 584 | Complete CSS rewrite — design tokens, dot grid, responsive |
| `web/boot.js` | 596 | Pan/zoom, node drag, resize handle, keyboard shortcuts |

### Modified Files

| File | Lines | Change |
|------|------:|--------|
| `src/render/renderer.scm` | 174 | Removed camera transforms from `render-scene` |
| `src/ui/web-observer.scm` | 364 | `*get-fresh-context*` thunk, drag-and-drop handlers |
| `web/envdraw.scm` | 430 | 3 mouse FFI bindings, `*get-fresh-context*` override in `boot!` |
| `web/envdraw-test.scm` | 302 | 3 mouse handler FFI stubs |
| `web/envdraw-test.html` | 54 | 3 mouse handler no-op JS imports |

---

## Test Results

**Native Guile tests:** 82/82 pass (31 evaluator + 51 phase-2 scene graph/placement)
```
$ guile --no-auto-compile test-evaluator.scm   → 31/31 pass
$ guile --no-auto-compile test-phase2.scm      → 51/51 pass
```

**Wasm compilation:** Successful — 939 KB, ~5 seconds
```
$ ./build.sh
Compiling web/envdraw.scm  →  web/envdraw.wasm ...
wrote `web/envdraw.wasm'
   939K  web/envdraw.wasm     5.0s
```

**Browser tests:** 22/22 pass (Puppeteer, headless Chromium)
```
$ npm test
=== EnvDraw Browser Tests ===
  ✓ Page loaded without network errors
  ✓ Wasm module booted successfully (status=Ready)
  ✓ No JS errors
  ✓ Empty state placeholder is visible
  ✓ REPL input appears in trace panel
  ✓ Result appears in trace panel
  ✓ Canvas has non-white pixels (something was drawn)
  ✓ Diagram not stuck at origin
  ✓ Diagram has reasonable size
  ✓ Empty state is hidden after first eval
  ...
  22 passed, 0 failed, 22 total
```

---

## What Remains

### Phase 5: Advanced Features
- [ ] Stepping UI — Step/Continue buttons should suspend the evaluator fiber until clicked; `on-wait-for-step` currently does `(values)` (no-op)
- [ ] GC button — `on-gc-mark` and `on-gc-sweep` are no-ops; need to reduce opacity / remove garbage nodes
- [ ] Pointer re-routing after drag — when a node is dragged, pointer lines should be recalculated; `handle-mouse-up!` has a TODO for this
- [ ] Smooth pointer animation — original STk version had animated arrows
- [ ] Mobile-friendly layout — basic responsive CSS exists but touch events and smaller breakpoints need work
- [ ] Fit-to-view — the "⊞" button currently resets to a fixed offset; should compute the scene graph bounding box and auto-fit
- [ ] `set!` / mutation — verify that variable reassignment updates diagram correctly
- [ ] Diagram persistence — save/restore diagram state across page reloads

### Known Limitations
- **Safari** not supported (no Wasm GC / tail calls)
- **Hoot quasiquote bug** — single quasiquote with 80+ unquotes crashes; work around by splitting into smaller expressions
- **`try` instruction deprecation** — Firefox warns about the deprecated Wasm exception handling `try` instruction; requires upstream Hoot fix
- **Pointer re-routing** — after dragging a node, pointer arrow lines still point to the original position until the next evaluation triggers a re-render with recalculated pointers
