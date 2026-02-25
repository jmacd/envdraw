# Phase 5 — D3.js Layout & SVG Rendering

## Problem Statement

The current custom Canvas2D renderer with convex-hull placement starts
the diagram at `(50, 50)` with `panX=0, panY=0` and no viewport
awareness.  Each new element grows outward from the hull perimeter,
quickly placing items off-screen.  The user must manually pan/zoom to
find new content.  Manual drag-and-drop exists but pointer arrows need
recalculation, and there is no automatic layout or animation.

**Root cause:** The placement algorithm has no concept of the viewport,
center, or desired spatial relationships between diagram elements.

## Proposed Solution

Replace Canvas2D rendering + convex-hull placement with:

- **D3-force** for automatic force-directed layout with hierarchy
- **SVG** rendering via D3 data-binding
- **D3-zoom** for pan/zoom (replacing custom Canvas2D transforms)
- **D3-drag** for node dragging (replacing custom scene-graph hit-test)
- **D3 transitions** for smooth animation of new nodes

## Architecture Change

### Before (Phase 4)

```
Evaluator → Observer hooks → Scene graph build → Placement → Canvas2D render
  (Scheme)    (Scheme)         (Scheme)           (Scheme)    (Scheme→FFI→JS)
```

### After (Phase 5)

```
Evaluator → Observer hooks → FFI graph commands → D3 visualization
  (Scheme)    (Scheme)         (Scheme→JS)          (pure JS)
```

### What gets removed from Scheme:
- `scene-graph.scm` — no more node records, hit-test, tree ops
- `renderer.scm` — no more Canvas2D drawing
- `placement.scm` — no more convex-hull layout
- `pointers.scm` — no more manual pointer routing
- All Canvas2D FFI calls (`canvas-*` foreign functions)
- Drag/pan/zoom handling in `web-observer.scm`

### What stays in Scheme:
- `meta.scm` — metacircular evaluator (unchanged)
- `environments.scm` — environment model (unchanged)
- `eval-observer.scm` — observer interface (unchanged)
- `web-observer.scm` — simplified: emits FFI graph commands
- `stacks.scm`, `math.scm`, `color.scm` — utilities

### What moves to JS:
- `d3-diagram.js` — all visualization: D3-force simulation, SVG
  rendering, zoom, drag, animations, edge routing
- D3 library (d3 v7 via CDN or vendored)

## Data Model (Scheme → JS via FFI)

The Scheme observer fires simple FFI commands:

```
d3AddFrame(id, name, parentId, x, y, width, height, color)
d3AddProcedure(id, lambdaText, frameId, color)
d3AddBinding(frameId, varName, value, valueType, procId)
d3AddEdge(fromId, toId, edgeType)   // 'env', 'binding', 'proc-env'
d3UpdateBinding(frameId, varName, newValue, valueType)
d3RemoveNode(id)                     // GC
d3RemoveEdge(fromId, toId)           // GC
d3RequestRender()
```

## D3-force Layout Design

### Forces:
- **forceCenter** — center simulation in viewport
- **forceCollide** — prevent node overlap (with padding)
- **forceLink** — edges as springs (env-pointers, proc-env arrows)
- **forceY** — hierarchical: push global frame up, children down based
  on depth
- **forceManyBody** — mild repulsion between nodes
- Custom compound force: keep procedures near their binding frame

### Node types (D3 data):
- `{ type: 'frame', id, name, parentId, width, height, color, bindings: [...] }`
- `{ type: 'procedure', id, lambdaText, frameId, color }`

### Edge types (D3 data):
- `{ type: 'env', source: childFrameId, target: parentFrameId }`
- `{ type: 'binding', source: frameId, target: procId, varName }`
- `{ type: 'proc-env', source: procId, target: frameId }`

## SVG Structure

```html
<svg id="diagram-svg">
  <defs>
    <marker id="arrowhead" .../>
  </defs>
  <g class="zoom-layer">
    <g class="edges">
      <path class="edge env" .../>
      <path class="edge binding" .../>
    </g>
    <g class="nodes">
      <g class="frame" data-id="...">
        <rect class="frame-bg" rx="6" .../>
        <line class="frame-sep" .../>
        <text class="frame-title">GLOBAL</text>
        <g class="binding" data-var="x">
          <text>x: 42</text>
        </g>
      </g>
      <g class="procedure" data-id="...">
        <rect class="proc-bg" rx="4" .../>
        <line class="proc-divider" .../>
        <circle class="dot-left" .../>
        <circle class="dot-right" .../>
        <text class="lambda-label">(lambda (n) ...)</text>
      </g>
    </g>
  </g>
</svg>
```

## Implementation Steps

### 5.1: Add D3.js and SVG skeleton
- Include D3 v7 (CDN: `d3.min.js`)
- Add `<svg id="diagram-svg">` to index.html (replacing canvas)
- Create `d3-diagram.js` with basic module structure

### 5.2: D3 force simulation + SVG rendering
- Implement `d3-diagram.js`:
  - `addFrame()`, `addProcedure()`, `addBinding()`, `addEdge()`
  - `removeNode()`, `updateBinding()`
  - D3-force simulation with the described forces
  - SVG rendering with D3 enter/update/exit pattern
  - D3-zoom and d3-drag

### 5.3: New FFI bindings
- Add `define-foreign` for `d3AddFrame`, `d3AddProcedure`, etc.
- Simplify `web-observer.scm` to call these instead of building
  scene graph

### 5.4: Wire boot.js
- Remove Canvas2D setup, pan/zoom, drag handlers
- Initialize D3 diagram module
- Wire Scheme FFI calls to d3-diagram.js functions

### 5.5: Polish and test
- Animation tuning (transition durations, force parameters)
- Edge routing refinement (curved paths, arrow placement)
- GC animation (fade out)
- Fit-to-view button
- Rebuild and test
