// boot.js — JavaScript bootstrap for EnvDraw
// Loads the Hoot-compiled Wasm module and wires up all UI interactions.
//
// The Scheme side registers callback functions via the "app" FFI module.
// This file provides:
//   1. All FFI imports (canvas, DOM, app callbacks)
//   2. Event listener wiring (REPL, toolbar, resize)
//   3. Canvas resize management

"use strict";

// ─── Registered Scheme Callbacks ───────────────────────────────────
// These are populated by the Scheme side during boot! via
// register*Handler FFI calls.  Each receives a JS-callable function
// wrapper around a Scheme procedure (via procedure->external).

const callbacks = {
  eval: null,
  render: null,
  step: null,
  continue_: null,
  toggleStep: null,
  resize: null,
};

// ─── Canvas / Context FFI ──────────────────────────────────────────
// Module "ctx" — Canvas2D drawing operations.
// Every function takes the context as its first argument.

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
// Module "app" — bidirectional communication between Scheme and JS.

const appImports = {
  // Scheme registers callbacks for JS to invoke on user events
  registerEvalHandler(fn)       { callbacks.eval = fn; },
  registerRenderHandler(fn)     { callbacks.render = fn; },
  registerStepHandler(fn)       { callbacks.step = fn; },
  registerContinueHandler(fn)   { callbacks.continue_ = fn; },
  registerToggleStepHandler(fn) { callbacks.toggleStep = fn; },
  registerResizeHandler(fn)     { callbacks.resize = fn; },

  // Scheme calls these to update the DOM
  traceAppend(text) {
    const traceOutput = document.getElementById("trace-output");
    const line = document.createElement("div");
    line.className = "trace-line";

    // Classify for color coding
    if (text.includes("EVAL in"))   line.classList.add("eval-line");
    else if (text.includes("RETURNING")) line.classList.add("return-line");
    else if (text.includes("Error") || text.includes("***")) line.classList.add("error-line");
    else line.classList.add("info-line");

    line.textContent = text;
    traceOutput.appendChild(line);
    traceOutput.scrollTop = traceOutput.scrollHeight;
  },

  setResultText(text) {
    const traceOutput = document.getElementById("trace-output");
    const line = document.createElement("div");
    line.className = "trace-line return-line";
    line.textContent = "=> " + text;
    traceOutput.appendChild(line);
    traceOutput.scrollTop = traceOutput.scrollHeight;
  },

  getCanvasContext() {
    const canvas = document.getElementById("diagram-canvas");
    return canvas ? canvas.getContext("2d") : null;
  },

  getCanvasWidth() {
    const canvas = document.getElementById("diagram-canvas");
    return canvas ? canvas.width : 800;
  },

  getCanvasHeight() {
    const canvas = document.getElementById("diagram-canvas");
    return canvas ? canvas.height : 600;
  },

  consoleLog(msg)   { console.log("[EnvDraw]", msg); },
  consoleError(msg) { console.error("[EnvDraw]", msg); },
};

// ─── Canvas resize helper ──────────────────────────────────────────

function setupCanvasResize() {
  const canvas = document.getElementById("diagram-canvas");
  const container = document.getElementById("canvas-container");

  function resize() {
    const dpr = window.devicePixelRatio || 1;
    const rect = container.getBoundingClientRect();
    canvas.width  = rect.width  * dpr;
    canvas.height = rect.height * dpr;
    const ctx = canvas.getContext("2d");
    ctx.scale(dpr, dpr);
    // Tell Scheme side to update its dimensions and re-render
    if (callbacks.resize) {
      try { callbacks.resize(); } catch (e) { console.error("resize callback:", e); }
    }
  }

  window.addEventListener("resize", resize);
  resize();
  return canvas;
}

// ─── Wire UI Events ────────────────────────────────────────────────

function wireEvents() {
  const replInput = document.getElementById("repl-input");
  const btnStep = document.getElementById("btn-step");
  const btnContinue = document.getElementById("btn-continue");
  const chkStepping = document.getElementById("chk-stepping");
  const btnGC = document.getElementById("btn-gc");

  // Command history
  const history = [];
  let historyIndex = -1;

  // REPL input: Enter to evaluate
  replInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      const text = replInput.value.trim();
      if (!text) return;

      // Add to history
      history.unshift(text);
      historyIndex = -1;

      // Show input in trace
      appImports.traceAppend("EnvDraw> " + text);
      replInput.value = "";

      // Call Scheme evaluator
      if (callbacks.eval) {
        try {
          callbacks.eval(text);
        } catch (err) {
          console.error("eval error:", err);
          appImports.traceAppend("*** JS Error: " + err.message);
        }
      }
    } else if (e.key === "ArrowUp") {
      // History navigation
      if (historyIndex < history.length - 1) {
        historyIndex++;
        replInput.value = history[historyIndex];
        e.preventDefault();
      }
    } else if (e.key === "ArrowDown") {
      if (historyIndex > 0) {
        historyIndex--;
        replInput.value = history[historyIndex];
      } else if (historyIndex === 0) {
        historyIndex = -1;
        replInput.value = "";
      }
      e.preventDefault();
    }
  });

  // Toolbar: Step button
  btnStep.addEventListener("click", () => {
    if (callbacks.step) {
      try { callbacks.step(); } catch (e) { console.error("step:", e); }
    }
  });

  // Toolbar: Continue button
  btnContinue.addEventListener("click", () => {
    if (callbacks.continue_) {
      try { callbacks.continue_(); } catch (e) { console.error("continue:", e); }
    }
  });

  // Toolbar: Stepping checkbox
  chkStepping.addEventListener("change", () => {
    if (callbacks.toggleStep) {
      try { callbacks.toggleStep(); } catch (e) { console.error("toggleStep:", e); }
    }
  });

  // Toolbar: GC button (placeholder)
  btnGC.addEventListener("click", () => {
    appImports.traceAppend("GC: not yet implemented");
  });

  // Focus REPL on load
  replInput.focus();
}

// ─── Boot ──────────────────────────────────────────────────────────

async function boot() {
  setupCanvasResize();

  try {
    // Load the Hoot-compiled EnvDraw Wasm module
    // Scheme is the global from reflect.js (loaded before this script)
    // Debug: fetch and inspect the wasm imports before loading
    const wasmBytes = await fetch("envdraw.wasm?" + Date.now()).then(r => r.arrayBuffer());
    console.log("DEBUG: wasm size =", wasmBytes.byteLength, "bytes");
    const wasmMod = await WebAssembly.compile(wasmBytes);
    const imports = WebAssembly.Module.imports(wasmMod);
    const importsByModule = {};
    for (const imp of imports) {
      if (!importsByModule[imp.module]) importsByModule[imp.module] = [];
      importsByModule[imp.module].push(imp.name + " (" + imp.kind + ")");
    }
    for (const [mod, names] of Object.entries(importsByModule)) {
      if (mod === "ctx" || mod === "app") {
        console.log("DEBUG: wasm imports [" + mod + "]:", names);
      }
    }
    // Check what we're providing
    console.log("DEBUG: JS provides [ctx]:", Object.keys(ctxImports));
    console.log("DEBUG: JS provides [app]:", Object.keys(appImports));

    await Scheme.load_main("envdraw.wasm?" + Date.now(), {
      reflect_wasm_dir: ".",
      user_imports: {
        ctx: ctxImports,
        app: appImports,
      },
    });

    console.log("EnvDraw: Wasm module loaded successfully.");

    // Wire up DOM event handlers (after Scheme callbacks are registered)
    wireEvents();

  } catch (e) {
    if (e instanceof WebAssembly.CompileError) {
      document.getElementById("object-label").textContent =
        "Error: Browser does not support Wasm GC / tail calls";
    }
    console.error("EnvDraw boot error:", e);

    // Still wire events for error feedback
    wireEvents();
    const traceOutput = document.getElementById("trace-output");
    const line = document.createElement("div");
    line.className = "trace-line error-line";
    line.textContent = "*** Failed to load envdraw.wasm: " + e.message;
    traceOutput.appendChild(line);
  }
}

window.addEventListener("load", boot);
