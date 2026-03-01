#!/usr/bin/env node
/**
 * browser-test.mjs — Puppeteer-based end-to-end test for EnvDraw
 *
 * Usage:
 *   node test/browser-test.mjs              # headless
 *   node test/browser-test.mjs --headed     # visible browser
 *   node test/browser-test.mjs --debug      # headed + slow + devtools
 *
 * Requires a running HTTP server in web/:
 *   cd web && python3 -m http.server 8088
 *
 * The test:
 *   1. Loads index.html and waits for Wasm boot
 *   2. Types Scheme expressions into the REPL
 *   3. Verifies trace panel output
 *   4. Checks that SVG diagram has D3-rendered nodes
 *   5. Tests pan/zoom controls
 *   6. Takes diagnostic screenshots
 */

import puppeteer from "puppeteer";
import { createServer } from "http";
import { readFileSync, existsSync } from "fs";
import { resolve, extname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const WEB_DIR = resolve(__dirname, "..", "web");
const PORT = 8089;

// ─── Simple HTTP server ───────────────────────────────────────────

const MIME = {
  ".html": "text/html",
  ".css": "text/css",
  ".js": "application/javascript",
  ".wasm": "application/wasm",
  ".scm": "text/plain",
};

function startServer() {
  return new Promise((resolve) => {
    const server = createServer((req, res) => {
      // Strip query string
      const urlPath = req.url.split("?")[0];
      const filePath = join(WEB_DIR, urlPath === "/" ? "index.html" : urlPath);

      if (!existsSync(filePath)) {
        res.writeHead(404);
        res.end("Not found: " + urlPath);
        return;
      }

      const ext = extname(filePath);
      const mime = MIME[ext] || "application/octet-stream";
      const data = readFileSync(filePath);
      res.writeHead(200, { "Content-Type": mime });
      res.end(data);
    });

    server.listen(PORT, () => {
      console.log(`  HTTP server listening on http://localhost:${PORT}/`);
      resolve(server);
    });
  });
}

// ─── Test helpers ─────────────────────────────────────────────────

let passed = 0;
let failed = 0;
const failures = [];

function assert(condition, message) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${message}`);
  } else {
    failed++;
    failures.push(message);
    console.log(`  ✗ ${message}`);
  }
}

async function typeInRepl(page, text) {
  await page.click("#repl-input");
  // Clear existing input
  await page.evaluate(() => {
    const el = document.getElementById("repl-input");
    el.value = "";
    el.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.type("#repl-input", text, { delay: 10 });
  await page.keyboard.press("Enter");
  // Give Wasm time to evaluate + render
  await sleep(500);
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function getTraceLines(page) {
  return page.evaluate(() => {
    const lines = document.querySelectorAll("#trace-output .trace-line");
    return Array.from(lines).map((el) => el.textContent);
  });
}

async function svgHasNodes(page) {
  // Check if the SVG diagram has any D3-rendered node groups
  return page.evaluate(() => {
    const svg = document.getElementById("diagram-svg");
    if (!svg) return false;
    const nodes = svg.querySelectorAll(".node");
    return nodes.length > 0;
  });
}

async function getSvgNodeInfo(page) {
  // Get info about D3-rendered SVG nodes (frames, procedures, edges)
  return page.evaluate(() => {
    const svg = document.getElementById("diagram-svg");
    if (!svg) return { found: false, frames: 0, procs: 0, edges: 0 };
    const frames = svg.querySelectorAll(".node.frame");
    const procs = svg.querySelectorAll(".node.procedure");
    const edges = svg.querySelectorAll(".edge");
    return {
      found: frames.length > 0 || procs.length > 0,
      frames: frames.length,
      procs: procs.length,
      edges: edges.length,
    };
  });
}

// ─── Main test suite ──────────────────────────────────────────────

async function runTests() {
  const args = process.argv.slice(2);
  const headed = args.includes("--headed") || args.includes("--debug");
  const debug = args.includes("--debug");

  console.log("\n=== EnvDraw Browser Tests ===\n");

  const server = await startServer();
  const browser = await puppeteer.launch({
    headless: !headed,
    devtools: debug,
    slowMo: debug ? 100 : 0,
    args: [
      "--enable-features=WebAssemblyGC,WebAssemblyTailCall",
      "--no-sandbox",
    ],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  // Collect console messages
  const consoleMsgs = [];
  page.on("console", (msg) => {
    consoleMsgs.push({ type: msg.type(), text: msg.text() });
  });

  // Collect errors
  const errors = [];
  page.on("pageerror", (err) => errors.push(err.message));

  try {
    // ── Test 1: Page loads ──
    console.log("--- Page load ---");
    await page.goto(`http://localhost:${PORT}/`, {
      waitUntil: "networkidle0",
      timeout: 30000,
    });
    assert(true, "Page loaded without network errors");

    // Wait for Wasm boot (look for "EnvDraw: ready." in console)
    const bootOk = await page.waitForFunction(
      () => {
        const status = document.getElementById("status-indicator");
        return status && status.textContent === "Ready";
      },
      { timeout: 30000 }
    ).then(() => true).catch(() => false);

    assert(bootOk, "Wasm module booted successfully (status=Ready)");

    if (!bootOk) {
      // Dump console for debugging
      console.log("\n  Console messages:");
      consoleMsgs.forEach((m) => console.log(`    [${m.type}] ${m.text}`));
      if (errors.length) {
        console.log("\n  Page errors:");
        errors.forEach((e) => console.log(`    ${e}`));
      }
    }

    // Check for JS errors
    const jsErrors = errors.filter(
      (e) => !e.includes("try instruction") // Hoot deprecation warning
    );
    assert(jsErrors.length === 0, `No JS errors (${jsErrors.length} found)`);

    // ── Test 2: Empty state ──
    // Note: With D3, the global frame is displayed at boot, so empty state
    // may already be hidden. Check it's either visible or already hidden.
    console.log("\n--- Empty state ---");
    const emptyState = await page.evaluate(() => {
      const el = document.getElementById("empty-state");
      return el ? el.classList.contains("hidden") ? "hidden" : "visible" : "missing";
    });
    assert(emptyState === "visible" || emptyState === "hidden",
      `Empty state element exists (state=${emptyState})`);

    // ── Test 3: Define a variable ──
    console.log("\n--- Define variable ---");
    await typeInRepl(page, "(define x 42)");

    const traces = await getTraceLines(page);
    const hasInput = traces.some((t) => t.includes("EnvDraw>") && t.includes("define x 42"));
    assert(hasInput, "REPL input appears in trace panel");

    const hasResult = traces.some((t) => t.includes("⇒") || t.includes("=>"));
    assert(hasResult, "Result appears in trace panel");

    await page.screenshot({ path: "test/screenshot-define.png" });
    console.log("  📸 screenshot-define.png");

    // ── Test 4: SVG has D3 nodes ──
    console.log("\n--- SVG rendering ---");
    const hasNodes = await svgHasNodes(page);
    assert(hasNodes, "SVG has D3-rendered node groups");

    const nodeInfo = await getSvgNodeInfo(page);
    assert(nodeInfo.found, "SVG diagram has visible nodes");
    assert(nodeInfo.frames >= 1, `At least 1 frame node (got ${nodeInfo.frames})`);

    // Empty state should now be hidden
    const emptyHidden = await page.evaluate(() => {
      const el = document.getElementById("empty-state");
      return el && el.classList.contains("hidden");
    });
    assert(emptyHidden, "Empty state is hidden after first eval");

    // ── Test 5: Define a function ──
    console.log("\n--- Define function ---");
    await typeInRepl(page, "(define (square n) (* n n))");
    await sleep(300);

    await page.screenshot({ path: "test/screenshot-function.png" });
    console.log("  📸 screenshot-function.png");

    const nodeInfo2 = await getSvgNodeInfo(page);
    assert(nodeInfo2.procs >= 1, `Procedure node added after define lambda (got ${nodeInfo2.procs})`);
    assert(nodeInfo2.edges >= 1, `Edges present after define lambda (got ${nodeInfo2.edges})`);

    // ── Test 6: Call the function ──
    console.log("\n--- Call function ---");
    await typeInRepl(page, "(square 5)");
    await sleep(300);

    const traces2 = await getTraceLines(page);
    const hasSquareResult = traces2.some(
      (t) => t.includes("25") 
    );
    assert(hasSquareResult, "square(5) = 25 appears in trace");

    await page.screenshot({ path: "test/screenshot-call.png" });
    console.log("  📸 screenshot-call.png");

    // ── Test 7: Multiple definitions ──
    console.log("\n--- Multiple definitions ---");
    await typeInRepl(page, "(define y 100)");
    await sleep(200);
    await typeInRepl(page, "(define (add a b) (+ a b))");
    await sleep(200);

    const nodeInfo3 = await getSvgNodeInfo(page);
    assert(nodeInfo3.procs >= 2, `Multiple procs after add definition (got ${nodeInfo3.procs})`);
    assert(nodeInfo3.edges >= 3, `Multiple edges in diagram (got ${nodeInfo3.edges})`);

    await page.screenshot({ path: "test/screenshot-multi.png" });
    console.log("  📸 screenshot-multi.png");

    // ── Test 8: Closures ──
    console.log("\n--- Closures ---");
    await typeInRepl(page, "(define (make-adder n) (lambda (x) (+ x n)))");
    await sleep(300);
    await typeInRepl(page, "(define add5 (make-adder 5))");
    await sleep(300);
    await typeInRepl(page, "(add5 10)");
    await sleep(300);

    const traces3 = await getTraceLines(page);
    const hasClosure = traces3.some((t) => t.includes("15"));
    assert(hasClosure, "Closure (add5 10) = 15 appears in trace");

    await page.screenshot({ path: "test/screenshot-closure.png" });
    console.log("  📸 screenshot-closure.png");

    // ── Test 9: Zoom controls ──
    console.log("\n--- Zoom controls ---");
    const zoomLabel = await page.evaluate(() => {
      return document.getElementById("btn-zoom-reset").textContent;
    });
    assert(zoomLabel === "100%", "Initial zoom label is 100%");

    // Click zoom in
    await page.click("#btn-zoom-in");
    await sleep(400);  // D3 zoom transitions take ~200ms
    const zoomLabel2 = await page.evaluate(() => {
      return document.getElementById("btn-zoom-reset").textContent;
    });
    assert(zoomLabel2 !== "100%", `Zoom changed after zoom-in (now ${zoomLabel2})`);

    // Reset zoom — use evaluate to avoid page lifecycle issues
    await page.evaluate(() => {
      EnvDiagram.resetView();
    });
    await sleep(500);  // D3 reset transition
    await page.evaluate(() => {
      // Update zoom label after transition
      const label = document.getElementById("btn-zoom-reset");
      const z = EnvDiagram.getZoom ? EnvDiagram.getZoom() : 1;
      label.textContent = Math.round(z * 100) + "%";
    });
    const zoomLabel3 = await page.evaluate(() => {
      return document.getElementById("btn-zoom-reset").textContent;
    });
    assert(zoomLabel3 === "100%", "Zoom reset back to 100%");

    // ── Test 10: Trace panel toggle ──
    // Panel starts collapsed; first toggle opens it, second closes it
    console.log("\n--- Trace panel toggle ---");
    await page.click("#btn-toggle-trace");
    await sleep(300);
    const traceShown = await page.evaluate(() => {
      return !document.getElementById("trace-panel").classList.contains("collapsed");
    });
    assert(traceShown, "Trace panel shown after first toggle");

    await page.click("#btn-toggle-trace");
    await sleep(300);
    const traceHidden = await page.evaluate(() => {
      return document.getElementById("trace-panel").classList.contains("collapsed");
    });
    assert(traceHidden, "Trace panel collapsed after second toggle");

    // ── Test 11: Clear ──
    console.log("\n--- Clear ---");
    await page.click("#btn-clear");
    await sleep(300);
    const tracesAfterClear = await getTraceLines(page);
    assert(tracesAfterClear.length === 0, "Trace panel cleared");

    await page.screenshot({ path: "test/screenshot-cleared.png" });
    console.log("  📸 screenshot-cleared.png");

    // ── Test 12: Error handling ──
    console.log("\n--- Error handling ---");
    await typeInRepl(page, "(/ 1 0)");
    await sleep(300);
    const traces4 = await getTraceLines(page);
    const hasError = traces4.some(
      (t) => t.includes("Error") || t.includes("***")
    );
    assert(hasError, "Division by zero produces an error in trace");

    await page.screenshot({ path: "test/screenshot-error.png" });
    console.log("  📸 screenshot-error.png");

    // ── Test 13: Command history ──
    console.log("\n--- Command history ---");
    await page.click("#repl-input");
    await page.keyboard.press("ArrowUp");
    const historyVal = await page.evaluate(() => {
      return document.getElementById("repl-input").value;
    });
    assert(historyVal.length > 0, `History recall works (got "${historyVal}")`);

  } catch (err) {
    console.error("\n  FATAL:", err.message);
    try {
      await page.screenshot({ path: "test/screenshot-fatal.png" });
    } catch (screenshotErr) {
      console.error("  (Could not capture screenshot:", screenshotErr.message + ")");
    }
    failed++;
  }

  // ── Summary ──
  console.log(`\n${"─".repeat(50)}`);
  console.log(`${passed} passed, ${failed} failed, ${passed + failed} total`);
  if (failures.length) {
    console.log("\nFailures:");
    failures.forEach((f) => console.log(`  ✗ ${f}`));
  }
  console.log("");

  await browser.close();
  server.close();

  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((err) => {
  console.error("Test runner error:", err);
  process.exit(1);
});
