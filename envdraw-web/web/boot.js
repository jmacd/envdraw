// boot.js — JavaScript bootstrap for EnvDraw (Phase 4)
// Loads the Hoot-compiled Wasm module and wires up all UI interactions.
//
// Provides:
//   1. FFI imports (canvas with pan/zoom transforms, DOM, app callbacks)
//   2. Event wiring (REPL, toolbar, resize, keyboard shortcuts)
//   3. Canvas pan/zoom with mouse drag + scroll wheel
//   4. Resizable trace panel via drag handle
//   5. Collapsible trace sidebar

"use strict";

// ─── State ─────────────────────────────────────────────────────────

const callbacks = {
  eval: null,
  render: null,
  step: null,
  continue_: null,
  toggleStep: null,
  resize: null,
  mouseDown: null,
  mouseMove: null,
  mouseUp: null,
};

const view = {
  zoom: 1.0,
  panX: 0,
  panY: 0,
  isPanning: false,
  isDragging: false,
  mouseStarted: false,
  lastMouse: { x: 0, y: 0 },
  startMouse: { x: 0, y: 0 },
  diagramExists: false,
};

// ─── Canvas / Context FFI ──────────────────────────────────────────

const ctxImports = {
  setFillStyle(ctx, style)    { ctx.fillStyle = style; },
  setStrokeStyle(ctx, style)  { ctx.strokeStyle = style; },
  setLineWidth(ctx, w)        { ctx.lineWidth = w; },
  fillRect(ctx, x, y, w, h)  { ctx.fillRect(x, y, w, h); },
  strokeRect(ctx, x, y, w, h){ ctx.strokeRect(x, y, w, h); },
  clearRect(ctx, x, y, w, h) { ctx.clearRect(x, y, w, h); },
  beginPath(ctx)              { ctx.beginPath(); },
  closePath(ctx)              { ctx.closePath(); },
  moveTo(ctx, x, y)          { ctx.moveTo(x, y); },
  lineTo(ctx, x, y)          { ctx.lineTo(x, y); },
  arc(ctx, x, y, r, s, e)    { ctx.arc(x, y, r, s, e); },
  ellipse(ctx, x, y, rx, ry, rot, s, e) {
    ctx.ellipse(x, y, rx, ry, rot, s, e);
  },
  stroke(ctx)                 { ctx.stroke(); },
  fill(ctx)                   { ctx.fill(); },
  fillText(ctx, text, x, y)  { ctx.fillText(text, x, y); },
  setFont(ctx, font)          { ctx.font = font; },
  setTextAlign(ctx, align)    { ctx.textAlign = align; },
  setTextBaseline(ctx, bl)    { ctx.textBaseline = bl; },
  measureTextWidth(ctx, text) { return ctx.measureText(text).width; },
  save(ctx)                   { ctx.save(); },
  restore(ctx)                { ctx.restore(); },
  translate(ctx, x, y)        { ctx.translate(x, y); },
  scale(ctx, sx, sy)          { ctx.scale(sx, sy); },
  setGlobalAlpha(ctx, a)      { ctx.globalAlpha = a; },
  setLineDash(ctx, seg1, seg2){ ctx.setLineDash([seg1, seg2]); },
  clearLineDash(ctx)          { ctx.setLineDash([]); },
};

// ─── App FFI ───────────────────────────────────────────────────────

const appImports = {
  registerEvalHandler(fn)       { callbacks.eval = fn; },
  registerRenderHandler(fn)     { callbacks.render = fn; },
  registerStepHandler(fn)       { callbacks.step = fn; },
  registerContinueHandler(fn)   { callbacks.continue_ = fn; },
  registerToggleStepHandler(fn) { callbacks.toggleStep = fn; },
  registerResizeHandler(fn)     { callbacks.resize = fn; },
  registerMouseDownHandler(fn)  { callbacks.mouseDown = fn; },
  registerMouseMoveHandler(fn)  { callbacks.mouseMove = fn; },
  registerMouseUpHandler(fn)    { callbacks.mouseUp = fn; },

  traceAppend(text) {
    const traceOutput = document.getElementById("trace-output");
    const line = document.createElement("div");
    line.className = "trace-line";

    if (text.startsWith("EnvDraw>")) line.classList.add("input-line");
    else if (text.includes("EVAL in"))   line.classList.add("eval-line");
    else if (text.includes("RETURNING")) line.classList.add("return-line");
    else if (text.includes("Error") || text.includes("***")) line.classList.add("error-line");
    else line.classList.add("info-line");

    line.textContent = text;
    traceOutput.appendChild(line);
    traceOutput.scrollTop = traceOutput.scrollHeight;

    // Show trace panel if it's collapsed and there's an error
    if (text.includes("Error") || text.includes("***")) {
      showTracePanel();
    }
  },

  setResultText(text) {
    const traceOutput = document.getElementById("trace-output");
    const line = document.createElement("div");
    line.className = "trace-line return-line";
    line.textContent = "⇒ " + text;
    traceOutput.appendChild(line);
    traceOutput.scrollTop = traceOutput.scrollHeight;

    // First result means diagram exists — hide empty state
    hideEmptyState();
  },

  getCanvasContext() {
    const canvas = document.getElementById("diagram-canvas");
    if (!canvas) return null;
    const ctx = canvas.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    // Reset transform and clear the entire physical canvas
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    // Set up rendering transform: DPR, then pan, then zoom
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.translate(view.panX, view.panY);
    ctx.scale(view.zoom, view.zoom);
    return ctx;
  },

  getCanvasWidth() {
    const canvas = document.getElementById("diagram-canvas");
    const dpr = window.devicePixelRatio || 1;
    return canvas ? canvas.width / dpr / view.zoom : 800;
  },

  getCanvasHeight() {
    const canvas = document.getElementById("diagram-canvas");
    const dpr = window.devicePixelRatio || 1;
    return canvas ? canvas.height / dpr / view.zoom : 600;
  },

  consoleLog(msg)   { console.log("[EnvDraw]", msg); },
  consoleError(msg) { console.error("[EnvDraw]", msg); },
};

// ─── UI Helpers ────────────────────────────────────────────────────

function setStatus(text, level) {
  const el = document.getElementById("status-indicator");
  el.textContent = text;
  el.className = "status-" + (level || "ready");
}

function hideEmptyState() {
  const el = document.getElementById("empty-state");
  if (el && !view.diagramExists) {
    el.classList.add("hidden");
    view.diagramExists = true;
  }
}

function showTracePanel() {
  const panel = document.getElementById("trace-panel");
  const handle = document.getElementById("resize-handle");
  panel.classList.remove("collapsed");
  handle.classList.remove("hidden");
}

function updateZoomLabel() {
  const label = document.getElementById("btn-zoom-reset");
  label.textContent = Math.round(view.zoom * 100) + "%";
}

function requestRender() {
  if (callbacks.render) {
    try { callbacks.render(); } catch (e) { console.error("render:", e); }
  }
}

// ─── Canvas Resize ─────────────────────────────────────────────────

function setupCanvasResize() {
  const canvas = document.getElementById("diagram-canvas");
  const container = document.getElementById("canvas-container");

  function resize() {
    const dpr = window.devicePixelRatio || 1;
    const rect = container.getBoundingClientRect();
    canvas.width  = rect.width  * dpr;
    canvas.height = rect.height * dpr;
    if (callbacks.resize) {
      try { callbacks.resize(); } catch (e) { console.error("resize:", e); }
    }
  }

  const ro = new ResizeObserver(() => resize());
  ro.observe(container);
  resize();
  return canvas;
}

// ─── Pan & Zoom ────────────────────────────────────────────────────

/** Convert a client-space mouse position to scene coordinates */
function clientToScene(clientX, clientY, canvas) {
  const rect = canvas.getBoundingClientRect();
  const cssX = clientX - rect.left;
  const cssY = clientY - rect.top;
  // Remove pan, then remove zoom
  return {
    x: (cssX - view.panX) / view.zoom,
    y: (cssY - view.panY) / view.zoom,
  };
}

function setupPanZoom() {
  const canvas = document.getElementById("diagram-canvas");

  // --- Mouse drag: pan OR node drag ---
  canvas.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();

    const scene = clientToScene(e.clientX, e.clientY, canvas);

    // Ask Scheme if something is under the cursor
    let isDraggingNode = false;
    if (callbacks.mouseDown) {
      try {
        callbacks.mouseDown(scene.x, scene.y);
        // If Scheme set a drag node, we're in node-drag mode.
        // We'll detect this by tracking if mouseMove gets consumed.
        isDraggingNode = true;
      } catch (err) {
        console.error("mouseDown:", err);
      }
    }

    // Start tracking — we decide pan vs drag on first move
    view.isDragging = isDraggingNode;
    view.isPanning = false;
    view.mouseStarted = true;
    view.lastMouse = { x: e.clientX, y: e.clientY };
    view.startMouse = { x: e.clientX, y: e.clientY };
  });

  window.addEventListener("mousemove", (e) => {
    if (!view.mouseStarted) return;
    const dx = e.clientX - view.lastMouse.x;
    const dy = e.clientY - view.lastMouse.y;

    if (view.isDragging && callbacks.mouseMove) {
      // Node drag mode — pass scene coordinates to Scheme
      const canvas = document.getElementById("diagram-canvas");
      const scene = clientToScene(e.clientX, e.clientY, canvas);
      try {
        callbacks.mouseMove(scene.x, scene.y);
      } catch (err) {
        console.error("mouseMove:", err);
      }
      canvas.classList.add("panning");
    } else {
      // Pan mode — after small threshold to avoid accidental pans on click
      const totalDx = e.clientX - view.startMouse.x;
      const totalDy = e.clientY - view.startMouse.y;
      if (!view.isPanning && (totalDx * totalDx + totalDy * totalDy) > 9) {
        view.isPanning = true;
        view.isDragging = false;
        // Tell Scheme to cancel any drag
        if (callbacks.mouseUp) {
          try { callbacks.mouseUp(0, 0); } catch (_) {}
        }
      }
      if (view.isPanning) {
        view.panX += dx;
        view.panY += dy;
        const canvas = document.getElementById("diagram-canvas");
        canvas.classList.add("panning");
        requestRender();
      }
    }
    view.lastMouse = { x: e.clientX, y: e.clientY };
  });

  window.addEventListener("mouseup", (e) => {
    if (!view.mouseStarted) return;
    view.mouseStarted = false;

    if (view.isDragging && callbacks.mouseUp) {
      const canvas = document.getElementById("diagram-canvas");
      const scene = clientToScene(e.clientX, e.clientY, canvas);
      try { callbacks.mouseUp(scene.x, scene.y); } catch (err) {
        console.error("mouseUp:", err);
      }
    }
    view.isPanning = false;
    view.isDragging = false;
    const canvas = document.getElementById("diagram-canvas");
    canvas.classList.remove("panning");
  });

  // --- Scroll wheel for zoom ---
  canvas.addEventListener("wheel", (e) => {
    e.preventDefault();
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;

    // Zoom factor
    const delta = -e.deltaY * 0.001;
    const factor = Math.exp(delta);
    const newZoom = Math.min(5, Math.max(0.1, view.zoom * factor));
    const ratio = newZoom / view.zoom;

    // Zoom centered on mouse position
    view.panX = mx - ratio * (mx - view.panX);
    view.panY = my - ratio * (my - view.panY);
    view.zoom = newZoom;

    updateZoomLabel();
    requestRender();
  }, { passive: false });

  // --- Zoom buttons ---
  document.getElementById("btn-zoom-in").addEventListener("click", () => {
    zoomBy(1.25);
  });

  document.getElementById("btn-zoom-out").addEventListener("click", () => {
    zoomBy(0.8);
  });

  document.getElementById("btn-zoom-reset").addEventListener("click", () => {
    view.zoom = 1.0;
    view.panX = 0;
    view.panY = 0;
    updateZoomLabel();
    requestRender();
  });

  document.getElementById("btn-fit").addEventListener("click", () => {
    // Reset to origin — a smarter version would compute bounding box
    view.zoom = 1.0;
    view.panX = 20;
    view.panY = 20;
    updateZoomLabel();
    requestRender();
  });
}

function zoomBy(factor) {
  const container = document.getElementById("canvas-container");
  const rect = container.getBoundingClientRect();
  const cx = rect.width / 2;
  const cy = rect.height / 2;

  const newZoom = Math.min(5, Math.max(0.1, view.zoom * factor));
  const ratio = newZoom / view.zoom;
  view.panX = cx - ratio * (cx - view.panX);
  view.panY = cy - ratio * (cy - view.panY);
  view.zoom = newZoom;

  updateZoomLabel();
  requestRender();
}

// ─── Resizable Trace Panel ─────────────────────────────────────────

function setupResizeHandle() {
  const handle = document.getElementById("resize-handle");
  const panel = document.getElementById("trace-panel");
  let isResizing = false;

  handle.addEventListener("mousedown", (e) => {
    isResizing = true;
    e.preventDefault();
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";
  });

  window.addEventListener("mousemove", (e) => {
    if (!isResizing) return;
    const mainArea = document.getElementById("main-area");
    const rect = mainArea.getBoundingClientRect();
    const newWidth = rect.right - e.clientX;
    if (newWidth >= 180 && newWidth <= 600) {
      panel.style.width = newWidth + "px";
    }
  });

  window.addEventListener("mouseup", () => {
    if (!isResizing) return;
    isResizing = false;
    document.body.style.cursor = "";
    document.body.style.userSelect = "";
  });
}

// ─── Wire UI Events ────────────────────────────────────────────────

function wireEvents() {
  const replInput = document.getElementById("repl-input");
  const btnStep = document.getElementById("btn-step");
  const btnContinue = document.getElementById("btn-continue");
  const chkStepping = document.getElementById("chk-stepping");
  const btnGC = document.getElementById("btn-gc");
  const btnClear = document.getElementById("btn-clear");
  const btnToggleTrace = document.getElementById("btn-toggle-trace");
  const btnClearTrace = document.getElementById("btn-clear-trace");
  const historyEl = document.getElementById("history-pos");

  const history = [];
  let historyIndex = -1;

  // ── REPL ──
  replInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      const text = replInput.value.trim();
      if (!text) return;

      history.unshift(text);
      historyIndex = -1;
      historyEl.textContent = "";

      appImports.traceAppend("EnvDraw> " + text);
      replInput.value = "";

      hideEmptyState();
      setStatus("Evaluating…", "busy");

      if (callbacks.eval) {
        try {
          callbacks.eval(text);
          setStatus("Ready", "ready");
        } catch (err) {
          console.error("eval error:", err);
          appImports.traceAppend("*** Error: " + err.message);
          setStatus("Error", "error");
        }
      }
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      if (historyIndex < history.length - 1) {
        historyIndex++;
        replInput.value = history[historyIndex];
        historyEl.textContent = (historyIndex + 1) + "/" + history.length;
      }
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      if (historyIndex > 0) {
        historyIndex--;
        replInput.value = history[historyIndex];
        historyEl.textContent = (historyIndex + 1) + "/" + history.length;
      } else if (historyIndex === 0) {
        historyIndex = -1;
        replInput.value = "";
        historyEl.textContent = "";
      }
    }
  });

  // ── Toolbar ──
  btnStep.addEventListener("click", () => {
    if (callbacks.step) {
      try { callbacks.step(); } catch (e) { console.error("step:", e); }
    }
  });

  btnContinue.addEventListener("click", () => {
    if (callbacks.continue_) {
      try { callbacks.continue_(); } catch (e) { console.error("continue:", e); }
    }
  });

  chkStepping.addEventListener("change", () => {
    if (callbacks.toggleStep) {
      try { callbacks.toggleStep(); } catch (e) { console.error("toggleStep:", e); }
    }
  });

  btnGC.addEventListener("click", () => {
    appImports.traceAppend("GC: not yet implemented");
  });

  btnClear.addEventListener("click", () => {
    document.getElementById("trace-output").innerHTML = "";
    // Reset view
    view.zoom = 1.0;
    view.panX = 0;
    view.panY = 0;
    view.diagramExists = false;
    updateZoomLabel();
    document.getElementById("empty-state").classList.remove("hidden");
    requestRender();
  });

  // ── Trace panel toggle ──
  btnToggleTrace.addEventListener("click", () => {
    const panel = document.getElementById("trace-panel");
    const handle = document.getElementById("resize-handle");
    panel.classList.toggle("collapsed");
    handle.classList.toggle("hidden");
  });

  btnClearTrace.addEventListener("click", () => {
    document.getElementById("trace-output").innerHTML = "";
  });

  // ── Empty state examples — click to insert ──
  document.querySelectorAll(".empty-examples code").forEach((el) => {
    el.addEventListener("click", () => {
      replInput.value = el.textContent;
      replInput.focus();
    });
  });

  // ── Keyboard shortcuts ──
  document.addEventListener("keydown", (e) => {
    // Don't capture when typing in the REPL
    if (document.activeElement === replInput && !e.ctrlKey && !e.metaKey) return;

    if (e.key === "F10" || (e.ctrlKey && e.key === "'")) {
      e.preventDefault();
      btnStep.click();
    } else if (e.key === "F5") {
      e.preventDefault();
      btnContinue.click();
    } else if (e.key === "t" && !e.ctrlKey && !e.metaKey && document.activeElement !== replInput) {
      e.preventDefault();
      btnToggleTrace.click();
    } else if (e.key === "0" && !e.ctrlKey && !e.metaKey && document.activeElement !== replInput) {
      e.preventDefault();
      view.zoom = 1.0; view.panX = 0; view.panY = 0;
      updateZoomLabel(); requestRender();
    } else if (e.key === "=" && !e.ctrlKey && !e.metaKey && document.activeElement !== replInput) {
      e.preventDefault();
      zoomBy(1.25);
    } else if (e.key === "-" && !e.ctrlKey && !e.metaKey && document.activeElement !== replInput) {
      e.preventDefault();
      zoomBy(0.8);
    } else if (e.key === "/" && document.activeElement !== replInput) {
      e.preventDefault();
      replInput.focus();
    }
  });

  replInput.focus();
}

// ─── Boot ──────────────────────────────────────────────────────────

async function boot() {
  setStatus("Loading…", "busy");
  setupCanvasResize();
  setupPanZoom();
  setupResizeHandle();

  try {
    await Scheme.load_main("envdraw.wasm?" + Date.now(), {
      reflect_wasm_dir: ".",
      user_imports: {
        ctx: ctxImports,
        app: appImports,
      },
    });

    console.log("EnvDraw: Wasm module loaded successfully.");
    setStatus("Ready", "ready");
    wireEvents();

  } catch (e) {
    if (e instanceof WebAssembly.CompileError) {
      setStatus("Browser unsupported", "error");
      document.getElementById("empty-state").querySelector(".empty-title").textContent =
        "Browser not supported";
      document.getElementById("empty-state").querySelector(".empty-hint").textContent =
        "EnvDraw requires Wasm GC and tail calls (Firefox 120+ or Chrome 119+)";
    } else {
      setStatus("Load error", "error");
    }
    console.error("EnvDraw boot error:", e);
    wireEvents();

    const traceOutput = document.getElementById("trace-output");
    const line = document.createElement("div");
    line.className = "trace-line error-line";
    line.textContent = "*** Failed to load envdraw.wasm: " + e.message;
    traceOutput.appendChild(line);
  }
}

window.addEventListener("load", boot);
