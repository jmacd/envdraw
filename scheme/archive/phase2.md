# EnvDraw Web Port — Phase 2 Report

**Date:** February 21, 2026  
**Author:** Josh MacDonald  
**Phase:** Scene Graph Layout & Pointer Routing

---

## Summary

Phase 2 ported the original EnvDraw layout engine — the algorithms that decide *where* diagram elements go and *how* arrows route between them. Three new source files (1,020 LOC) replace the simple grid layout from Phase 1 with the original convex-hull placement algorithm and all six pointer-routing strategies from the 1995 codebase.

**Key result:** 82/82 tests passing (31 evaluator + 51 layout/pointer).

---

## What Was Done

### 1. Convex-Hull Placement Algorithm (`placement.scm`, 492 LOC)

Ported from `placement.stk` (644 LOC). This is the algorithm that positions new diagram elements (frames, procedures, cell trees) around the perimeter of the existing layout without overlapping.

The core data structure is a **metropolis** — a convex hull represented as a circular doubly-linked list of corner points. When a new block is placed:

1. **`find-closest-point`** — O(n) scan to find the hull vertex nearest to the desired location (typically the parent object).
2. **`place-on-convex-corner`** — Inserts the block adjacent to a convex hull vertex by extending two new edges.
3. **`place-on-concave-corner`** — Fits the block into a concave gap, or if it doesn't fit, removes vertices and recurses.
4. **`smooth-hull`** — Post-processing pass that removes coincident points, collinear segments, and small gaps (< 100px).
5. **`regenerate-hull`** — Full reconstruction via X-axis sweep-line scan, producing two half-chains that are stitched into a ring. O(N log N) in the number of diagram elements.

The high-level API is `place-widget!`, which creates the metropolis on first invocation and delegates to `place-new-block` thereafter.

**Porting changes from STklos → R7RS:**
- `<metropolis>` STklos class → `define-record-type`
- GOOPS `define-method` on `+`, `-`, `*` for lists → explicit `vec+`/`vec-`/`vec*` calls
- `(1/2 x)` → `(* 0.5 x)` (STk had `1/2` as a function alias)
- `(slot-ref/slot-set!)` → record field accessors
- `(provide/require)` guards → removed (load-once handled by main.scm)

### 2. Cell Profiles & Layout Constants (`profiles.scm`, 123 LOC)

Ported from `view-profiles.stk` (300 LOC). A "profile" is a 5-element list describing how a cons-cell subtree should be sized and how its car/cdr children are positioned:

```
(xsize ysize xpos carpos cdrpos)
```

**`add-profiles`** combines the profiles of a cell's car and cdr children using one of two layout strategies:
- **Tree mode** (`#t`): children side by side below the parent cell — used for association lists and trees.
- **List mode** (`#f`): cdr extends horizontally, car drops vertically — used for standard lists.

This file also defines all the drawing constants that were scattered across the original codebase:

| Constant | Value | Purpose |
|----------|------:|---------|
| `CELL_SIZE` | 30 | Half-width of a cons cell (full cell = 60×30) |
| `SCALE` | 30 | Default spacing unit |
| `PROCEDURE_DIAMETER` | 30 | Circle diameter for procedure objects |
| `PROCEDURE_RADIUS` | 15 | Half of above |
| `BENT_POINTER_OFFSET` | 15 | Clearance for bent pointer segments |
| `POINTER_WIDTH` | 2 | Normal arrow line width |
| `GCD_POINTER_WIDTH` | 1 | Dimmed (GC'd) arrow line width |

Plus derived constants for pointer offsets (`CARP_OFFSET`, `CDRP_OFFSET`, correction vectors, basis vectors).

### 3. Pointer Routing (`pointers.scm`, 405 LOC)

Consolidated port from three original files:
- `simple-pointer.stk` (123 LOC) — base pointer motion
- `env-pointers.stk` (368 LOC) — frame-to-frame, frame-to-procedure, procedure-to-frame
- `view-pointers.stk` (223 LOC) — cell-to-cell, cell-to-atom

Six routing strategies, each a pure function from source/target geometry to a polyline coordinate list:

| Strategy | Function | Used For |
|----------|----------|----------|
| **env** | `find-env-pointer` | Frame ↔ frame arrows |
| **cell** | `find-cell-pointer` | Cons cell ↔ cons cell (car/cdr) |
| **atom** | `find-atom-pointer` | Cell → atom (simple text value) |
| **to-proc** | `to-proc-find-pointer` | Frame binding → procedure circle |
| **from-proc** | `from-proc-find-pointer` | Procedure → enclosing frame |
| **cell-to-proc** | `cell-to-proc-find-pointer` | Cons cell → procedure |

**Algorithm highlights:**

- **`find-env-pointer`**: Given two rectangle bounds, merges their x- and y-coordinates into a sorted ordering, detects overlap per axis, and chooses straight (1-segment) or bent (3-segment) routing. Handles all four cases: x-overlap only, y-overlap only, no overlap, and full containment.

- **`find-cell-pointer`**: Context-sensitive routing for cons-cell arrows. Handles nine cases based on relative position and distance, including drop-through (vertical), wrap-around (multi-segment), and cut-corner optimizations. Uses a random offset (`spacing`) to visually distinguish parallel pointers.

- **`find-procedure-head`**: Routes the final segment of a pointer to the circle representing a procedure object, choosing entry from left/right/top based on approach direction.

**Architectural change:** The original code stored pointer state in STklos objects with motion hooks that updated coordinates when objects moved. The port extracts the geometry as pure functions — the caller provides positions and gets back coordinates. A `<pointer-state>` record is defined for future use when drag-and-drop requires incremental updates, but the current code uses the stateless `compute-pointer-path` entry point.

### 4. Integration Changes

**`web-observer.scm`** (rewritten, 300 LOC): Replaced the Phase 1 grid layout with:
- Hull-based placement via `place-widget!` — new frames and procedures are positioned by the convex-hull algorithm near their parent objects
- Proper pointer routing via `compute-pointer-path` — environment arrows use `find-env-pointer` instead of hardcoded center-to-center lines
- Metropolis state and placed-rectangle tracking for future hull regeneration
- Additional bookkeeping: `*proc-frame-map*` tracks which frame each procedure was created in

**`environments.scm`** (modified): Made `frame-info-id` mutable (`set-frame-info-id!`). The observer's `on-frame-created` callback returns a scene-graph node ID, which is now captured back into the `<frame-info>` record. This unifies the ID namespace — pointer routing, binding placement, and env-pointer callbacks all use the same ID.

**`main.scm`** (modified): Added three new `load-relative` calls in dependency order:
```scheme
(load-relative "model/profiles.scm")    ; after color.scm
(load-relative "model/placement.scm")   ; after profiles.scm
(load-relative "model/pointers.scm")    ; after placement.scm
```

---

## Bug Fixed

**Frame-ID mismatch** — The evaluator generated IDs like `"frame-1"` in `make-frame` (environments.scm), while the observer created scene-graph nodes with IDs like `"g2"`. When the observer later looked up `"frame-1"` in `*frame-nodes*` (keyed by `"g2"`), the `assoc` failed silently, and no pointer was drawn from procedures to their enclosing frames.

Fix: the observer's `on-frame-created` returns the node ID, and `extend-environment` stores it back via `set-frame-info-id!`. All subsequent lookups use the unified ID.

---

## Source Files (cumulative)

### Scheme Source (3,545 LOC across 14 files)

| File | Lines | Ported From | Description |
|------|------:|-------------|-------------|
| `src/main.scm` | 135 | *(new)* | Entry point, load orchestrator, REPL |
| `src/core/meta.scm` | 666 | `meta.stk` | Metacircular evaluator |
| `src/core/environments.scm` | 264 | `environments.stk` | Frames, bindings, environment ops |
| `src/core/eval-observer.scm` | 169 | *(new)* | Observer protocol (14 callbacks) |
| `src/core/stacks.scm` | 105 | `stacks.stk` | Stack and doubly-linked list |
| `src/model/scene-graph.scm` | 302 | `view-classes.stk` et al. | Retained-mode node tree |
| `src/model/math.scm` | 155 | `math.stk` | Vector arithmetic |
| `src/model/color.scm` | 90 | `color.stk` | RGB colors, CSS conversion |
| `src/model/placement.scm` | 492 | `placement.stk` | **Convex-hull placement** |
| `src/model/profiles.scm` | 123 | `view-profiles.stk` | **Cell profiles & constants** |
| `src/model/pointers.scm` | 405 | `env-pointers.stk` et al. | **All pointer routing** |
| `src/render/canvas-ffi.scm` | 162 | *(new)* | Canvas2D stubs / FFI |
| `src/render/renderer.scm` | 177 | *(new)* | Scene-graph renderer |
| `src/ui/web-observer.scm` | 300 | `env-toplev.stk` et al. | Observer → scene graph |

### Tests (361 LOC, 82 tests)

| File | Tests | Description |
|------|------:|-------------|
| `test-evaluator.scm` | 31 | Evaluator correctness |
| `test-phase2.scm` | 51 | Profiles, placement, pointers, integration |

---

## Test Results

```
=== EnvDraw Evaluator Tests ===
31 passed, 0 failed, 31 total — All tests passed!

=== Phase 2 Tests ===
--- Profile computation ---           7/7 PASS
--- Constants ---                     5/5 PASS
--- Placement: metropolis ---         9/9 PASS
--- Pointer routing: env pointers --- 3/3 PASS
--- Pointer routing: cell pointers --- 5/5 PASS
--- Pointer routing: proc pointers --- 3/3 PASS
--- Coordinate helpers ---            3/3 PASS
--- compute-pointer-path ---          4/4 PASS
--- Scene graph + placement ---      12/12 PASS
51 passed, 0 failed, 51 total — All tests passed!
```

---

## What Remains

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
- The `--no-auto-compile` flag is needed for Guile tests
