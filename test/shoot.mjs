#!/usr/bin/env node
// Full-page screenshots at an exact viewport width via the Chrome DevTools Protocol.
//   node test/shoot.mjs <width> <out.png> <url> [<out.png> <url> ...]
// Resolves *.popug.cloud to 127.0.0.1 and ignores the dev certificate.
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [width, ...rest] = process.argv.slice(2);
const chrome = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9333;
const proc = spawn(chrome, [
  '--headless=new', `--remote-debugging-port=${port}`, '--ignore-certificate-errors', '--hide-scrollbars',
  '--host-resolver-rules=MAP *.popug.cloud 127.0.0.1, MAP popug.cloud 127.0.0.1', `--user-data-dir=${mkdtempSync(join(tmpdir(), 'shoot-'))}`, 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page'); } catch {}
  if (!target) await sleep(200);
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0; const pending = new Map();
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } };
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });

await send('Page.enable');
for (let i = 0; i < rest.length; i += 2) {
  const [out, url] = [rest[i], rest[i + 1]];
  await send('Emulation.setDeviceMetricsOverride', { width: +width, height: 900, deviceScaleFactor: 1, mobile: +width < 700 });
  await send('Page.navigate', { url });
  await sleep(900);
  const m = (await send('Page.getLayoutMetrics')).result;
  const h = Math.ceil(m.cssContentSize.height);
  const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { x: 0, y: 0, width: +width, height: h, scale: 1 } });
  writeFileSync(out, Buffer.from(shot.result.data, 'base64'));
  console.log(`${out}  ${width}x${h}  scrollWidth-ok=${m.cssContentSize.width <= +width + 1}`);
}
ws.close(); proc.kill();
