// The motion path end to end, without a phone: headless Chrome plays the real web build with
// ?auto (menus click themselves, nothing else is faked in the game) while this script feeds
// the page synthetic DeviceMotionEvents — shaking during SHAKE, a phone tipped 45° to the
// right during AIM — in Android's sign convention or, with ios, iPhone's opposite one.
// It then reads the pressure and angle the game actually used (window.fizz.out.throw).
//   node tools/checks/motion_web.mjs            (needs build/web served on :8064)
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";

const PORT = 9345;   // its own port: other sessions' headless Chrome use 9333/9344/9444+
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function round({ amp, ios, tiltDeg }) {
  const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
    "--headless=new", `--remote-debugging-port=${PORT}`, "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
    "--window-size=405,820", "--autoplay-policy=no-user-gesture-required", `--user-data-dir=${mkdtempSync(tmpdir() + "/fizz-motion-")}`, "about:blank"], { stdio: "ignore" });
  let target;
  for (let i = 0; i < 40 && !target; i++) {
    await sleep(250);
    try { target = (await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()).find((t) => t.type === "page"); } catch {}
  }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r));
  let id = 0; const wait = {};
  ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (wait[m.id]) { wait[m.id](m.result); delete wait[m.id]; } });
  const send = (method, params = {}) => new Promise((r) => { wait[++id] = r; ws.send(JSON.stringify({ id, method, params })); });
  const ev = async (expr) => (await send("Runtime.evaluate", { expression: expr, returnByValue: true })).result?.value;
  await send("Page.navigate", { url: `http://localhost:8064/?auto${ios ? "&forceios" : ""}` });
  // a first tap in an empty corner, as a player's first touch: that is when the page asks for
  // motion permission (iPhones, and newer Chrome, only start sending motion after it)
  await sleep(2500);
  for (const type of ["mousePressed", "mouseReleased"]) await send("Input.dispatchMouseEvent", { type, x: 8, y: 8, button: "left", clickCount: 1 });
  await sleep(300);
  const perm = await ev("fizz.perm + ' listening=' + fizz.listening");
  const k = ios ? -1 : 1;                 // iPhones report the opposite sign
  const g = 9.81, tr = (tiltDeg * Math.PI) / 180;
  let clock = 0, result = null, lastSent = 0;
  const started = Date.now();
  while (!result && Date.now() - started < 180000) {
    const st = await ev("window.fizz && fizz.state");
    // one event per 1/60 s of real time since the last batch, like a phone's sensor: the page
    // integrates shake energy over event.interval, so fewer events would mean less shaking
    const now = Date.now();
    const n = Math.max(1, Math.round((now - (lastSent || now - 100)) * 60 / 1000));
    lastSent = now;
    const events = [];
    for (let i = 0; i < n; i++) {
      clock += 1 / 60;
      let lin = [0, 0, 0], up = [0, g, 0];                       // held upright, still
      if (st === "SHAKE") lin = [amp * Math.sin(2 * Math.PI * 5 * clock), 0.4 * amp * Math.sin(2 * Math.PI * 3 * clock + 1), 0];
      if (st === "AIM") up = [-g * Math.sin(tr), g * Math.cos(tr), 0];   // top of the phone tipped right
      const inc = up.map((u, j) => k * (u + lin[j]));
      events.push({ lin, inc, iv: ios ? 1 / 60 : 1000 / 60 });
    }
    await ev(`(${JSON.stringify(events)}).forEach(e => window.dispatchEvent(new DeviceMotionEvent('devicemotion', {
      acceleration: {x: e.lin[0], y: e.lin[1], z: e.lin[2]},
      accelerationIncludingGravity: {x: e.inc[0], y: e.inc[1], z: e.inc[2]}, interval: e.iv })))`);
    result = await ev("window.fizz && fizz.out.throw && JSON.stringify(fizz.out.throw)");
    if (process.env.DEBUG && Math.random() < 0.05) console.log(st, await ev("JSON.stringify({ev: fizz.events, has: fizz.has, perm: fizz.perm, sh: fizz.shake, ux: fizz.ux, uy: fizz.uy, l: fizz.listening})"));
    await sleep(100);
  }
  chrome.kill();
  await sleep(500);
  if (process.env.DEBUG) console.log("permission after the first tap:", perm);
  return result ? JSON.parse(result) : null;
}

let fails = 0;
const check = (name, ok, detail) => { console.log((ok ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : "")); if (!ok) fails++; };
const hard = await round({ amp: 22, ios: false, tiltDeg: 45 });
check("Android, hard shaking (22 m/s², 5 Hz) builds 80-97% pressure", hard && hard.pressure >= 0.8 && hard.pressure <= 0.97, JSON.stringify(hard));
check("Android, phone tipped 45° right aims the bottle at 45° (±4°)", hard && Math.abs(hard.elev - 45) <= 4);
const gentle = await round({ amp: 6, ios: false, tiltDeg: 20 });
check("gentle shaking (6 m/s²) builds under half the pressure", gentle && gentle.pressure < 0.5, JSON.stringify(gentle));
check("tipped only 20° aims steep, at 70° (±4°)", gentle && Math.abs(gentle.elev - 70) <= 4);
const iphone = await round({ amp: 22, ios: true, tiltDeg: 45 });
check("iPhone signs, the same hard shake gives the same pressure (±5%)", iphone && hard && Math.abs(iphone.pressure - hard.pressure) < 0.05, JSON.stringify(iphone));
check("iPhone signs, tipped 45° right also aims at 45° (±4°)", iphone && Math.abs(iphone.elev - 45) <= 4);
console.log(`\n${fails} failed`);
process.exit(fails ? 1 : 0);
