// boot.js — JavaScript bootstrap for EnvDraw (Phase 5 — D3.js)
// Loads the Hoot-compiled Wasm module and wires up all UI interactions.
//
// Provides:
//   1. FFI imports (no-op canvas stubs, D3 graph-mutation functions, DOM, app callbacks)
//   2. Event wiring (REPL, toolbar, resize, keyboard shortcuts)
//   3. D3.js handles all pan/zoom/drag via d3-diagram.js
//   4. Resizable trace panel via drag handle
//   5. Collapsible trace sidebar

"use strict";

// ─── State ─────────────────────────────────────────────────────────

/** Convert a Hoot Wasm value to a JS string.
 *  Hoot heap objects (MutableString, Sym, etc.) have a repr() method
 *  that returns Scheme write-style text; their toString() returns opaque
 *  type tags like "#<mutable-string>".  For MutableString we extract the
 *  raw string value (like Scheme display); for other types we use repr(). */
function schemeToString(val) {
  if (val == null) return null;
  if (typeof val === "string" || typeof val === "number" ||
      typeof val === "boolean" || typeof val === "bigint") {
    return String(val);
  }
  // MutableString: extract raw content via reflector.string_value
  if (typeof val === "object" && val.reflector &&
      typeof val.reflector.string_value === "function") {
    try { return val.reflector.string_value(val); } catch (_) {}
  }
  if (typeof val === "object" && typeof val.repr === "function") {
    return val.repr();
  }
  return String(val);
}

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
  clear: null,
};

const view = {
  diagramExists: false,
};

// ─── Stepping State ───────────────────────────────────────────────
// Stepping is implemented via record-and-replay: evaluation runs to
// completion synchronously, but when stepping is enabled, all D3
// mutations and trace output are recorded into step groups (bounded
// by wait-for-confirmation calls in the evaluator).  The Step button
// replays one group at a time; Continue replays all remaining groups.

const stepping = {
  active: false,        // stepping checkbox is checked
  queueing: false,      // currently recording steps during eval
  suspended: false,     // evaluation done, steps pending replay
  queue: [],            // array of fn[] (each fn[] is one step's operations)
  currentOps: [],       // accumulating current step's operations
  boundariesSeen: 0,    // count of step boundaries in current eval
  pendingResult: null,  // {thisLine, fullText, resultText, isError, numLines}
};

/** Push accumulated operations as a completed step group. */
function finalizeCurrentStep() {
  if (stepping.currentOps.length > 0) {
    stepping.queue.push([...stepping.currentOps]);
    stepping.currentOps = [];
  }
}

/** Apply all queued step groups immediately (used on error or no boundaries). */
function flushStepQueue() {
  for (const ops of stepping.queue) for (const op of ops) op();
  stepping.queue = [];
  stepping.currentOps = [];
}

// ─── Canvas / Context FFI (no-op stubs — Wasm still imports these) ─

const _noop = () => {};
const _noopRet0 = () => 0;
const _noopRetNull = () => null;

const ctxImports = {
  setFillStyle: _noop,
  setStrokeStyle: _noop,
  setLineWidth: _noop,
  fillRect: _noop,
  strokeRect: _noop,
  clearRect: _noop,
  beginPath: _noop,
  closePath: _noop,
  moveTo: _noop,
  lineTo: _noop,
  arc: _noop,
  ellipse: _noop,
  stroke: _noop,
  fill: _noop,
  fillText: _noop,
  setFont: _noop,
  setTextAlign: _noop,
  setTextBaseline: _noop,
  measureTextWidth: _noopRet0,
  save: _noop,
  restore: _noop,
  translate: _noop,
  scale: _noop,
  setGlobalAlpha: _noop,
  setLineDash: _noop,
  clearLineDash: _noop,
  roundRect: _noop,
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
  registerGCHandler(fn)          { callbacks.gc = fn; },
  registerClearHandler(fn)       { callbacks.clear = fn; },

  traceAppend(text) {
    text = schemeToString(text) || '';
    if (stepping.queueing) {
      stepping.currentOps.push(() => realTraceAppend(text));
      return;
    }
    realTraceAppend(text);
  },

  setResultText(text) {
    text = schemeToString(text) || '';
    if (stepping.queueing) {
      stepping.currentOps.push(() => realSetResultText(text));
      return;
    }
    realSetResultText(text);
  },

  getCanvasContext: _noopRetNull,
  getCanvasWidth()  { return 800; },
  getCanvasHeight() { return 600; },

  consoleLog(msg)   { console.log("[EnvDraw]", schemeToString(msg)); },
  consoleError(msg) { console.error("[EnvDraw]", schemeToString(msg)); },

  // ── D3 graph-mutation FFI (called from Scheme web-observer) ──
  // When stepping is active during eval, mutations are queued as closures
  // and replayed one step group at a time when the user clicks Step.
  d3AddFrame(id, name, parentId, color) {
    const a = schemeToString(id), b = schemeToString(name),
          c = schemeToString(parentId), d = schemeToString(color);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.addFrame(a, b, c, d)); return; }
    EnvDiagram.addFrame(a, b, c, d);
  },
  d3AddProcedure(id, lambdaText, frameId, color) {
    const a = schemeToString(id), b = schemeToString(lambdaText),
          c = schemeToString(frameId), d = schemeToString(color);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.addProcedure(a, b, c, d)); return; }
    EnvDiagram.addProcedure(a, b, c, d);
  },
  d3AddBinding(frameId, varName, value, valueType, procId) {
    const a = schemeToString(frameId), b = schemeToString(varName),
          c = schemeToString(value), d = schemeToString(valueType),
          e = schemeToString(procId);
    console.log("[d3AddBinding]", {frameId: a, varName: b, value: c, valueType: d, procId: e, rawProcId: procId});
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.addBinding(a, b, c, d, e)); return; }
    EnvDiagram.addBinding(a, b, c, d, e);
  },
  d3UpdateBinding(frameId, varName, newValue, valueType) {
    const a = schemeToString(frameId), b = schemeToString(varName),
          c = schemeToString(newValue), d = schemeToString(valueType);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.updateBinding(a, b, c, d)); return; }
    EnvDiagram.updateBinding(a, b, c, d);
  },
  d3RemoveNode(id) {
    const a = schemeToString(id);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.removeNode(a)); return; }
    EnvDiagram.removeNode(a);
  },
  d3RemoveEdge(fromId, toId) {
    const a = schemeToString(fromId), b = schemeToString(toId);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.removeEdge(a, b)); return; }
    EnvDiagram.removeEdge(a, b);
  },
  d3AddPair(id, carLabel, cdrLabel) {
    const a = schemeToString(id), b = schemeToString(carLabel),
          c = schemeToString(cdrLabel);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.addPair(a, b, c)); return; }
    EnvDiagram.addPair(a, b, c);
  },
  d3AddPairEdge(fromId, toId, edgeType) {
    const a = schemeToString(fromId), b = schemeToString(toId),
          c = schemeToString(edgeType);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.addPairEdge(a, b, c)); return; }
    EnvDiagram.addPairEdge(a, b, c);
  },
  d3AddPairAtom(id, label) {
    const a = schemeToString(id), b = schemeToString(label);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.addPairAtom(a, b)); return; }
    EnvDiagram.addPairAtom(a, b);
  },
  d3AddPairNull(id) {
    const a = schemeToString(id);
    if (stepping.queueing) { stepping.currentOps.push(() => EnvDiagram.addPairNull(a)); return; }
    EnvDiagram.addPairNull(a);
  },
  d3RequestRender() {
    if (stepping.queueing) return;
  },
  /** Called from Scheme when wait-for-confirmation fires (at each apply). */
  notifyStepBoundary() {
    console.log("[step] notifyStepBoundary: queueing=", stepping.queueing,
                "boundariesSeen=", stepping.boundariesSeen,
                "currentOps.length=", stepping.currentOps.length);
    if (stepping.queueing) {
      stepping.boundariesSeen++;
      finalizeCurrentStep();
    }
  },
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

/** Append a line to the trace panel (bypasses step queue). */
function realTraceAppend(text) {
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

  if (text.includes("Error") || text.includes("***")) {
    showTracePanel();
  }
}

/** Show a result line in the trace panel (bypasses step queue). */
function realSetResultText(text) {
  const traceOutput = document.getElementById("trace-output");
  const line = document.createElement("div");
  line.className = "trace-line return-line";
  line.textContent = "⇒ " + text;
  traceOutput.appendChild(line);
  traceOutput.scrollTop = traceOutput.scrollHeight;
  hideEmptyState();
}

function updateZoomLabel() {
  const label = document.getElementById("btn-zoom-reset");
  const z = EnvDiagram.getZoom ? EnvDiagram.getZoom() : 1;
  label.textContent = Math.round(z * 100) + "%";
}

function requestRender() {
  // D3 handles rendering; this is a compatibility no-op
}

// ─── D3 Diagram Initialization ─────────────────────────────────────

function setupDiagram() {
  const svgEl = document.getElementById("diagram-svg");
  if (!svgEl) {
    console.error("SVG element #diagram-svg not found");
    return;
  }
  EnvDiagram.init(svgEl);

  // Wire zoom buttons to D3
  document.getElementById("btn-zoom-in").addEventListener("click", () => {
    EnvDiagram.zoomBy(1.25);
    setTimeout(updateZoomLabel, 250);  // after D3 transition
  });

  document.getElementById("btn-zoom-out").addEventListener("click", () => {
    EnvDiagram.zoomBy(0.8);
    setTimeout(updateZoomLabel, 250);
  });

  document.getElementById("btn-zoom-reset").addEventListener("click", () => {
    EnvDiagram.resetView();
    setTimeout(updateZoomLabel, 350);
  });

  document.getElementById("btn-fit").addEventListener("click", () => {
    EnvDiagram.fitToView();
    setTimeout(updateZoomLabel, 510);  // after fit animation completes
  });
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
  const replLog = document.getElementById("repl-log");
  const lineNumGutter = document.getElementById("input-line-nums");

  const history = [];
  let historyIndex = -1;
  let replLineNumber = 1;

  /** Check whether parentheses/brackets/strings are balanced */
  function isExpressionComplete(text) {
    let depth = 0;
    let inString = false;
    let escape = false;
    let inComment = false;
    for (const ch of text) {
      if (inComment) {
        if (ch === '\n') inComment = false;
        continue;
      }
      if (escape) { escape = false; continue; }
      if (ch === '\\' && inString) { escape = true; continue; }
      if (ch === '"') { inString = !inString; continue; }
      if (inString) continue;
      if (ch === ';') { inComment = true; continue; }
      if (ch === '(') depth++;
      if (ch === ')') depth--;
    }
    // Balanced (or more closes): depth ≤ 0; but also require non-empty
    return depth <= 0;
  }

  /** Auto-resize the textarea to fit its content */
  function autoResizeInput() {
    replInput.style.height = '0';
    replInput.style.height = Math.min(replInput.scrollHeight, 200) + 'px';
  }

  /** Update the line-number gutter beside the textarea */
  function updateLineNumGutter() {
    const lines = replInput.value.split('\n');
    const numLines = lines.length;
    let html = '';
    for (let i = 0; i < numLines; i++) {
      html += '<span>' + (replLineNumber + i) + '</span>';
    }
    lineNumGutter.innerHTML = html;
  }

  /** Append an entry to the REPL history log (supports multi-line) */
  function addToReplLog(startLine, inputText, resultText, isError) {
    const lines = inputText.split('\n');
    const block = document.createElement("div");
    block.className = "repl-log-block";

    lines.forEach((line, i) => {
      const row = document.createElement("div");
      row.className = "repl-log-line";

      const numSpan = document.createElement("span");
      numSpan.className = "line-num";
      numSpan.textContent = startLine + i;
      row.appendChild(numSpan);

      const inputSpan = document.createElement("span");
      inputSpan.className = "line-input";
      inputSpan.textContent = line;
      row.appendChild(inputSpan);

      block.appendChild(row);
    });

    // Result/error on its own line below the input
    if (resultText != null) {
      const resRow = document.createElement("div");
      resRow.className = "repl-log-line";
      const resSpan = document.createElement("span");
      resSpan.className = isError ? "line-error" : "line-result";
      resSpan.textContent = isError ? resultText : "⇒ " + resultText;
      resRow.appendChild(resSpan);
      block.appendChild(resRow);
    }

    replLog.appendChild(block);
    replLog.scrollTop = replLog.scrollHeight;
  }

  // Export for tests
  window._replLineNumber = () => replLineNumber;

  // ── Stepping: replay management ──

  /** Update Step/Continue button highlight state. */
  function updateStepButtons() {
    if (stepping.suspended && stepping.queue.length > 0) {
      btnStep.classList.add("step-highlight");
      btnContinue.classList.add("step-highlight");
    } else {
      btnStep.classList.remove("step-highlight");
      btnContinue.classList.remove("step-highlight");
    }
  }

  /** Update the status bar with remaining step count. */
  function updateStepStatus() {
    const n = stepping.queue.length;
    if (n > 0) {
      setStatus(`Stepping \u2014 ${n} step${n !== 1 ? "s" : ""} remaining`, "stepping");
    }
  }

  /** End the stepping suspension: show result, re-enable REPL. */
  function finishStepping() {
    if (!stepping.suspended) return;
    stepping.suspended = false;
    const p = stepping.pendingResult;
    if (p) {
      addToReplLog(p.thisLine, p.fullText, p.resultText, p.isError);
      replLineNumber += p.numLines;
      updateLineNumGutter();
      stepping.pendingResult = null;
    }
    replInput.disabled = false;
    replInput.focus();
    setStatus("Ready", "ready");
    updateStepButtons();
  }

  /** Advance one step group (called by Step button). */
  function advanceOneStep() {
    if (stepping.queue.length === 0) { finishStepping(); return; }
    const ops = stepping.queue.shift();
    for (const op of ops) op();
    if (stepping.queue.length === 0) {
      finishStepping();
    } else {
      updateStepStatus();
      updateStepButtons();
    }
  }

  /** Apply all remaining step groups (called by Continue button). */
  function advanceAllSteps() {
    while (stepping.queue.length > 0) {
      const ops = stepping.queue.shift();
      for (const op of ops) op();
    }
    finishStepping();
  }

  // Auto-resize on input and update line numbers
  replInput.addEventListener("input", () => {
    autoResizeInput();
    updateLineNumGutter();
  });

  // Keep line-number gutter scroll in sync with textarea
  replInput.addEventListener("scroll", () => {
    lineNumGutter.scrollTop = replInput.scrollTop;
  });

  // ── REPL ──
  function submitInput() {
      const text = replInput.value.trim();
      if (!text) return;
      if (!isExpressionComplete(text)) return;

      const fullText = replInput.value.trimEnd();
      const inputLines = fullText.split('\n');
      const numLines = inputLines.length;
      const thisLine = replLineNumber;

      history.unshift(fullText);
      historyIndex = -1;

      appImports.traceAppend("EnvDraw> " + fullText);
      replInput.value = "";
      autoResizeInput();
      updateLineNumGutter();

      hideEmptyState();
      setStatus("Evaluating…", "busy");

      // Set up step recording if stepping is active
      const wasQueueing = stepping.active;
      console.log("[step] eval start: stepping.active=", stepping.active);
      if (wasQueueing) {
        stepping.queueing = true;
        stepping.queue = [];
        stepping.currentOps = [];
        stepping.boundariesSeen = 0;
      }

      let resultText = null;
      let isError = false;
      if (callbacks.eval) {
        try {
          const res = callbacks.eval(fullText);
          resultText = schemeToString(res);

        } catch (err) {
          console.error("eval error:", err);
          resultText = err.message || "unknown error";
          isError = true;
          // On error during stepping, flush recorded steps then show error
          if (stepping.queueing) {
            stepping.queueing = false;
            finalizeCurrentStep();
            flushStepQueue();
          }
          realTraceAppend("*** Error: " + err.message);
          setStatus("Error", "error");
        }
      }

      stepping.queueing = false;
      finalizeCurrentStep();

      console.log("[step] eval done: wasQueueing=", wasQueueing,
                  "boundariesSeen=", stepping.boundariesSeen,
                  "queue.length=", stepping.queue.length,
                  "isError=", isError);
      if (wasQueueing && stepping.boundariesSeen > 0 && !isError) {
        // Enter stepping suspension — replay on Step/Continue clicks
        stepping.suspended = true;
        stepping.pendingResult = { thisLine, fullText, resultText, isError, numLines };
        updateStepStatus();
        replInput.disabled = true;
        showTracePanel();
        updateStepButtons();
        console.log("[step] entered suspension with", stepping.queue.length, "step groups");
      } else {
        // No stepping, or no boundaries, or error — apply immediately
        console.log("[step] NOT entering suspension");
        if (wasQueueing) flushStepQueue();
        addToReplLog(thisLine, fullText, resultText, isError);
        replLineNumber += numLines;
        updateLineNumGutter();
        if (!isError) setStatus("Ready", "ready");
      }
  }

  replInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      // Shift+Enter: always insert newline (let default happen)
      if (e.shiftKey) return;

      const text = replInput.value.trim();
      if (!text) { e.preventDefault(); return; }

      // If expression is incomplete (unbalanced parens), insert newline
      if (!isExpressionComplete(text)) return;

      e.preventDefault();
      submitInput();
    } else if (e.key === "ArrowUp") {
      // Only navigate history if cursor is at the very start
      if (replInput.selectionStart === 0 && replInput.selectionEnd === 0) {
        e.preventDefault();
        if (historyIndex < history.length - 1) {
          historyIndex++;
          replInput.value = history[historyIndex];
          autoResizeInput();
          updateLineNumGutter();
        }
      }
    } else if (e.key === "ArrowDown") {
      // Only navigate history if cursor is at the very end
      if (replInput.selectionEnd === replInput.value.length) {
        e.preventDefault();
        if (historyIndex > 0) {
          historyIndex--;
          replInput.value = history[historyIndex];
          autoResizeInput();
          updateLineNumGutter();
        } else if (historyIndex === 0) {
          historyIndex = -1;
          replInput.value = "";
          autoResizeInput();
          updateLineNumGutter();
        }
      }
    }
  });

  // ── Toolbar ──
  btnStep.addEventListener("click", () => {
    if (stepping.suspended && stepping.queue.length > 0) {
      advanceOneStep();
    }
  });

  btnContinue.addEventListener("click", () => {
    if (stepping.suspended) {
      advanceAllSteps();
    }
  });

  chkStepping.addEventListener("change", () => {
    stepping.active = chkStepping.checked;
    if (callbacks.toggleStep) {
      try { callbacks.toggleStep(); } catch (e) { console.error("toggleStep:", e); }
    }
    // If turning off stepping while suspended, flush remaining steps
    if (!stepping.active && stepping.suspended) {
      advanceAllSteps();
    }
    updateStepButtons();
  });

  btnGC.addEventListener("click", () => {
    if (callbacks.gc) {
      try { callbacks.gc(); } catch (e) { console.error("gc:", e); }
    }
  });

  btnClear.addEventListener("click", () => {
    // Cancel any pending step replay
    if (stepping.suspended) {
      stepping.queue = [];
      stepping.currentOps = [];
      stepping.suspended = false;
      stepping.pendingResult = null;
      replInput.disabled = false;
      updateStepButtons();
    }
    document.getElementById("trace-output").innerHTML = "";
    // Clear REPL log and reset line counter
    replLog.innerHTML = "";
    replLineNumber = 1;
    updateLineNumGutter();
    // Clear D3 diagram
    EnvDiagram.clear();
    view.diagramExists = false;
    updateZoomLabel();
    document.getElementById("empty-state").classList.remove("hidden");
    // Reset Scheme evaluator state so the global frame is re-emitted
    if (callbacks.clear) {
      try { callbacks.clear(); } catch (e) { console.error("clear:", e); }
    }
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
      submitInput();
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
      EnvDiagram.resetView();
      setTimeout(updateZoomLabel, 350);
    } else if (e.key === "=" && !e.ctrlKey && !e.metaKey && document.activeElement !== replInput) {
      e.preventDefault();
      EnvDiagram.zoomBy(1.25);
      setTimeout(updateZoomLabel, 250);
    } else if (e.key === "-" && !e.ctrlKey && !e.metaKey && document.activeElement !== replInput) {
      e.preventDefault();
      EnvDiagram.zoomBy(0.8);
      setTimeout(updateZoomLabel, 250);
    } else if (e.key === "f" && !e.ctrlKey && !e.metaKey && document.activeElement !== replInput) {
      e.preventDefault();
      EnvDiagram.fitToView();
      setTimeout(updateZoomLabel, 510);
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
  setupDiagram();
  setupResizeHandle();

  try {
    await Scheme.load_main("envdraw.wasm?" + Date.now(), {
      reflect_wasm_dir: "hoot",
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
