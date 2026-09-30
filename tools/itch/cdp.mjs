// Drives the visible itch.io Chrome window (its own profile, remote debugging on 9555), in a
// tab of its own so it never steers a tab another session is using. The tab id is kept in
// build/itch_tab.txt; a missing or closed tab is replaced with a new one.
//   node tools/itch/cdp.mjs go <url>                 navigate and wait
//   node tools/itch/cdp.mjs eval "<js>"              run JS, print the result
//   node tools/itch/cdp.mjs evalfile <file.js>       the same, from a file
//   node tools/itch/cdp.mjs shot <file.png>          screenshot
//   node tools/itch/cdp.mjs files <css> <n> <paths...>   put files into the n-th matching file <input>
//   node tools/itch/cdp.mjs click <x> <y>            a real mouse click at page pixels
//   node tools/itch/cdp.mjs choose <css> <paths...>  click a button and answer the file dialog it opens
import { readFileSync, writeFileSync, existsSync } from "node:fs";
const B = "http://127.0.0.1:9555", TAB = new URL("../../build/itch_tab.txt", import.meta.url);
const [cmd, ...args] = process.argv.slice(2);
const tabs = (await (await fetch(B + "/json")).json()).filter((t) => t.type === "page");
let tab = existsSync(TAB) && tabs.find((t) => t.id === readFileSync(TAB, "utf8").trim());
if (!tab) { tab = await (await fetch(B + "/json/new?about:blank", { method: "PUT" })).json(); writeFileSync(TAB, tab.id); }
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0; const wait = {};
ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (wait[m.id]) { wait[m.id](m); delete wait[m.id]; } });
const send = (method, params = {}) => new Promise((r) => { wait[++id] = r; ws.send(JSON.stringify({ id, method, params })); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ev = async (expr) => { const r = await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true }); return r.result?.result?.value ?? r.result?.exceptionDetails?.exception?.description; };
if (cmd === "evalfile") console.log(JSON.stringify(await ev(readFileSync(args[0], "utf8")), null, 1));
if (cmd === "eval") console.log(JSON.stringify(await ev(args[0]), null, 1));
if (cmd === "go") { await send("Page.navigate", { url: args[0] }); await sleep(4000); console.log(await ev("location.href + ' | ' + document.title")); }
if (cmd === "shot") { const s = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: args[1] === "full" }); writeFileSync(args[0], Buffer.from(s.result.data, "base64")); console.log(args[0]); }
if (cmd === "files") {
  await send("DOM.enable");
  const doc = await send("DOM.getDocument", { depth: -1, pierce: true });
  const q = await send("DOM.querySelectorAll", { nodeId: doc.result.root.nodeId, selector: args[0] });
  const ids = q.result.nodeIds; const n = Number(args[1]);
  await send("DOM.setFileInputFiles", { nodeId: ids[n], files: args.slice(2) });
  console.log("set", args.slice(2).length, "file(s) on input", n, "of", ids.length);
}
if (cmd === "click") {
  const [x, y] = args.map(Number);
  for (const type of ["mousePressed", "mouseReleased"]) await send("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
  console.log("clicked", x, y);
}
if (cmd === "choose") {
  const { resolve } = await import("node:path");
  let chooser = null;
  ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.method === "Page.fileChooserOpened") chooser = m.params; });
  await send("Page.enable"); await send("DOM.enable");
  await send("Page.setInterceptFileChooserDialog", { enabled: true });
  // "text:Upload Cover Image" picks the button by its label; anything else is a CSS selector
  const pick = args[0].startsWith("text:")
    ? `[...document.querySelectorAll('button,a,.button')].find((b) => b.textContent.trim() === ${JSON.stringify(args[0].slice(5))})`
    : `document.querySelector(${JSON.stringify(args[0])})`;
  // a real mouse press on the button: some pickers ignore a scripted click()
  const box = await ev(`(() => { const b = ${pick}; b.scrollIntoView({ block: "center" }); const r = b.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()`);
  await sleep(300);
  for (const type of ["mousePressed", "mouseReleased"]) await send("Input.dispatchMouseEvent", { type, x: box[0], y: box[1], button: "left", clickCount: 1 });
  for (let i = 0; i < 50 && !chooser; i++) await sleep(100);
  if (!chooser) { console.log("no file dialog opened"); process.exit(1); }
  await send("DOM.setFileInputFiles", { backendNodeId: chooser.backendNodeId, files: args.slice(1).map((f) => resolve(f)) });
  await sleep(500);
  await send("Page.setInterceptFileChooserDialog", { enabled: false });
  console.log("chose", args.length - 1, "file(s)");
}
ws.close(); process.exit(0);
