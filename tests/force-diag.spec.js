const { test, expect } = require('@playwright/test');
test('proc edge analysis', async ({ page }) => {
  await page.goto('/');
  const status = page.locator("#status-indicator");
  await expect(status).toHaveText("Ready", { timeout: 15000 });
  await page.evaluate((n) => {
    const sel = document.getElementById("sel-examples");
    sel.value = n; sel.dispatchEvent(new Event("change"));
  }, "skiplist");
  await expect(status).toHaveText("Ready", { timeout: 30000 });
  await page.waitForTimeout(3000);
  const info = await page.evaluate(() => {
    const all = EnvDiagram.nodeList();
    const edges = EnvDiagram.edgeList();
    const procs = all.filter(n => n.type === 'procedure');
    // For each proc, count its edges
    return procs.map(p => {
      const myEdges = edges.filter(e => e.source === p.id || e.target === p.id);
      return { id: p.id, x: p.x, y: p.y, edgeCount: myEdges.length, types: myEdges.map(e => e.type) };
    });
  });
  const outliers = info.filter(p => Math.abs(p.x) > 500 || Math.abs(p.y) > 400);
  console.log("Total procs:", info.length);
  console.log("Outliers:", outliers.length, JSON.stringify(outliers.slice(0,5)));
  const noEdge = info.filter(p => p.edgeCount === 0);
  console.log("No-edge procs:", noEdge.length);
  const fewEdge = info.filter(p => p.edgeCount <= 1);
  console.log("<=1 edge procs:", fewEdge.length, JSON.stringify(fewEdge.slice(0,5)));
});
