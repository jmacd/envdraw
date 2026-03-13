// @ts-check
import { test, expect } from "@playwright/test";

// Helper: wait for Wasm to load and status to show "Ready"
async function waitForReady(page) {
  await page.goto("/");
  const status = page.locator("#status-indicator");
  await expect(status).toHaveText("Ready", { timeout: 15000 });
  await expect(status).toHaveClass(/status-ready/);
}

// Helper: submit Scheme code via the REPL.
// Uses page.evaluate because the synchronous Scheme eval blocks the main
// thread — Playwright's fill()/press() cannot resolve until it finishes.
async function submitCode(page, code) {
  await page.evaluate((c) => {
    const input = document.getElementById("repl-input");
    input.value = c;
    input.dispatchEvent(new Event("input"));
    // Trigger the submit handler (Enter keydown)
    input.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
    );
  }, code);
  // Wait for status to return to Ready (evaluation complete)
  const status = page.locator("#status-indicator");
  await expect(status).toHaveText("Ready", { timeout: 30000 });
}

// Helper: select an example from the flyout menu
async function selectExample(page, name) {
  await page.evaluate((n) => {
    const flyout = document.getElementById("examples-flyout");
    const btn = Array.from(flyout.querySelectorAll(".ex-btn")).find(b => b.textContent === n);
    if (btn) btn.click();
  }, name);
  const status = page.locator("#status-indicator");
  await expect(status).toHaveText("Ready", { timeout: 30000 });
}

// Collect console errors during a test
function trackConsoleErrors(page) {
  const errors = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") errors.push(msg.text());
  });
  page.on("pageerror", (err) => {
    errors.push(err.message);
  });
  return errors;
}

// Filter out known debug logging that uses console.error
function realErrors(errors) {
  return errors.filter((e) => !e.includes("[d3AddBinding]"));
}

// ─── Boot tests ─────────────────────────────────────────────

test.describe("Boot", () => {
  test("page loads and Wasm initializes", async ({ page }) => {
    const errors = trackConsoleErrors(page);
    await waitForReady(page);

    // Empty state should be visible
    const emptyState = page.locator("#empty-state");
    await expect(emptyState).toBeVisible();

    expect(realErrors(errors)).toEqual([]);
  });

  test("examples flyout is populated", async ({ page }) => {
    await waitForReady(page);
    const buttons = page.locator("#examples-flyout .ex-btn");
    // 2 examples (factorial, skiplist)
    await expect(buttons).toHaveCount(2);
  });
});

// ─── Factorial tests ────────────────────────────────────────

test.describe("Factorial example", () => {
  test("evaluates without errors and renders diagram", async ({ page }) => {
    const errors = trackConsoleErrors(page);
    await waitForReady(page);

    await submitCode(
      page,
      "(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))"
    );

    // Diagram should now have at least one node (D3 class: "node frame")
    const nodes = page.locator("#diagram-svg .node");
    await expect(nodes.first()).toBeVisible({ timeout: 5000 });

    // Empty state should be hidden
    const emptyState = page.locator("#empty-state");
    await expect(emptyState).toHaveClass(/hidden/);

    // Call fact — should produce 120
    await submitCode(page, "(fact 5)");
    const replLog = page.locator("#repl-log");
    await expect(replLog).toContainText("120");

    expect(realErrors(errors)).toEqual([]);
  });
});

// ─── Skiplist tests ─────────────────────────────────────────

test.describe("Skiplist example", () => {
  test("evaluates without errors", async ({ page }) => {
    const errors = trackConsoleErrors(page);
    await waitForReady(page);

    await selectExample(page, "skiplist");

    // Should not have page errors (the "node not found" bug)
    expect(realErrors(errors)).toEqual([]);
  });

  test("completes within time budget", async ({ page }) => {
    await waitForReady(page);

    const start = Date.now();
    await selectExample(page, "skiplist");
    const elapsed = Date.now() - start;

    // Should complete in under 10 seconds
    expect(elapsed).toBeLessThan(10000);
  });
});

// ─── Layout mode tests ──────────────────────────────────────

test.describe("Grid layout", () => {
  test("switches to grid and pins pair nodes", async ({ page }) => {
    const errors = trackConsoleErrors(page);
    await waitForReady(page);
    await submitCode(page, "(define x (cons 1 (cons 2 3)))");

    // Switch to grid layout
    await page.evaluate(() => {
      const sel = document.getElementById("sel-layout");
      sel.value = "grid";
      sel.dispatchEvent(new Event("change"));
    });

    // Check that pair nodes have fx/fy set (pinned)
    const pinned = await page.evaluate(() => {
      const stats = EnvDiagram.stats();
      // Access internal state: pairs should be pinned
      return EnvDiagram.getLayout() === "grid" && stats.pair > 0;
    });
    expect(pinned).toBe(true);
    expect(realErrors(errors)).toEqual([]);
  });

  test("grid layout works with skiplist example", async ({ page }) => {
    const errors = trackConsoleErrors(page);
    await waitForReady(page);

    // Switch to grid first, then load skiplist
    await page.evaluate(() => {
      const sel = document.getElementById("sel-layout");
      sel.value = "grid";
      sel.dispatchEvent(new Event("change"));
    });

    await selectExample(page, "skiplist");

    const stats = await page.evaluate(() => EnvDiagram.stats());
    expect(stats.pair).toBeGreaterThan(0);
    expect(stats._pairTrees).toBeGreaterThan(0);
    expect(realErrors(errors)).toEqual([]);
  });
});
