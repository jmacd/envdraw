// @ts-check
import { test, expect } from "@playwright/test";

// Diagnostic: check bottom node self-loop edges
test("debug: bottom self-loop edges", async ({ page }) => {
  await page.goto("/");
  const status = page.locator("#status-indicator");
  await expect(status).toHaveText("Ready", { timeout: 15000 });

  // Just run make-tree and the mutations, not the inserts
  await page.evaluate((code) => {
    const input = document.getElementById("repl-input");
    input.value = code;
    input.dispatchEvent(new Event("input"));
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  }, `
(define (make-node value right down)
  (cons (cons value down) right))
(define *maxkey* 'maxkey)
(define *tailkey* 'tailkey)
(define (make-tree)
  (let* ((tail (make-node *tailkey* #t #t))
         (bottom (make-node *tailkey* #t #t))
         (head (make-node *maxkey* tail bottom)))
    (set-cdr! tail tail)
    (set-cdr! bottom bottom)
    (set-cdr! (car bottom) bottom)
    (list head tail bottom)))
(define t (make-tree))
  `);
  await expect(status).toHaveText("Ready", { timeout: 30000 });

  // Find self-loop edges and car/cdr edges involving the same pair
  const edgeInfo = await page.evaluate(() => {
    const stats = EnvDiagram.stats();
    const allEdges = EnvDiagram.edgeList();
    const selfLoops = allEdges.filter(e => e.selfLoop);
    const carCdrEdges = allEdges.filter(e => e.type === 'car' || e.type === 'cdr');
    return { stats, selfLoops, carCdrSample: carCdrEdges.slice(0, 20) };
  });
  console.log("Stats:", JSON.stringify(edgeInfo.stats));
  console.log("Self-loop edges:", edgeInfo.selfLoops.length, JSON.stringify(edgeInfo.selfLoops));
  console.log("Car/cdr edges sample:", JSON.stringify(edgeInfo.carCdrSample));

  // Check for self-loops in the SVG (need to wait for simulation to set path `d` attrs)
  await page.waitForTimeout(500);
  const selfLoops = await page.evaluate(() => {
    const edges = document.querySelectorAll('.edge');
    const paths = [];
    edges.forEach(el => {
      const d = el.getAttribute('d') || '';
      if (d.includes(' C')) {
        paths.push(d.substring(0, 80));
      }
    });
    return { total: edges.length, selfLoopPaths: paths.length, samples: paths.slice(0, 4) };
  });
  console.log("SVG edges:", selfLoops.total, "Self-loops:", selfLoops.selfLoopPaths);
  console.log("Samples:", selfLoops.samples);
});
