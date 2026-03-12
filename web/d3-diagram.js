/**
 * d3-diagram.js — D3.js force-directed environment diagram
 *
 * Manages an SVG visualization of SICP-style environment diagrams
 * using D3-force for layout, D3-zoom for pan/zoom, and D3-drag
 * for node dragging.
 *
 * The Scheme evaluator pushes graph mutations via FFI:
 *   addFrame, addProcedure, addBinding, addEdge,
 *   updateBinding, removeNode, removeEdge
 *
 * Copyright (C) 2026 Josh MacDonald
 */

const EnvDiagram = (() => {
  // ─── Data ────────────────────────────────────────────────────────
  let nodes = [];     // { id, type, name, parentId, width, height, color, ... }
  let edges = [];     // { id, source, target, edgeType, ... }
  let bindings = {};  // frameId → [ { varName, value, valueType, procId } ]

  // ─── D3 handles ─────────────────────────────────────────────────
  let svg, zoomLayer, edgeGroup, nodeGroup, defs;
  let simulation;
  let zoomBehavior;
  let width = 800, height = 600;
  let autoFitTimer = null;  // schedules fitToView after first mutations
  let renderTimer = null;   // debounces simulation restarts across rapid mutations

  // ─── Configuration ──────────────────────────────────────────────
  const FRAME_MIN_W = 140;
  const FRAME_HEADER_H = 24;
  const BINDING_H = 18;
  const BINDING_PAD = 8;
  const PROC_CELL_W = 30;
  const PROC_CELL_H = 30;
  const PROC_LABEL_H = 18;
  const PAIR_CELL_W = 30;   // width of each half of a cons cell
  const PAIR_CELL_H = 30;   // height of a cons cell
  const PAIR_ATOM_PAD = 6;  // padding around atom labels
  const ANIM_DURATION = 400;

  // Color palette for frames — muted cool pastels
  const COLORS = [
    "#c6def1", "#bde0d7", "#c8dbc7",
    "#d0d5e1", "#b7dae0", "#d6dceb"
  ];
  let colorIndex = 0;
  function nextColor() {
    const c = COLORS[colorIndex % COLORS.length];
    colorIndex++;
    return c;
  }
  function darken(hex) {
    // Quick darken — reduce each channel by ~30%
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    const f = 0.65;
    return `rgb(${Math.round(r * f)},${Math.round(g * f)},${Math.round(b * f)})`;
  }

  // ─── Helpers ────────────────────────────────────────────────────
  let edgeIdCounter = 0;
  function edgeId(from, to, type) {
    return `e-${from}-${to}-${type}`;
  }

  function nodeById(id) {
    return nodes.find(n => n.id === id);
  }

  function frameBindings(frameId) {
    return bindings[frameId] || [];
  }

  function computeFrameHeight(frameId) {
    const b = frameBindings(frameId);
    return FRAME_HEADER_H + Math.max(1, b.length) * BINDING_H + 8;
  }

  function computeFrameWidth(frameId, name) {
    const b = frameBindings(frameId);
    let maxW = name.length * 8 + 20;
    for (const binding of b) {
      const labelW = (binding.varName.length + 2 +
        (binding.valueType === "atom" ? binding.value.length : 3)) * 7 + 30;
      maxW = Math.max(maxW, labelW);
    }
    return Math.max(FRAME_MIN_W, maxW);
  }

  // ─── Initialization ─────────────────────────────────────────────
  function init(svgElement) {
    svg = d3.select(svgElement);
    const rect = svgElement.getBoundingClientRect();
    width = rect.width || 800;
    height = rect.height || 600;

    svg.attr("width", width).attr("height", height);

    // Arrow marker definition
    defs = svg.append("defs");
    defs.append("marker")
      .attr("id", "arrowhead")
      .attr("viewBox", "0 0 10 6")
      .attr("refX", 10)
      .attr("refY", 3)
      .attr("markerWidth", 10)
      .attr("markerHeight", 6)
      .attr("orient", "auto")
      .append("path")
      .attr("d", "M0,0 L10,3 L0,6 Z")
      .attr("fill", "#666");

    // Arrowhead for env pointers (slightly different color)
    defs.append("marker")
      .attr("id", "arrowhead-env")
      .attr("viewBox", "0 0 10 6")
      .attr("refX", 10)
      .attr("refY", 3)
      .attr("markerWidth", 10)
      .attr("markerHeight", 6)
      .attr("orient", "auto")
      .append("path")
      .attr("d", "M0,0 L10,3 L0,6 Z")
      .attr("fill", "#888");

    // Arrowhead for pair (car/cdr) pointers
    defs.append("marker")
      .attr("id", "arrowhead-pair")
      .attr("viewBox", "0 0 10 6")
      .attr("refX", 10)
      .attr("refY", 3)
      .attr("markerWidth", 10)
      .attr("markerHeight", 6)
      .attr("orient", "auto")
      .append("path")
      .attr("d", "M0,0 L10,3 L0,6 Z")
      .attr("fill", "#444");

    // Zoom layer — nodes first so edges (arrows) render on top and
    // arrowheads are always visible even when they touch a shape.
    zoomLayer = svg.append("g").attr("class", "zoom-layer");
    nodeGroup = zoomLayer.append("g").attr("class", "nodes");
    edgeGroup = zoomLayer.append("g").attr("class", "edges")
      .attr("pointer-events", "none");

    // D3-zoom
    zoomBehavior = d3.zoom()
      .scaleExtent([0.1, 5])
      .on("zoom", (event) => {
        zoomLayer.attr("transform", event.transform);
      });
    svg.call(zoomBehavior);

    // Initialize force simulation
    simulation = d3.forceSimulation(nodes)
      .force("charge", d3.forceManyBody().strength(-150))
      .force("collide", d3.forceCollide().radius(d => {
        if (d.type === "frame")
          return Math.max(d.width, d.height) * 0.6 + 20;
        if (d.type === "pair-null" || d.type === "pair-atom")
          return Math.max(d.width || 14, d.height || 14) * 0.5 + 4;
        return Math.max(d.width || 60, d.height || 48) * 0.5 + 10;
      }).strength(0.8).iterations(2))
      .force("link", d3.forceLink(edges)
        .id(d => d.id)
        .distance(d => {
          if (d.edgeType === "env") return 160;
          if (d.edgeType === "proc-env") return 120;
          if (d.edgeType === "binding") return 130;
          if (d.edgeType === "car") return 65;
          if (d.edgeType === "cdr") return 70;
          return 120;
        })
        .strength(d => {
          if (d.edgeType === "env") return 0.2;
          if (d.edgeType === "binding") return 0.15;
          if (d.edgeType === "proc-env") return 0.15;
          if (d.edgeType === "car") return 0.6;
          if (d.edgeType === "cdr") return 0.6;
          return 0.2;
        })
      )
      .force("y", d3.forceY().y(d => {
        // Hierarchical: global at top, children below
        if (d.type === "frame") {
          const depth = getFrameDepth(d.id);
          return 80 + depth * 170;
        }
        // Procedures: same depth level as their enclosing frame, offset down
        if (d.type === "procedure" && d.frameId) {
          const frameDepth = getFrameDepth(d.frameId);
          return 80 + frameDepth * 170 + 30;
        }
        // Pair nodes: let link force position them, weak center pull
        if (d.type === "pair" || d.type === "pair-atom" || d.type === "pair-null") {
          return height / 2;
        }
        return height / 2;
      }).strength(d => {
        // Very strong Y keeps hierarchy stable
        if (d.type === "frame") return 1.0;
        if (d.type === "procedure") return 0.7;
        // Weak Y for pair nodes — link force does the positioning
        if (d.type === "pair" || d.type === "pair-atom" || d.type === "pair-null") return 0.02;
        return 0.3;
      }))
      .force("x", d3.forceX().x(d => {
        // Spread procedures to the right of their frame
        if (d.type === "procedure" && d.frameId) {
          const fn = nodeById(d.frameId);
          if (fn) return (fn.x || width / 2) + 180;
        }
        return width / 2;
      }).strength(d => {
        if (d.type === "procedure") return 0.12;
        if (d.type === "pair" || d.type === "pair-atom" || d.type === "pair-null") return 0.02;
        return 0.08;
      }))
      .velocityDecay(0.7)
      .alphaDecay(0.05)
      .on("tick", ticked)
      .stop();  // Don't auto-start; scheduleRender() handles restarts

    // Observe container resizing
    const ro = new ResizeObserver(() => {
      const rect = svgElement.getBoundingClientRect();
      width = rect.width || 800;
      height = rect.height || 600;
      svg.attr("width", width).attr("height", height);
      // Don't re-add forceCenter — we rely on forceY/forceX for positioning
      simulation.alpha(0.1).restart();
    });
    ro.observe(svgElement.parentElement);
  }

  function getFrameDepth(frameId) {
    const node = nodeById(frameId);
    if (!node || !node.parentId) return 0;
    return 1 + getFrameDepth(node.parentId);
  }

  // ─── Force tick → update SVG positions ──────────────────────────
  function ticked() {
    // Update edge paths
    edgeGroup.selectAll(".edge")
      .attr("d", d => computeEdgePath(d));

    // Update node positions
    nodeGroup.selectAll(".node")
      .attr("transform", d => `translate(${d.x - (d.width || 0) / 2},${d.y - (d.height || 0) / 2})`);
  }

  // ─── Edge path computation ──────────────────────────────────────
  function computeEdgePath(d) {
    const s = typeof d.source === "object" ? d.source : nodeById(d.source);
    const t = typeof d.target === "object" ? d.target : nodeById(d.target);
    if (!s || !t) return "";

    let sx, sy, tx, ty;
    const sw = s.width || FRAME_MIN_W;
    const sh = s.height || 60;
    const tw = t.width || FRAME_MIN_W;
    const th = t.height || 60;

    // Procedure dots are in the cons-cell rect, which sits at the top-left
    // of the node bounding box.  The node center (d.x, d.y) is the center
    // of the full bounding box (which includes the possibly-wider lambda
    // label text below the cell).  These helpers compute the cons-cell
    // center in world coords so arrows terminate at the actual cell.
    function procCellCX(node) {
      // Cons cell starts at local x=0, is PROC_CELL_W*2 wide.
      // Node is translated to (node.x - node.width/2, ...).
      // So cell center X = node.x - node.width/2 + PROC_CELL_W.
      return node.x - (node.width || PROC_CELL_W * 2) / 2 + PROC_CELL_W;
    }
    function procCellCY(node) {
      // Cons cell starts at local y=0, is PROC_CELL_H tall.
      // Node is translated to (..., node.y - node.height/2).
      // So cell center Y = node.y - node.height/2 + PROC_CELL_H/2.
      return node.y - (node.height || (PROC_CELL_H + PROC_LABEL_H)) / 2 + PROC_CELL_H / 2;
    }

    if (d.edgeType === "binding") {
      // From binding dot in source frame → target procedure or pair.
      // The dot is drawn inside the frame at a position that depends
      // on the variable name length — match renderBindings() exactly.
      const fb = frameBindings(s.id);
      const bindIdx = fb.findIndex(b => b.procId === t.id);
      const binding = bindIdx >= 0 ? fb[bindIdx] : null;
      const bindY = FRAME_HEADER_H + (bindIdx >= 0 ? bindIdx : 0) * BINDING_H + BINDING_H / 2;
      const varLen = binding ? binding.varName.length : 4;
      const dotLocalX = BINDING_PAD + (varLen + 1) * 7 + 14;
      // Source: dot position inside the frame (local → world)
      sx = s.x - sw / 2 + dotLocalX;
      sy = s.y - sh / 2 + bindY;
      if (t.type === "pair") {
        // Target: edge of pair cons-cell bounding box
        const pt = intersectNodeRect(t, sx, sy);
        tx = pt.x;
        ty = pt.y;
      } else {
        // Target: edge of procedure cons-cell (exclude label area)
        const pt = intersectNodeRect(t, sx, sy,
          PROC_CELL_W * 2, PROC_CELL_H, procCellCX(t), procCellCY(t));
        tx = pt.x;
        ty = pt.y;
      }
    } else if (d.edgeType === "car") {
      // From car-dot of source cons cell → target (pair, atom, null, or proc)
      sx = s.x - sw / 2 + PAIR_CELL_W / 2;
      sy = s.y;
      // Target: edge of target node
      if (t.type === "procedure") {
        const pt = intersectNodeRect(t, sx, sy,
          PROC_CELL_W * 2, PROC_CELL_H, procCellCX(t), procCellCY(t));
        tx = pt.x;
        ty = pt.y;
      } else {
        const pt = intersectNodeRect(t, sx, sy);
        tx = pt.x;
        ty = pt.y;
      }
    } else if (d.edgeType === "cdr") {
      // From cdr-dot of source cons cell → target
      sx = s.x - sw / 2 + PAIR_CELL_W * 1.5;
      sy = s.y;
      // Target: edge of target node
      if (t.type === "procedure") {
        const pt = intersectNodeRect(t, sx, sy,
          PROC_CELL_W * 2, PROC_CELL_H, procCellCX(t), procCellCY(t));
        tx = pt.x;
        ty = pt.y;
      } else {
        const pt = intersectNodeRect(t, sx, sy);
        tx = pt.x;
        ty = pt.y;
      }
    } else if (d.edgeType === "proc-env") {
      // Source is procedure, target is frame
      // From right-dot of procedure → nearest edge of target frame
      sx = s.x - (s.width || PROC_CELL_W * 2) / 2 + PROC_CELL_W * 1.5;
      sy = procCellCY(s);
      // Target: nearest point on frame border
      const targetPt = nearestFrameEdge(t, sx, sy);
      tx = targetPt.x;
      ty = targetPt.y;
    } else if (d.edgeType === "env") {
      // Child frame → parent frame
      // Source: top center of child frame
      sx = s.x;
      sy = s.y - sh / 2;
      // Target: nearest point on parent frame border
      const targetPt = nearestFrameEdge(t, sx, sy);
      tx = targetPt.x;
      ty = targetPt.y;
    } else {
      sx = s.x;
      sy = s.y;
      const pt = intersectNodeRect(t, sx, sy);
      tx = pt.x;
      ty = pt.y;
    }

    // Use quadratic Bézier for a gentle curve
    const mx = (sx + tx) / 2;
    const my = (sy + ty) / 2;
    // Offset control point perpendicular to the line
    const edx = tx - sx, edy = ty - sy;
    const len = Math.sqrt(edx * edx + edy * edy) || 1;
    const ndx = -edy;
    const ndy = edx;
    // Curvature factor varies by edge type
    let curveFactor = 0;
    if (d.edgeType === "binding") curveFactor = 0.15;
    else if (d.edgeType === "proc-env") curveFactor = 0.12;
    else if (d.edgeType === "env") curveFactor = 0.1;
    else if (d.edgeType === "car" || d.edgeType === "cdr") curveFactor = 0.08;
    const cx = mx + (ndx / len) * len * curveFactor;
    const cy = my + (ndy / len) * len * curveFactor;

    return `M${sx},${sy} Q${cx},${cy} ${tx},${ty}`;
  }

  /** Find the nearest point on a frame's border for an arrow target */
  function nearestFrameEdge(frameNode, fromX, fromY) {
    const fw = frameNode.width || FRAME_MIN_W;
    const fh = frameNode.height || 60;
    const fl = frameNode.x - fw / 2;
    const fr = frameNode.x + fw / 2;
    const ft = frameNode.y - fh / 2;
    const fb = frameNode.y + fh / 2;

    // Try all 4 edges and pick the one closest to the source point
    const candidates = [
      { x: Math.max(fl, Math.min(fr, fromX)), y: ft },  // top
      { x: Math.max(fl, Math.min(fr, fromX)), y: fb },  // bottom
      { x: fl, y: Math.max(ft, Math.min(fb, fromY)) },  // left
      { x: fr, y: Math.max(ft, Math.min(fb, fromY)) },  // right
    ];

    let best = candidates[0];
    let bestDist = Infinity;
    for (const c of candidates) {
      const d = Math.sqrt((c.x - fromX) ** 2 + (c.y - fromY) ** 2);
      if (d < bestDist) {
        bestDist = d;
        best = c;
      }
    }
    return best;
  }

  /**
   * Intersect the line from (fromX, fromY) through a rectangular node's
   * centre with the node's bounding-box edge.  Optional overrides let
   * callers target a sub-region (e.g. only the cons-cell portion of a
   * procedure node, excluding the label area below it).
   */
  function intersectNodeRect(node, fromX, fromY, overrideW, overrideH, overrideCX, overrideCY) {
    const w  = overrideW  !== undefined ? overrideW  : (node.width  || 60);
    const h  = overrideH  !== undefined ? overrideH  : (node.height || 60);
    const cx = overrideCX !== undefined ? overrideCX : node.x;
    const cy = overrideCY !== undefined ? overrideCY : node.y;
    const hw = w / 2;
    const hh = h / 2;

    const dx = fromX - cx;
    const dy = fromY - cy;
    const absDx = Math.abs(dx);
    const absDy = Math.abs(dy);

    // Degenerate — source is exactly at centre
    if (absDx < 0.001 && absDy < 0.001) return { x: cx, y: cy - hh };

    let scale;
    if (absDx < 0.001) {
      scale = hh / absDy;
    } else if (absDy < 0.001) {
      scale = hw / absDx;
    } else if (hw * absDy <= hh * absDx) {
      // Hits left or right edge
      scale = hw / absDx;
    } else {
      // Hits top or bottom edge
      scale = hh / absDy;
    }

    return { x: cx + dx * scale, y: cy + dy * scale };
  }

  // ─── SVG rendering (D3 enter/update/exit) ──────────────────────

  // Batch rendering: mutation methods call scheduleRender() instead of
  // render() directly.  This coalesces all mutations from a synchronous
  // eval into a single DOM update.
  let renderScheduled = false;
  function scheduleRender() {
    if (!renderScheduled) {
      renderScheduled = true;
      // Stop the simulation immediately so it doesn't tick with stale data
      // while we accumulate mutations.  It will restart in the deferred render.
      simulation.stop();
      setTimeout(() => {
        renderScheduled = false;
        render();
      }, 0);
    }
  }

  function render() {
    // Prune edges whose source or target node no longer exists.
    // With batched rendering, a node may be removed after edges were added
    // in the same synchronous eval pass.
    const nodeIds = new Set(nodes.map(n => n.id));
    edges = edges.filter(e => {
      const sid = typeof e.source === "object" ? e.source.id : e.source;
      const tid = typeof e.target === "object" ? e.target.id : e.target;
      return nodeIds.has(sid) && nodeIds.has(tid);
    });

    renderEdges();
    renderNodes();

    // Debounce simulation restart — a single eval step triggers
    // multiple mutations (frame + bindings + procedure + edges) in
    // rapid succession.  Restarting on every call pumps too much
    // energy into the system.  Instead, batch them.
    if (renderTimer !== null) clearTimeout(renderTimer);
    renderTimer = setTimeout(() => {
      renderTimer = null;
      // Stop simulation while updating data to avoid tick() seeing stale refs
      simulation.stop();
      // Re-prune before feeding edges to the simulation — more mutations
      // may have occurred between render() and this deferred restart.
      const ids = new Set(nodes.map(n => n.id));
      edges = edges.filter(e => {
        const s = typeof e.source === "object" ? e.source.id : e.source;
        const t = typeof e.target === "object" ? e.target.id : e.target;
        return ids.has(s) && ids.has(t);
      });
      simulation.nodes(nodes);
      simulation.force("link").links(edges);
      simulation.alpha(0.2).restart();
    }, 50);

    // Auto-fit: debounce so we fit once after a burst of mutations settles
    if (autoFitTimer !== null) clearTimeout(autoFitTimer);
    autoFitTimer = setTimeout(() => {
      autoFitTimer = null;
      fitToView();
    }, 900);
  }

  function renderEdges() {
    const sel = edgeGroup.selectAll(".edge")
      .data(edges, d => d.id);

    // Enter
    sel.enter()
      .append("path")
      .attr("class", d => `edge ${d.edgeType}`)
      .attr("fill", "none")
      .attr("stroke", d => {
        if (d.edgeType === "env") return "#888";
        if (d.edgeType === "proc-env") return "#6a9";
        if (d.edgeType === "binding") return "#555";
        if (d.edgeType === "car" || d.edgeType === "cdr") return "#444";
        return "#666";
      })
      .attr("stroke-width", d => d.edgeType === "env" ? 1.0 : 1.2)
      .attr("stroke-dasharray", d => d.edgeType === "env" ? "4,3" : null)
      .attr("marker-end", d => {
        if (d.edgeType === "env") return "url(#arrowhead-env)";
        if (d.edgeType === "car" || d.edgeType === "cdr") return "url(#arrowhead-pair)";
        return "url(#arrowhead)";
      })
      .attr("opacity", 0)
      .transition().duration(ANIM_DURATION)
      .attr("opacity", 1);

    // Exit
    sel.exit()
      .transition().duration(ANIM_DURATION)
      .attr("opacity", 0)
      .remove();
  }

  function renderNodes() {
    const sel = nodeGroup.selectAll(".node")
      .data(nodes, d => d.id);

    // Enter: create groups
    const enter = sel.enter()
      .append("g")
      .attr("class", d => `node ${d.type}`)
      .attr("opacity", 0)
      .call(d3.drag()
        .on("start", dragStarted)
        .on("drag", dragged)
        .on("end", dragEnded));

    // Render frame interiors
    enter.filter(d => d.type === "frame").each(function (d) {
      renderFrame(d3.select(this), d);
    });

    // Render procedure interiors
    enter.filter(d => d.type === "procedure").each(function (d) {
      renderProcedure(d3.select(this), d);
    });

    // Render pair (cons cell) interiors
    enter.filter(d => d.type === "pair").each(function (d) {
      renderPairCell(d3.select(this), d);
    });

    // Render pair atom (leaf value) interiors
    enter.filter(d => d.type === "pair-atom").each(function (d) {
      renderPairAtom(d3.select(this), d);
    });

    // Render pair null (empty list terminator)
    enter.filter(d => d.type === "pair-null").each(function (d) {
      renderPairNull(d3.select(this), d);
    });

    // Animate in
    enter.transition().duration(ANIM_DURATION)
      .attr("opacity", 1);

    // Update: reposition + re-render internals
    sel.each(function (d) {
      const g = d3.select(this);
      if (d.type === "frame") updateFrame(g, d);
    });

    // Exit
    sel.exit()
      .transition().duration(ANIM_DURATION)
      .attr("opacity", 0)
      .remove();
  }

  // ─── Frame SVG ──────────────────────────────────────────────────
  function renderFrame(g, d) {
    const w = d.width || FRAME_MIN_W;
    const h = d.height || 60;
    const color = d.color || "#c6def1";
    const stroke = darken(color);

    // Background rect
    g.append("rect")
      .attr("class", "frame-bg")
      .attr("width", w).attr("height", h)
      .attr("rx", 6).attr("ry", 6)
      .attr("fill", color)
      .attr("stroke", stroke)
      .attr("stroke-width", 1);

    // Separator line
    g.append("line")
      .attr("class", "frame-sep")
      .attr("x1", 0).attr("y1", FRAME_HEADER_H)
      .attr("x2", w).attr("y2", FRAME_HEADER_H)
      .attr("stroke", stroke)
      .attr("stroke-width", 0.5);

    // Title
    g.append("text")
      .attr("class", "frame-title")
      .attr("x", w / 2).attr("y", 16)
      .attr("text-anchor", "middle")
      .attr("font-size", "11px")
      .attr("font-weight", "bold")
      .attr("font-family", "sans-serif")
      .attr("fill", "#333")
      .text(d.name);

    // Bindings
    renderBindings(g, d);
  }

  function renderBindings(g, d) {
    const b = frameBindings(d.id);
    // Remove old binding elements
    g.selectAll(".binding").remove();

    b.forEach((binding, i) => {
      const by = FRAME_HEADER_H + i * BINDING_H + BINDING_H / 2;
      const bg = g.append("g")
        .attr("class", "binding")
        .attr("data-var", binding.varName)
        .attr("transform", `translate(0, 0)`);

      // Variable name
      bg.append("text")
        .attr("x", BINDING_PAD)
        .attr("y", by + 4)
        .attr("font-size", "11px")
        .attr("font-family", "monospace")
        .attr("font-weight", "bold")
        .attr("fill", "#444")
        .text(binding.varName + ":");

      if (binding.valueType === "atom") {
        // Inline value
        const valX = BINDING_PAD + (binding.varName.length + 1) * 7 + 6;
        bg.append("text")
          .attr("class", "val-label")
          .attr("x", valX)
          .attr("y", by + 4)
          .attr("font-size", "11px")
          .attr("font-family", "monospace")
          .attr("fill", "#666")
          .text(binding.value);
      } else if (binding.valueType === "procedure" || binding.valueType === "pair") {
        // Small dot (pointer origin for binding→proc or binding→pair edge)
        const dotX = BINDING_PAD + (binding.varName.length + 1) * 7 + 14;
        bg.append("circle")
          .attr("class", "binding-dot")
          .attr("cx", dotX)
          .attr("cy", by)
          .attr("r", 3)
          .attr("fill", "#555");
      }
    });
  }

  function updateFrame(g, d) {
    // Recompute dimensions
    d.width = computeFrameWidth(d.id, d.name);
    d.height = computeFrameHeight(d.id);

    g.select(".frame-bg")
      .attr("width", d.width)
      .attr("height", d.height);

    g.select(".frame-sep")
      .attr("x2", d.width);

    renderBindings(g, d);
  }

  // ─── Procedure SVG ──────────────────────────────────────────────
  function renderProcedure(g, d) {
    const w = PROC_CELL_W * 2;
    const h = PROC_CELL_H;
    const color = d.color || "#b7dae0";
    const stroke = darken(color);

    // Background rect (cons-pair style)
    g.append("rect")
      .attr("class", "proc-bg")
      .attr("width", w).attr("height", h)
      .attr("rx", 4).attr("ry", 4)
      .attr("fill", color)
      .attr("stroke", stroke)
      .attr("stroke-width", 1);

    // Vertical divider
    g.append("line")
      .attr("class", "proc-divider")
      .attr("x1", PROC_CELL_W).attr("y1", 0)
      .attr("x2", PROC_CELL_W).attr("y2", h)
      .attr("stroke", stroke)
      .attr("stroke-width", 1);

    // Left dot (body/params)
    g.append("circle")
      .attr("class", "dot-left")
      .attr("cx", PROC_CELL_W / 2)
      .attr("cy", h / 2)
      .attr("r", 3)
      .attr("fill", "#555");

    // Right dot (env pointer)
    g.append("circle")
      .attr("class", "dot-right")
      .attr("cx", PROC_CELL_W * 1.5)
      .attr("cy", h / 2)
      .attr("r", 3)
      .attr("fill", "#555");

    // Lambda label below
    const labelText = d.lambdaText || "";
    g.append("text")
      .attr("class", "lambda-label")
      .attr("x", PROC_CELL_W)
      .attr("y", h + 14)
      .attr("text-anchor", "middle")
      .attr("font-size", "10px")
      .attr("font-family", "monospace")
      .attr("fill", "#555")
      .text(labelText);

    // Set node dimensions for collision/layout
    const textW = labelText.length * 6 + 8;
    d.width = Math.max(w, textW);
    d.height = h + PROC_LABEL_H;
  }

  // ─── Pair (cons cell) SVG — box-and-pointer diagram ─────────────
  function renderPairCell(g, d) {
    const w = PAIR_CELL_W * 2;
    const h = PAIR_CELL_H;

    // Background rect (cons-cell: two adjacent boxes)
    g.append("rect")
      .attr("class", "pair-bg")
      .attr("width", w).attr("height", h)
      .attr("rx", 2).attr("ry", 2)
      .attr("fill", "#fff")
      .attr("stroke", "#333")
      .attr("stroke-width", 1.2);

    // Vertical divider between car and cdr halves
    g.append("line")
      .attr("class", "pair-divider")
      .attr("x1", PAIR_CELL_W).attr("y1", 0)
      .attr("x2", PAIR_CELL_W).attr("y2", h)
      .attr("stroke", "#333")
      .attr("stroke-width", 1.2);

    // If car has a null marker ("/"), draw diagonal slash
    if (d.carLabel === "/") {
      g.append("line")
        .attr("class", "pair-car-null")
        .attr("x1", 4).attr("y1", h - 4)
        .attr("x2", PAIR_CELL_W - 4).attr("y2", 4)
        .attr("stroke", "#333")
        .attr("stroke-width", 1.2);
    } else if (d.carLabel && d.carLabel.length > 0 && d.carLabel.length <= 6) {
      // Short inline atom label
      g.append("text")
        .attr("class", "pair-car-label")
        .attr("x", PAIR_CELL_W / 2)
        .attr("y", h / 2 + 4)
        .attr("text-anchor", "middle")
        .attr("font-size", "10px")
        .attr("font-family", "monospace")
        .attr("fill", "#333")
        .text(d.carLabel);
    } else {
      // Dot in car half (pointer origin)
      g.append("circle")
        .attr("class", "pair-car-dot")
        .attr("cx", PAIR_CELL_W / 2)
        .attr("cy", h / 2)
        .attr("r", 3)
        .attr("fill", "#444");
    }

    // If cdr has a null marker ("/"), draw diagonal slash
    if (d.cdrLabel === "/") {
      g.append("line")
        .attr("class", "pair-cdr-null")
        .attr("x1", PAIR_CELL_W + 4).attr("y1", h - 4)
        .attr("x2", PAIR_CELL_W * 2 - 4).attr("y2", 4)
        .attr("stroke", "#333")
        .attr("stroke-width", 1.2);
    } else if (d.cdrLabel && d.cdrLabel.length > 0 && d.cdrLabel.length <= 6) {
      // Short inline atom label
      g.append("text")
        .attr("class", "pair-cdr-label")
        .attr("x", PAIR_CELL_W * 1.5)
        .attr("y", h / 2 + 4)
        .attr("text-anchor", "middle")
        .attr("font-size", "10px")
        .attr("font-family", "monospace")
        .attr("fill", "#333")
        .text(d.cdrLabel);
    } else {
      // Dot in cdr half (pointer origin)
      g.append("circle")
        .attr("class", "pair-cdr-dot")
        .attr("cx", PAIR_CELL_W * 1.5)
        .attr("cy", h / 2)
        .attr("r", 3)
        .attr("fill", "#444");
    }

    d.width = w;
    d.height = h;
  }

  // ─── Pair atom (leaf value) SVG ─────────────────────────────────
  function renderPairAtom(g, d) {
    const label = d.label || "";
    const textW = label.length * 7 + PAIR_ATOM_PAD * 2;
    const h = 20;

    g.append("text")
      .attr("class", "pair-atom-label")
      .attr("x", textW / 2)
      .attr("y", h / 2 + 4)
      .attr("text-anchor", "middle")
      .attr("font-size", "10px")
      .attr("font-family", "monospace")
      .attr("fill", "#333")
      .text(label);

    d.width = Math.max(textW, 20);
    d.height = h;
  }

  // ─── Null terminator SVG (diagonal slash) ───────────────────────
  function renderPairNull(g, d) {
    const s = 14;
    // Draw a diagonal line (classic null representation)
    g.append("line")
      .attr("class", "pair-null-slash")
      .attr("x1", 0).attr("y1", s)
      .attr("x2", s).attr("y2", 0)
      .attr("stroke", "#333")
      .attr("stroke-width", 1.5);

    d.width = s;
    d.height = s;
  }

  // ─── Drag behavior ─────────────────────────────────────────────
  function dragStarted(event, d) {
    if (!event.active) simulation.alphaTarget(0.3).restart();
    d.fx = d.x;
    d.fy = d.y;
  }

  function dragged(event, d) {
    d.fx = event.x;
    d.fy = event.y;
  }

  function dragEnded(event, d) {
    if (!event.active) simulation.alphaTarget(0);
    d.fx = null;
    d.fy = null;
  }

  // ─── Public API (called from Scheme via FFI) ────────────────────

  function addFrame(id, name, parentId, color) {
    if (nodeById(id)) return; // already exists

    const c = color || nextColor();
    const node = {
      id,
      type: "frame",
      name: name || "frame",
      parentId: parentId || null,
      color: c,
      width: FRAME_MIN_W,
      height: 60,
    };

    // Position near parent if one exists
    const parent = parentId ? nodeById(parentId) : null;
    if (parent) {
      node.x = (parent.x || width / 2) + (Math.random() - 0.5) * 60;
      node.y = (parent.y || height * 0.15) + 180;
    } else {
      // Global frame: pin at center top so it anchors the layout
      node.x = width / 2;
      node.y = 80;
      node.fx = width / 2;
      node.fy = 80;
    }

    bindings[id] = [];
    nodes.push(node);

    // Add env edge to parent
    if (parentId && nodeById(parentId)) {
      edges.push({
        id: edgeId(id, parentId, "env"),
        source: id,
        target: parentId,
        edgeType: "env",
      });
    }

    scheduleRender();
    hideEmptyState();
    return id;
  }

  function addProcedure(id, lambdaText, frameId, color) {
    if (nodeById(id)) return;

    const c = color || nextColor();
    const frame = nodeById(frameId);
    const node = {
      id,
      type: "procedure",
      lambdaText: lambdaText || "",
      frameId: frameId,
      color: c,
      width: PROC_CELL_W * 2,
      height: PROC_CELL_H + PROC_LABEL_H,
    };

    // Position near enclosing frame
    if (frame) {
      node.x = (frame.x || width / 2) + 120 + (Math.random() - 0.5) * 40;
      node.y = (frame.y || height * 0.3) + (Math.random() - 0.5) * 40;
    } else {
      node.x = width / 2 + 150;
      node.y = height * 0.3;
    }

    nodes.push(node);

    // Add proc→env edge (right dot → enclosing frame)
    if (frameId && nodeById(frameId)) {
      edges.push({
        id: edgeId(id, frameId, "proc-env"),
        source: id,
        target: frameId,
        edgeType: "proc-env",
      });
    }

    scheduleRender();
    return id;
  }

  function addBinding(frameId, varName, value, valueType, procId) {
    // For procedure bindings the Scheme side passes the proc-id as both
    // the value (3rd arg) and procId (5th arg).  If the 5th arg is lost
    // at the Hoot FFI boundary, fall back to value.
    if (valueType === "procedure" && !procId && value) {
      procId = value;
    }

    if (!bindings[frameId]) bindings[frameId] = [];

    // Check if binding already exists
    const existing = bindings[frameId].find(b => b.varName === varName);
    if (existing) {
      existing.value = value;
      existing.valueType = valueType;
      existing.procId = procId || null;
    } else {
      bindings[frameId].push({
        varName,
        value: value || "",
        valueType: valueType || "atom",
        procId: procId || null,
      });
    }

    // Recompute frame dimensions
    const frame = nodeById(frameId);
    if (frame) {
      frame.width = computeFrameWidth(frameId, frame.name);
      frame.height = computeFrameHeight(frameId);
    }

    // Add binding→proc edge if this is a procedure binding
    if (valueType === "procedure" && procId) {
      const eid = edgeId(frameId, procId, "binding");
      if (!edges.find(e => e.id === eid)) {
        edges.push({
          id: eid,
          source: frameId,
          target: procId,
          edgeType: "binding",
        });
      }
    }

    // Add binding→pair edge if this is a pair binding
    // procId field is reused to carry the root pair-node id
    if (valueType === "pair" && procId) {
      const eid = edgeId(frameId, procId, "binding");
      if (!edges.find(e => e.id === eid)) {
        edges.push({
          id: eid,
          source: frameId,
          target: procId,
          edgeType: "binding",
        });
      }
    }

    scheduleRender();
  }

  function updateBinding(frameId, varName, newValue, valueType) {
    const fb = bindings[frameId];
    if (!fb) return;
    const binding = fb.find(b => b.varName === varName);
    if (binding) {
      // Remove old binding→proc/pair edge if target is changing
      if (binding.procId) {
        const oldEid = edgeId(frameId, binding.procId, "binding");
        edges = edges.filter(e => {
          const eid = typeof e.id === "string" ? e.id : "";
          return eid !== oldEid;
        });
      }

      binding.value = newValue;
      binding.valueType = valueType;

      // For procedure bindings, newValue IS the proc-id
      if (valueType === "procedure" && newValue) {
        binding.procId = newValue;
        const eid = edgeId(frameId, newValue, "binding");
        if (!edges.find(e => e.id === eid)) {
          edges.push({
            id: eid,
            source: frameId,
            target: newValue,
            edgeType: "binding",
          });
        }
      } else if (valueType !== "pair") {
        // Atom binding — clear procId
        binding.procId = null;
      }
    }
    scheduleRender();
  }

  // ─── Pair (cons cell) public API ─────────────────────────────────

  /** addPair: create a cons-cell node with optional inline labels */
  function addPair(id, carLabel, cdrLabel) {
    if (nodeById(id)) return;

    const node = {
      id,
      type: "pair",
      carLabel: carLabel || "",
      cdrLabel: cdrLabel || "",
      width: PAIR_CELL_W * 2,
      height: PAIR_CELL_H,
    };

    // Find a neighboring pair or frame to position near
    // For now, place to the right of the last-added pair or frame
    const lastPair = nodes.filter(n => n.type === "pair").pop();
    const lastFrame = nodes.filter(n => n.type === "frame").pop();
    const anchor = lastPair || lastFrame;
    if (anchor) {
      node.x = (anchor.x || width / 2) + 80 + (Math.random() - 0.5) * 30;
      node.y = (anchor.y || height / 2) + (Math.random() - 0.5) * 30;
    } else {
      node.x = width / 2 + 100;
      node.y = height / 2;
    }

    nodes.push(node);
    // Don't render yet — wait for pair edges to be added
    return id;
  }

  /** addPairEdge: connect a cons cell to its car or cdr child */
  function addPairEdge(fromId, toId, type) {
    // type is "car" or "cdr"
    const eid = edgeId(fromId, toId, type);
    if (edges.find(e => e.id === eid)) return;

    edges.push({
      id: eid,
      source: fromId,
      target: toId,
      edgeType: type,  // "car" or "cdr"
    });

    // Position child near parent for good list/tree initial layout
    const parent = nodeById(fromId);
    const child = nodeById(toId);
    if (parent && child) {
      const px = parent.x || width / 2;
      const py = parent.y || height / 2;
      if (type === "cdr") {
        // cdr goes to the right (list layout)
        child.x = px + 80;
        child.y = py;
      } else {
        // car goes below (tree layout)
        child.x = px;
        child.y = py + 60;
      }
    }

    scheduleRender();
  }

  /** addPairAtom: create a leaf atom node for pair display */
  function addPairAtom(id, label) {
    if (nodeById(id)) return;

    const textW = (label || "").length * 7 + PAIR_ATOM_PAD * 2;
    const node = {
      id,
      type: "pair-atom",
      label: label || "",
      width: Math.max(textW, 20),
      height: 20,
    };

    node.x = width / 2 + (Math.random() - 0.5) * 100;
    node.y = height / 2 + (Math.random() - 0.5) * 100;

    nodes.push(node);
    return id;
  }

  /** addPairNull: create a null terminator node */
  function addPairNull(id) {
    if (nodeById(id)) return;

    const node = {
      id,
      type: "pair-null",
      width: 14,
      height: 14,
    };

    node.x = width / 2 + (Math.random() - 0.5) * 100;
    node.y = height / 2 + (Math.random() - 0.5) * 100;

    nodes.push(node);
    return id;
  }

  function removeNode(id) {
    // Remove from nodes
    nodes = nodes.filter(n => n.id !== id);

    // Remove associated edges
    edges = edges.filter(e => {
      const sid = typeof e.source === "object" ? e.source.id : e.source;
      const tid = typeof e.target === "object" ? e.target.id : e.target;
      return sid !== id && tid !== id;
    });

    // Remove bindings
    delete bindings[id];

    scheduleRender();
  }

  function removeEdge(fromId, toId) {
    edges = edges.filter(e => {
      const sid = typeof e.source === "object" ? e.source.id : e.source;
      const tid = typeof e.target === "object" ? e.target.id : e.target;
      return !(sid === fromId && tid === toId);
    });
    scheduleRender();
  }

  function fitToView() {
    if (nodes.length === 0) return;

    // Compute bounding box
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const n of nodes) {
      const hw = (n.width || 60) / 2;
      const hh = (n.height || 60) / 2;
      minX = Math.min(minX, (n.x || 0) - hw);
      minY = Math.min(minY, (n.y || 0) - hh);
      maxX = Math.max(maxX, (n.x || 0) + hw);
      maxY = Math.max(maxY, (n.y || 0) + hh);
    }

    const bw = maxX - minX;
    const bh = maxY - minY;
    const padX = 40, padY = 40;
    const scaleX = (width - padX * 2) / bw;
    const scaleY = (height - padY * 2) / bh;
    const scale = Math.min(scaleX, scaleY, 2.0);
    const cx = (minX + maxX) / 2;
    const cy = (minY + maxY) / 2;

    svg.transition().duration(500).call(
      zoomBehavior.transform,
      d3.zoomIdentity
        .translate(width / 2, height / 2)
        .scale(scale)
        .translate(-cx, -cy)
    );
  }

  function resetView() {
    svg.transition().duration(300).call(
      zoomBehavior.transform,
      d3.zoomIdentity
    );
  }

  function getZoom() {
    return d3.zoomTransform(svg.node()).k;
  }

  function zoomBy(factor) {
    svg.transition().duration(200).call(
      zoomBehavior.scaleBy, factor
    );
  }

  function clear() {
    nodes = [];
    edges = [];
    bindings = {};
    colorIndex = 0;
    if (autoFitTimer !== null) { clearTimeout(autoFitTimer); autoFitTimer = null; }
    if (renderTimer !== null) { clearTimeout(renderTimer); renderTimer = null; }
    edgeGroup.selectAll("*").remove();
    nodeGroup.selectAll("*").remove();
    simulation.nodes([]);
    simulation.force("link").links([]);
    simulation.stop();
  }

  function hideEmptyState() {
    const el = document.getElementById("empty-state");
    if (el) el.classList.add("hidden");
  }

  // ─── Export ─────────────────────────────────────────────────────
  return {
    init,
    addFrame,
    addProcedure,
    addBinding,
    updateBinding,
    addPair,
    addPairEdge,
    addPairAtom,
    addPairNull,
    removeNode,
    removeEdge,
    fitToView,
    resetView,
    getZoom,
    zoomBy,
    clear,
  };
})();
