// @ts-check
import { test, expect } from "@playwright/test";

// Diagnostic test to pinpoint "wrong number of arguments" in skiplist
test("debug: isolate skiplist wrong-args error", async ({ page }) => {
  const errors = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") errors.push(msg.text());
  });

  await page.goto("/");
  const status = page.locator("#status-indicator");
  await expect(status).toHaveText("Ready", { timeout: 15000 });

  // Load skiplist example
  let totalLogs = 0;
  page.on("console", () => totalLogs++);

  await page.evaluate(() => {
    const sel = document.getElementById("sel-examples");
    sel.value = "skiplist";
    sel.dispatchEvent(new Event("change"));
  });
  await expect(status).toHaveText("Ready", { timeout: 30000 });

  const traceLines = await page.evaluate(() =>
    document.querySelectorAll('.trace-line').length
  );
  console.log(`Trace panel lines: ${traceLines}`);
  console.log(`Total console messages: ${totalLogs}`);
});
