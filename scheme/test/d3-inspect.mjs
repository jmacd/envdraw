#!/usr/bin/env node
/**
 * d3-inspect.mjs — Inspect D3 SVG structure and layout quality
 *
 * Usage:
 *   node test/d3-inspect.mjs              # headless, text report
 *   node test/d3-inspect.mjs --headed     # visible browser
 *   node test/d3-inspect.mjs --screenshot # save screenshots per step
 *
 * Requires: npm install (puppeteer)
 * Starts its own HTTP server on port 8091.
 */

import puppeteer from "puppeteer";
import { createServer } from "http";
import { readFileSync, existsSync } from "fs";
import { resolve, extname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const WEB_DIR = resolve(__dirname, "..", "web");
const PORT = 8091;

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
      const urlPath = req.url.split("?")[0];
      const filePath = join(WEB_DIR, urlPath === "/" ? "index.html" : urlPath);
      if (!existsSync(filePath)) {
        res.writeHead(404);
        res.end("Not found: " + urlPath);
        return;
      }
      const ext = extname(filePath);
      const mime = MIME[ext] || "application/octet-stream";
      res.writeHead(200, { "Content-Type": mime });
      res.end(readFileSync(filePath));
    });
    server.listen(PORT, () => resolve(server));
  });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function typeInRepl(page, text) {
  await page.click("#repl-input");
  await page.evaluate(() => {
    document.getElementById("repl-input").value = "";
  });
  await page.type("#repl-input", text, { delay: 5 });
  await page.keyboard.press("Enter");
  await sleep(800);
}

// ─── SVG inspection helpers ───────────────────────────────────────

async function getSvgInfo(page) {
  return page.evaluate(() => {
    const svg = document.getElementById("diagram-svg");
    if (!svg) return null;

    const nodeEls = svg.querySelectorAll(".node");
    const edgeEls = svg.querySelectorAll(".edge");

    const nodes = [];
    nodeEls.forEach((el) => {
      const d = el.__data__;
      if (!d) return;
      nodes.push({
        id: d.id,
        type: d.type,
        name: d.name || d.lambdaText || "",
        x: Math.round(d.x || 0),
        y: Math.round(d.y || 0),
        width: d.width || 0,
        height: d.height || 0,
        parentId: d.parentId || null,
        frameId: d.frameId || null,
        color: d.color || "",
      });
    });

    const edges = [];
    edgeEls.forEach((el) => {
      const d = el.__data__;
      if (!d) return;
      const sid = typeof d.source === "object" ? d.source.id : d.source;
      const tid = typeof d.target === "object" ? d.target.id : d.target;
      edges.push({
        id: d.id,
        edgeType: d.edgeType,
        source: sid,
        target: tid,
        pathD: (el.getAttribute("d") || "").substring(0, 80),
      });
    });

    const bindings = {};
    const bindingData = window.EnvDiagram?._debug?.bindings;
    // bindings are private, read from DOM instead
    nodeEls.forEach((el) => {
      const d = el.__data__;
      if (d?.type !== "frame") return;
      const bindEls = el.querySelectorAll(".binding");
      const bs = [];
      bindEls.forEach((bel) => {
        const varText = bel.querySelector("text")?.textContent || "";
        const valText = bel.querySelector(".val-label")?.textContent || "";
        const dot = bel.querySelector(".binding-dot");
        bs.push({ var: varText, val: valText, hasDot: !!dot });
      });
      if (bs.length > 0) bindings[d.id] = bs;
    });

    return { nodes, edges, bindings };
  });
}

function analyzeLayout(info) {
  const issues = [];
  const { nodes, edges } = info;

  if (nodes.length === 0) {
    issues.push("ERROR: No nodes in diagram");
    return issues;
  }

  // Check for overlapping nodes
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      const dx = Math.abs(a.x - b.x);
      const dy = Math.abs(a.y - b.y);
      const minDx = (a.width + b.width) / 2;
      const minDy = (a.height + b.height) / 2;
      if (dx < minDx * 0.5 && dy < minDy * 0.5) {
        issues.push(`OVERLAP: ${a.id} (${a.x},${a.y}) and ${b.id} (${b.x},${b.y})`);
      }
    }
  }

  // Check for nodes at extreme positions
  for (const n of nodes) {
    if (Math.abs(n.x) > 2000 || Math.abs(n.y) > 2000) {
      issues.push(`FAR-OFF: ${n.id} at (${n.x},${n.y})`);
    }
    if (n.x === 0 && n.y === 0) {
      issues.push(`ORIGIN: ${n.id} stuck at (0,0)`);
    }
  }

  // Check frame hierarchy (children should be below parents in y)
  const frames = nodes.filter((n) => n.type === "frame");
  for (const f of frames) {
    if (f.parentId) {
      const parent = nodes.find((n) => n.id === f.parentId);
      if (parent && f.y < parent.y) {
        issues.push(`HIERARCHY: ${f.id} (y=${f.y}) above parent ${parent.id} (y=${parent.y})`);
      }
    }
  }

  // Check procedure proximity to enclosing frame
  const procs = nodes.filter((n) => n.type === "procedure");
  for (const p of procs) {
    if (p.frameId) {
      const frame = nodes.find((n) => n.id === p.frameId);
      if (frame) {
        const dist = Math.sqrt((p.x - frame.x) ** 2 + (p.y - frame.y) ** 2);
        if (dist > 500) {
          issues.push(`DISTANT-PROC: ${p.id} is ${Math.round(dist)}px from frame ${frame.id}`);
        }
      }
    }
  }

  // Check for zero-length edge paths
  for (const e of edges) {
    if (!e.pathD || e.pathD === "M0,0 L0,0") {
      issues.push(`ZERO-EDGE: ${e.id} has empty/zero path`);
    }
  }

  return issues;
}

// ─── Main ─────────────────────────────────────────────────────────

async function run() {
  const args = process.argv.slice(2);
  const headed = args.includes("--headed");
  const doScreenshots = args.includes("--screenshot");

  console.log("\n=== D3 Diagram Inspector ===\n");

  const server = await startServer();
  const browser = await puppeteer.launch({
    headless: !headed,
    args: [
      "--enable-features=WebAssemblyGC,WebAssemblyTailCall",
      "--no-sandbox",
    ],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  const errors = [];
  page.on("pageerror", (err) => errors.push(err.message));

  await page.goto(`http://localhost:${PORT}/`, {
    waitUntil: "networkidle0",
    timeout: 30000,
  });

  const booted = await page
    .waitForFunction(
      () => document.getElementById("status-indicator")?.textContent === "Ready",
      { timeout: 30000 }
    )
    .then(() => true)
    .catch(() => false);

  if (!booted) {
    console.error("ERROR: Wasm boot failed");
    await browser.close();
    server.close();
    process.exit(1);
  }

  console.log("Wasm booted OK\n");

  // ── Scenarios ──
  const scenarios = [
    {
      name: "Simple variable",
      exprs: ["(define x 42)"],
    },
    {
      name: "Variable + function",
      exprs: ["(define (square n) (* n n))"],
    },
    {
      name: "Function application",
      exprs: ["(square 5)"],
    },
    {
      name: "Multiple bindings",
      exprs: ["(define y 100)", "(define (add a b) (+ a b))"],
    },
    {
      name: "Closure",
      exprs: [
        "(define (make-counter) (let ((c 0)) (lambda () (set! c (+ c 1)) c)))",
        "(define counter (make-counter))",
        "(counter)",
        "(counter)",
      ],
    },
  ];

  let step = 0;
  for (const scenario of scenarios) {
    step++;
    console.log(`--- ${step}. ${scenario.name} ---`);

    for (const expr of scenario.exprs) {
      console.log(`  eval: ${expr}`);
      await typeInRepl(page, expr);
    }

    // Let force simulation settle
    await sleep(600);

    const info = await getSvgInfo(page);
    if (!info) {
      console.log("  ERROR: Could not read SVG\n");
      continue;
    }

    // Print node summary
    console.log(`  Nodes (${info.nodes.length}):`);
    for (const n of info.nodes) {
      const label = n.type === "frame" ? n.name : n.name.substring(0, 40);
      console.log(
        `    ${n.id.padEnd(6)} ${n.type.padEnd(10)} ${label.padEnd(25)} (${n.x}, ${n.y})  ${n.width}×${n.height}`
      );
    }

    console.log(`  Edges (${info.edges.length}):`);
    for (const e of info.edges) {
      console.log(
        `    ${e.edgeType.padEnd(10)} ${e.source} → ${e.target}  path: ${e.pathD.substring(0, 50)}`
      );
    }

    if (Object.keys(info.bindings).length > 0) {
      console.log(`  Bindings:`);
      for (const [fid, bs] of Object.entries(info.bindings)) {
        for (const b of bs) {
          console.log(
            `    ${fid}: ${b.var} ${b.val || (b.hasDot ? "→●" : "")}`
          );
        }
      }
    }

    // Layout analysis
    const issues = analyzeLayout(info);
    if (issues.length > 0) {
      console.log(`  ⚠ Layout issues:`);
      issues.forEach((i) => console.log(`    ${i}`));
    } else {
      console.log(`  ✓ Layout OK`);
    }

    if (doScreenshots) {
      const fname = `test/screenshot-inspect-${step}.png`;
      await page.screenshot({ path: fname });
      console.log(`  📸 ${fname}`);
    }

    console.log();
  }

  // ── Fit to view ──
  console.log("--- Fit to view ---");
  await page.evaluate(() => EnvDiagram.fitToView());
  await sleep(600);
  if (doScreenshots) {
    await page.screenshot({ path: "test/screenshot-inspect-fit.png" });
    console.log("  📸 test/screenshot-inspect-fit.png");
  }
  console.log("  Done\n");

  // ── Summary ──
  if (errors.length > 0) {
    console.log("JS errors:");
    errors.forEach((e) => console.log(`  ${e}`));
  }

  await browser.close();
  server.close();
  console.log("=== Done ===\n");
}

run().catch((err) => {
  console.error("Inspector error:", err);
  process.exit(1);
});
