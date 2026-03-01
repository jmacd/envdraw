// Quick test: verify (c) returns "1" and "2", not "#<mutable-string>"
import http from "http";
import fs from "fs";
import path from "path";
import puppeteer from "puppeteer";

const server = http.createServer((req, res) => {
  let fp = path.join("web", req.url === "/" ? "index.html" : req.url.split("?")[0]);
  if (!fs.existsSync(fp)) { res.writeHead(404); res.end(); return; }
  const ext = path.extname(fp);
  const ct = {".html":"text/html",".js":"text/javascript",".css":"text/css",".wasm":"application/wasm"}[ext] || "application/octet-stream";
  res.writeHead(200, {"Content-Type": ct});
  fs.createReadStream(fp).pipe(res);
});

server.listen(8097, async () => {
  const browser = await puppeteer.launch({ headless: "new", args: ["--no-sandbox"] });
  const page = await browser.newPage();
  await page.goto("http://localhost:8097/", { waitUntil: "networkidle0", timeout: 30000 });
  await page.waitForFunction(
    () => document.getElementById("status-indicator")?.textContent === "Ready",
    { timeout: 15000 }
  );

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  async function evalExpr(text) {
    await page.click("#repl-input");
    await page.evaluate(() => {
      const el = document.getElementById("repl-input");
      el.value = "";
      el.dispatchEvent(new Event("input", { bubbles: true }));
    });
    await page.type("#repl-input", text, { delay: 5 });
    await page.keyboard.press("Enter");
    await sleep(600);
  }

  await evalExpr("(define (make-counter) (let ((n 0)) (lambda () (set! n (+ n 1)) n)))");
  await evalExpr("(define c (make-counter))");
  await evalExpr("(c)");
  await evalExpr("(c)");

  // Read REPL log entries
  const logText = await page.evaluate(() => document.getElementById("repl-log").innerText);
  console.log("=== REPL Log ===");
  console.log(logText);

  // Check for mutable-string
  if (logText.includes("mutable-string")) {
    console.log("\nFAIL: found #<mutable-string> in output!");
    process.exitCode = 1;
  } else if (logText.includes("⇒ 1") && logText.includes("⇒ 2")) {
    console.log("\nPASS: (c) returns 1 and 2 correctly");
  } else {
    console.log("\nWARN: unexpected output (check above)");
  }

  await browser.close();
  server.close();
});
