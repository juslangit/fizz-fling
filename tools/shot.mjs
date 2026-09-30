// Screenshots the web build in headless Chrome (no window), for checking the look.
//   node tools/shot.mjs "http://localhost:8063/?demo" out-prefix [seconds...]
import { spawn } from "node:child_process";
import { writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
const [url, prefix, ...times] = process.argv.slice(2);
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
  "--headless=new", "--remote-debugging-port=9344", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
  "--window-size=405,820", ...(process.env.SHOT_AUTOPLAY ? ["--autoplay-policy=no-user-gesture-required"] : []), ...(process.env.SHOT_NOISOLATE ? ["--disable-site-isolation-trials", "--disable-features=IsolateOrigins,site-per-process"] : []), "--hide-scrollbars", `--user-data-dir=${mkdtempSync(tmpdir() + "/fizz-")}`, "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 40 && !target; i++) {
  await sleep(250);
  try { target = (await (await fetch("http://127.0.0.1:9344/json")).json()).find((t) => t.type === "page"); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0; const waiting = {};
ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (waiting[m.id]) { waiting[m.id](m.result); delete waiting[m.id]; } });
const send = (method, params = {}) => new Promise((r) => { waiting[++id] = r; ws.send(JSON.stringify({ id, method, params })); });
const logs = [];
ws.addEventListener("message", (e) => { const m = JSON.parse(e.data);
  if (m.method === "Runtime.consoleAPICalled") logs.push(m.params.type + ": " + m.params.args.map((a) => a.value ?? a.description).join(" "));
  if (m.method === "Runtime.exceptionThrown") logs.push("exception: " + m.params.exceptionDetails.text); });
await send("Runtime.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 405, height: 820, deviceScaleFactor: 2, mobile: true });
await send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
await send("Page.navigate", { url });
let t0 = 0;
if (process.env.SHOT_STATES) {  // "SHAKE:1.5,FLIGHT:0.4,RESULT:1" -> shot each state, N seconds after it starts
  const want = process.env.SHOT_STATES.split(",").map((w) => w.split(":"));
  const start = Date.now();
  for (const [st, after] of want) {
    let seen = false;
    while (!seen && Date.now() - start < 240000) {
      const r = await send("Runtime.evaluate", { expression: "window.fizz && fizz.state", returnByValue: true });
      seen = r.result.value === st;
      if (!seen) await sleep(150);
    }
    await sleep(Number(after || 0) * 1000);
    const shot = await send("Page.captureScreenshot", { format: "png" });
    writeFileSync(`${prefix}-${st}-${after}.png`, Buffer.from(shot.data, "base64"));
    console.log(`${prefix}-${st}-${after}.png`, seen ? "" : "(timed out)");
  }
  chrome.kill(); process.exit(0);
}
if (process.env.SHOT_BURST) {  // start:count:ms -> many quick frames for a GIF
  const [start, count, ms] = process.env.SHOT_BURST.split(":").map(Number);
  await sleep(start * 1000);
  for (let i = 0; i < count; i++) {
    const t = Date.now();
    const shot = await send("Page.captureScreenshot", { format: "jpeg", quality: 85 });
    writeFileSync(`${prefix}-${String(i).padStart(4, "0")}.jpg`, Buffer.from(shot.data, "base64"));
    await sleep(Math.max(0, ms - (Date.now() - t)));
  }
  chrome.kill(); process.exit(0);
}
if (process.env.SHOT_TAP) {  // tap the screen centre after N seconds (like a finger), then continue
  const at = Number(process.env.SHOT_TAP); await sleep(at * 1000); t0 = at;
  const pt = process.env.SHOT_TAPXY ? process.env.SHOT_TAPXY.split(",").map(Number) : [200, 700];
  await send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: pt[0], y: pt[1] }] });
  await sleep(200);                                  // a real finger stays down a moment
  await send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  if (process.env.SHOT_STICK) {  // later: left thumb drags left, right thumb holds (touch steering)
    const at2 = Number(process.env.SHOT_STICK); await sleep((at2 - at) * 1000); t0 = at2;
    await send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: 100, y: 600, id: 1 }, { x: Number(process.env.SHOT_HOLD_X || 320), y: Number(process.env.SHOT_HOLD_Y || 600), id: 2 }] });
    for (let i = 1; i <= 10; i++) { await send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: 100 - i * 6, y: 600, id: 1 }, { x: Number(process.env.SHOT_HOLD_X || 320), y: Number(process.env.SHOT_HOLD_Y || 600), id: 2 }] }); await sleep(30); }
  }
}
for (const t of (times.length ? times : ["20"]).map(Number)) {
  await sleep((t - t0) * 1000); t0 = t;
  const shot = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(`${prefix}-${t}s.png`, Buffer.from(shot.data, "base64"));
  console.log(`${prefix}-${t}s.png`);
}
if (process.env.SHOT_EVAL) { const r = await send("Runtime.evaluate", { expression: process.env.SHOT_EVAL, returnByValue: true }); console.log("EVAL:", JSON.stringify(r.result.value)); }
if (process.env.SHOT_TABS) { const tabs = await (await fetch("http://127.0.0.1:9344/json")).json(); console.log("TABS:", tabs.filter((t) => t.type === "page").map((t) => t.url).join(" | ")); }
if (process.env.SHOT_LOG) console.log(logs.filter((l) => /error|warn|exception|audio|OPENFULL/i.test(l)).slice(0, 40).join("\n"));
chrome.kill();
process.exit(0);
