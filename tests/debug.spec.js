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

  const blocks = [
    `(display 2)`,
    `(display "hello")`,
    `(newline)`,
    `(display '(1 2 3))`,
  ];

  for (let i = 0; i < blocks.length; i++) {
    const errsBefore = errors.length;
    await page.evaluate((code) => {
      const input = document.getElementById("repl-input");
      input.value = code;
      input.dispatchEvent(new Event("input"));
      input.dispatchEvent(
        new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
      );
    }, blocks[i]);
    await expect(status).toHaveText("Ready", { timeout: 30000 });

    const newErrs = errors.slice(errsBefore);
    if (newErrs.length > 0) {
      console.log(`Block ${i} [${blocks[i]}] ERRORS:`, JSON.stringify(newErrs));
    } else {
      console.log(`Block ${i} [${blocks[i]}]: OK`);
    }
  }

  console.log("ALL ERRORS:", JSON.stringify(errors));
});
