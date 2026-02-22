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
 *   4. Checks that canvas has non-empty rendering
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
    document.getElementById("repl-input").value = "";
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

async function canvasHasContent(page) {
  // Check if any non-white pixels exist on the canvas
  return page.evaluate(() => {
    const canvas = document.getElementById("diagram-canvas");
    if (!canvas) return false;
    const ctx = canvas.getContext("2d");
    const { width, height } = canvas;
    if (width === 0 || height === 0) return false;
    const data = ctx.getImageData(0, 0, width, height).data;
    // Check a sample of pixels for any non-white/non-transparent
    for (let i = 0; i < data.length; i += 40) {
      // RGBA — check if not white (255,255,255) and not transparent (alpha 0)
      const r = data[i], g = data[i+1], b = data[i+2], a = data[i+3];
      if (a > 0 && (r < 250 || g < 250 || b < 250)) {
        return true;
      }
    }
    return false;
  });
}

async function getNodePositions(page) {
  // Read scene graph node positions from the console
  // We'll use the trace panel to infer, or check canvas pixels
  // For now, examine colored pixel clusters
  return page.evaluate(() => {
    const canvas = document.getElementById("diagram-canvas");
    if (!canvas) return [];
    const ctx = canvas.getContext("2d");
    const { width, height } = canvas;
    if (width === 0 || height === 0) return [];

    const data = ctx.getImageData(0, 0, width, height).data;
    const dpr = window.devicePixelRatio || 1;
    const clusters = [];

    // Find bounding boxes of colored regions (non-white, non-transparent)
    let minX = width, minY = height, maxX = 0, maxY = 0;
    let found = false;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const i = (y * width + x) * 4;
        const r = data[i], g = data[i+1], b = data[i+2], a = data[i+3];
        if (a > 0 && (r < 250 || g < 250 || b < 250)) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
          found = true;
        }
      }
    }

    if (found) {
      return {
        found: true,
        bounds: {
          minX: Math.round(minX / dpr),
          minY: Math.round(minY / dpr),
          maxX: Math.round(maxX / dpr),
          maxY: Math.round(maxY / dpr),
          width: Math.round((maxX - minX) / dpr),
          height: Math.round((maxY - minY) / dpr),
        }
      };
    }
    return { found: false };
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

    // ── Test 2: Empty state visible ──
    console.log("\n--- Empty state ---");
    const emptyVisible = await page.evaluate(() => {
      const el = document.getElementById("empty-state");
      return el && !el.classList.contains("hidden");
    });
    assert(emptyVisible, "Empty state placeholder is visible");

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

    // ── Test 4: Canvas has content ──
    console.log("\n--- Canvas rendering ---");
    const hasContent = await canvasHasContent(page);
    assert(hasContent, "Canvas has non-white pixels (something was drawn)");

    const positions = await getNodePositions(page);
    if (positions.found) {
      assert(
        positions.bounds.minX > 0 || positions.bounds.minY > 0,
        `Diagram not stuck at origin (bounds: ${positions.bounds.minX},${positions.bounds.minY} → ${positions.bounds.maxX},${positions.bounds.maxY})`
      );
      assert(
        positions.bounds.width > 50 && positions.bounds.height > 20,
        `Diagram has reasonable size (${positions.bounds.width}×${positions.bounds.height}px)`
      );
    } else {
      assert(false, "Could not find diagram pixels on canvas");
    }

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

    const positions2 = await getNodePositions(page);
    if (positions2.found) {
      assert(
        positions2.bounds.width > positions.bounds?.width || 0,
        "Diagram grew after defining a function"
      );
    }

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

    const positions3 = await getNodePositions(page);
    if (positions3.found) {
      assert(
        positions3.bounds.width > 100,
        `Multiple elements spread out (width=${positions3.bounds.width}px)`
      );
    }

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
    await sleep(200);
    const zoomLabel2 = await page.evaluate(() => {
      return document.getElementById("btn-zoom-reset").textContent;
    });
    assert(zoomLabel2 !== "100%", `Zoom changed after zoom-in (now ${zoomLabel2})`);

    // Reset zoom
    await page.click("#btn-zoom-reset");
    await sleep(200);
    const zoomLabel3 = await page.evaluate(() => {
      return document.getElementById("btn-zoom-reset").textContent;
    });
    assert(zoomLabel3 === "100%", "Zoom reset back to 100%");

    // ── Test 10: Trace panel toggle ──
    console.log("\n--- Trace panel toggle ---");
    await page.click("#btn-toggle-trace");
    await sleep(300);
    const traceHidden = await page.evaluate(() => {
      return document.getElementById("trace-panel").classList.contains("collapsed");
    });
    assert(traceHidden, "Trace panel collapsed after toggle");

    await page.click("#btn-toggle-trace");
    await sleep(300);
    const traceShown = await page.evaluate(() => {
      return !document.getElementById("trace-panel").classList.contains("collapsed");
    });
    assert(traceShown, "Trace panel shown after second toggle");

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
    await page.screenshot({ path: "test/screenshot-fatal.png" });
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
