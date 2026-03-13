const { test, expect } = require('@playwright/test');

function getLayoutInfo(page) {
  return page.evaluate(() => {
    const all = EnvDiagram.nodeList();
    const edges = EnvDiagram.edgeList();
    const frames = all.filter(n => n.type === 'frame');
    const procs = all.filter(n => n.type === 'procedure');
    const pairs = all.filter(n => n.type === 'pair' || n.type === 'pair-atom' || n.type === 'pair-null');
    
    function range(arr) {
      const xs = arr.map(n => Math.round(n.x)), ys = arr.map(n => Math.round(n.y));
      return { minX: Math.min(...xs), maxX: Math.max(...xs), w: Math.max(...xs) - Math.min(...xs),
               minY: Math.min(...ys), maxY: Math.max(...ys), h: Math.max(...ys) - Math.min(...ys) };
    }
    return {
      counts: { frames: frames.length, procs: procs.length, pairs: pairs.length, total: all.length },
      frameRange: frames.length ? range(frames) : null,
      procRange: procs.length ? range(procs) : null,
      pairRange: pairs.length ? range(pairs) : null,
    };
  });
}

test('force layout analysis', async ({ page }) => {
  await page.goto('/');
  const status = page.locator("#status-indicator");
  await expect(status).toHaveText("Ready", { timeout: 15000 });
  await page.evaluate((n) => {
    const flyout = document.getElementById("examples-flyout");
    const btn = Array.from(flyout.querySelectorAll(".ex-btn")).find(b => b.textContent === n);
    if (btn) btn.click();
  }, "skiplist");
  await expect(status).toHaveText("Ready", { timeout: 30000 });
  await page.waitForTimeout(3000);
  
  let info = await getLayoutInfo(page);
  console.log("PRE-GC:", JSON.stringify(info.counts));
  console.log("  frames:", JSON.stringify(info.frameRange));
  console.log("  procs:", JSON.stringify(info.procRange));
  console.log("  pairs:", JSON.stringify(info.pairRange));
  
  // Verify procs aren't much wider than frames
  if (info.procRange && info.frameRange) {
    const procSpread = info.procRange.w;
    const frameSpread = info.frameRange.w;
    console.log("  proc/frame width ratio:", (procSpread / Math.max(frameSpread, 1)).toFixed(2));
  }
});
