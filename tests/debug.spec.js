// @ts-check
import { test, expect } from "@playwright/test";

// Diagnostic test — node/edge counts for skiplist
test("debug: skiplist diagram stats", async ({ page }) => {
  const errors = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") errors.push(msg.text());
  });

  await page.goto("/");
  const status = page.locator("#status-indicator");
  await expect(status).toHaveText("Ready", { timeout: 15000 });

  // Load skiplist example
  await page.evaluate(() => {
    const sel = document.getElementById("sel-examples");
    sel.value = "skiplist";
    sel.dispatchEvent(new Event("change"));
  });
  await expect(status).toHaveText("Ready", { timeout: 30000 });

  const stats = await page.evaluate(() => EnvDiagram.stats());
  console.log("Diagram stats:", JSON.stringify(stats, null, 2));
  console.log("Console errors:", errors.length);
  if (errors.length > 0) console.log("First error:", errors[0]);
});
