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
  const ANIM_DURATION = 400;

  // Color palette for frames
  const COLORS = [
    "#d4edda", "#fff3cd", "#cce5ff",
    "#fefcbf", "#f8d7da", "#e8daef"
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

    // Zoom layer
    zoomLayer = svg.append("g").attr("class", "zoom-layer");
    edgeGroup = zoomLayer.append("g").attr("class", "edges");
    nodeGroup = zoomLayer.append("g").attr("class", "nodes");

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
      .force("collide", d3.forceCollide().radius(d =>
        d.type === "frame"
          ? Math.max(d.width, d.height) * 0.6 + 20
          : Math.max(d.width || 60, d.height || 48) * 0.5 + 10
      ).strength(0.8).iterations(2))
      .force("link", d3.forceLink(edges)
        .id(d => d.id)
        .distance(d => {
          if (d.edgeType === "env") return 160;
          if (d.edgeType === "proc-env") return 120;
          if (d.edgeType === "binding") return 130;
          return 120;
        })
        .strength(d => {
          if (d.edgeType === "env") return 0.2;
          if (d.edgeType === "binding") return 0.15;
          if (d.edgeType === "proc-env") return 0.15;
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
        return height / 2;
      }).strength(d => {
        // Very strong Y keeps hierarchy stable
        if (d.type === "frame") return 1.0;
        if (d.type === "procedure") return 0.7;
        return 0.3;
      }))
      .force("x", d3.forceX().x(d => {
        // Spread procedures to the right of their frame
        if (d.type === "procedure" && d.frameId) {
          const fn = nodeById(d.frameId);
          if (fn) return (fn.x || width / 2) + 180;
        }
        return width / 2;
      }).strength(d => d.type === "procedure" ? 0.12 : 0.08))
      .velocityDecay(0.7)
      .alphaDecay(0.05)
      .on("tick", ticked);

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

    // Procedure dots are in the cons-cell rect, which sits at the top
    // of the node bounding box.  The node center (d.y) is the middle of
    // the full height (cell + label), so the dot Y in world coords is
    // offset upward by (height - PROC_CELL_H) / 2.
    function procDotY(node) {
      return node.y - ((node.height || (PROC_CELL_H + PROC_LABEL_H)) - PROC_CELL_H) / 2;
    }

    if (d.edgeType === "binding") {
      // From binding dot in source frame → left-dot of target procedure
      const bindIdx = frameBindings(s.id).findIndex(b => b.procId === t.id);
      const bindY = FRAME_HEADER_H + (bindIdx >= 0 ? bindIdx : 0) * BINDING_H + BINDING_H / 2;
      // Source: right side of frame at binding row height
      sx = s.x + sw / 2;
      sy = s.y - sh / 2 + bindY;
      // Target: left-dot center of procedure (cons-cell left half-center)
      tx = t.x - tw / 2 + PROC_CELL_W / 2;
      ty = procDotY(t);
    } else if (d.edgeType === "proc-env") {
      // Source is procedure, target is frame
      // From right-dot of procedure → nearest edge of target frame
      sx = s.x - (s.width || PROC_CELL_W * 2) / 2 + PROC_CELL_W * 1.5;
      sy = procDotY(s);
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
      tx = t.x;
      ty = t.y;
    }

    // Shorten the line to account for arrowhead
    const dx = tx - sx, dy = ty - sy;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len > 12) {
      tx -= (dx / len) * 8;
      ty -= (dy / len) * 8;
    }

    // Use quadratic Bézier for a gentle curve
    const mx = (sx + tx) / 2;
    const my = (sy + ty) / 2;
    // Offset control point perpendicular to the line
    const ndx = -(ty - sy);
    const ndy = tx - sx;
    const nlen = Math.sqrt(ndx * ndx + ndy * ndy) || 1;
    // Curvature factor varies by edge type
    let curveFactor = 0;
    if (d.edgeType === "binding") curveFactor = 0.15;
    else if (d.edgeType === "proc-env") curveFactor = 0.12;
    else if (d.edgeType === "env") curveFactor = 0.1;
    const cx = mx + (ndx / nlen) * len * curveFactor;
    const cy = my + (ndy / nlen) * len * curveFactor;

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

  // ─── SVG rendering (D3 enter/update/exit) ──────────────────────
  function render() {
    renderEdges();
    renderNodes();

    // Debounce simulation restart — a single eval step triggers
    // multiple mutations (frame + bindings + procedure + edges) in
    // rapid succession.  Restarting on every call pumps too much
    // energy into the system.  Instead, batch them.
    simulation.nodes(nodes);
    simulation.force("link").links(edges);
    if (renderTimer !== null) clearTimeout(renderTimer);
    renderTimer = setTimeout(() => {
      renderTimer = null;
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
        return "#666";
      })
      .attr("stroke-width", d => d.edgeType === "env" ? 1.0 : 1.2)
      .attr("stroke-dasharray", d => d.edgeType === "env" ? "4,3" : null)
      .attr("marker-end", d =>
        d.edgeType === "env" ? "url(#arrowhead-env)" : "url(#arrowhead)")
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
    const color = d.color || "#d4edda";
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
      .attr("x", 8).attr("y", 16)
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
      } else if (binding.valueType === "procedure") {
        // Small dot (pointer origin for binding→proc edge)
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
    const color = d.color || "#cce5ff";
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

    render();
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

    render();
    return id;
  }

  function addBinding(frameId, varName, value, valueType, procId) {
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

    render();
  }

  function updateBinding(frameId, varName, newValue, valueType) {
    const fb = bindings[frameId];
    if (!fb) return;
    const binding = fb.find(b => b.varName === varName);
    if (binding) {
      binding.value = newValue;
      binding.valueType = valueType;
    }
    render();
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

    render();
  }

  function removeEdge(fromId, toId) {
    edges = edges.filter(e => {
      const sid = typeof e.source === "object" ? e.source.id : e.source;
      const tid = typeof e.target === "object" ? e.target.id : e.target;
      return !(sid === fromId && tid === toId);
    });
    render();
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
    removeNode,
    removeEdge,
    fitToView,
    resetView,
    getZoom,
    zoomBy,
    clear,
  };
})();
