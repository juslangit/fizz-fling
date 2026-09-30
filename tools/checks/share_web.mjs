// The SHARE button end to end in headless Chrome: plays a demo round to its result, waits for
// the game to hand the page its picture, presses SHARE like a finger (press, then release), and
// checks the page shared or downloaded it. Saves the picture to build/share-card.jpg to look at.
//   node tools/checks/share_web.mjs [query]      (needs build/web served on :8064)
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
const PORT = 9346, q = process.argv[2] || "demo";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
  "--headless=new", `--remote-debugging-port=${PORT}`, "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
  "--window-size=405,820", `--user-data-dir=${mkdtempSync(tmpdir() + "/fizz-share-")}`, "about:blank"], { stdio: "ignore" });
let target;
for (let i = 0; i < 40 && !target; i++) { await sleep(250); try { target = (await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()).find((t) => t.type === "page"); } catch {} }
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0; const wait = {};
ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (wait[m.id]) { wait[m.id](m.result); delete wait[m.id]; } });
const send = (method, params = {}) => new Promise((r) => { wait[++id] = r; ws.send(JSON.stringify({ id, method, params })); });
const ev = async (x) => (await send("Runtime.evaluate", { expression: x, returnByValue: true })).result?.value;
await send("Emulation.setDeviceMetricsOverride", { width: 405, height: 820, deviceScaleFactor: 2, mobile: true });
await send("Page.navigate", { url: `http://localhost:8064/?${q}` });
const t0 = Date.now();
while (Date.now() - t0 < 200000 && !(await ev("window.fizz && fizz.state === 'RESULT' && !!fizz.out.share_ready"))) await sleep(200);
let fails = 0;
const check = (n, ok, d) => { console.log((ok ? "PASS  " : "FAIL  ") + n + (d ? "   " + d : "")); if (!ok) fails++; };
const b64 = await ev("fizz.shareB64");
check("the result hands the page a share picture", !!b64 && b64.length > 20000, b64 ? `${Math.round(b64.length * 0.75 / 1024)} KB, text: ${await ev("fizz.shareText")}` : "none");
if (b64) writeFileSync("build/share-card.jpg", Buffer.from(b64, "base64"));
// the SHARE button sits at the right of the row under the card (405-wide page pixels)
await ev("fizz.shared = ''");
if (process.env.DEBUG) {
  await ev("window.__clicks = 0; document.addEventListener('click', () => window.__clicks++, true); window.addEventListener('error', e => window.__err = String(e.message)); 1");
}
await send("Input.dispatchMouseEvent", { type: "mousePressed", x: 294, y: 660, button: "left", clickCount: 1 });
let armed = false;   // headless runs at a few frames a second: hold until the game has seen the press
for (let i = 0; i < 30 && !armed; i++) { await sleep(100); armed = await ev("fizz.shareArmed"); }
check("pressing SHARE arms the picture in the page", armed);
await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: 294, y: 660, button: "left", clickCount: 1 });
await sleep(1000);
const shared = await ev("fizz.shared");
if (process.env.DEBUG) console.log("clicks seen:", await ev("window.__clicks"), "error:", await ev("window.__err || ''"),
  "canShare:", await ev("typeof navigator.canShare"), "armed after:", await ev("fizz.shareArmed"));
check("pressing SHARE shares the picture (the phone's share sheet opens, or it downloads where sharing is not offered)", ["sharing", "shared", "downloaded", "cancelled"].includes(shared), `fizz.shared = '${shared}'`);
chrome.kill();
console.log(`\n${fails} failed`);
process.exit(fails ? 1 : 0);
