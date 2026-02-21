// boot.js — JavaScript bootstrap for EnvDraw
// Provides FFI imports for the Hoot-compiled Wasm module
// and initializes the application.

// ─── Canvas / Rendering FFI ────────────────────────────────────────

const canvasImports = {
  getCanvas() {
    return document.getElementById("diagram-canvas");
  },
  getContext(canvas, type) {
    return canvas.getContext(type);
  },
};

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

// ─── DOM FFI ───────────────────────────────────────────────────────

const documentImports = {
  getElementById(id)        { return document.getElementById(id); },
  createElement(tag)        { return document.createElement(tag); },
  createTextNode(text)      { return document.createTextNode(text); },
};

const elementImports = {
  setInnerText(el, text)    { el.innerText = text; },
  setInnerHTML(el, html)    { el.innerHTML = html; },
  getInnerText(el)          { return el.innerText; },
  getValue(el)              { return el.value; },
  setValue(el, v)            { el.value = v; },
  appendChild(el, child)    { return el.appendChild(child); },
  removeChild(el, child)    { el.removeChild(child); },
  setAttribute(el, k, v)    { el.setAttribute(k, v); },
  getAttribute(el, k)       { return el.getAttribute(k); },
  addClass(el, cls)         { el.classList.add(cls); },
  removeClass(el, cls)      { el.classList.remove(cls); },
  scrollToBottom(el)        { el.scrollTop = el.scrollHeight; },
  getBoundingClientRect(el) { return el.getBoundingClientRect(); },
  getWidth(el)              { return el.getBoundingClientRect().width; },
  getHeight(el)             { return el.getBoundingClientRect().height; },
  addEventListener(el, evt, fn) { el.addEventListener(evt, fn); },
  removeEventListener(el, evt, fn) { el.removeEventListener(evt, fn); },
  focus(el)                 { el.focus(); },
};

// ─── Event FFI ─────────────────────────────────────────────────────

const eventImports = {
  preventDefault(e)   { e.preventDefault(); },
  getKey(e)           { return e.key; },
  getKeyCode(e)       { return e.keyCode; },
  getClientX(e)       { return e.clientX; },
  getClientY(e)       { return e.clientY; },
  getOffsetX(e)       { return e.offsetX; },
  getOffsetY(e)       { return e.offsetY; },
  getButton(e)        { return e.button; },
  getShiftKey(e)      { return e.shiftKey; },
  getDeltaY(e)        { return e.deltaY; },
  getTarget(e)        { return e.target; },
  getChecked(e)       { return e.target.checked; },
};

// ─── Timer / RAF FFI ───────────────────────────────────────────────

const timerImports = {
  requestAnimationFrame(fn) { return requestAnimationFrame(fn); },
  setTimeout(fn, ms)        { return setTimeout(fn, ms); },
  consoleLog(msg)           { console.log(msg); },
  consoleError(msg)         { console.error(msg); },
  now()                     { return performance.now(); },
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
    // TODO: trigger re-render from Scheme side
  }

  window.addEventListener("resize", resize);
  resize();
  return canvas;
}

// ─── Boot ──────────────────────────────────────────────────────────

async function boot() {
  setupCanvasResize();

  // For now, just log that we're ready.
  // Once the Hoot Wasm module is built, we'll load it here:
  //
  //   import { Scheme } from "./reflect.js";
  //   const mod = await Scheme.load_main("envdraw.wasm", {
  //     canvas: canvasImports,
  //     ctx: ctxImports,
  //     document: documentImports,
  //     element: elementImports,
  //     event: eventImports,
  //     timer: timerImports,
  //   });
  //
  console.log("EnvDraw boot: DOM ready, canvas sized, awaiting Wasm module.");
}

boot();
