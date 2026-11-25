// Update check for the published PWA (docs/BUILD_AND_DEPLOYMENT.md "Updates"):
// serves build A, lets the service worker cache it, then switches the served
// directory to build B (a new deploy) and checks that the SAME browser profile
// ends up running build B by itself (no manual cache clearing).
// Usage: node tools/web_update_check.js <dirA> <dirB>
const http = require('http'); const fs = require('fs'); const path = require('path');
const { chromium } = require('playwright');
let dir = path.resolve(process.argv[2]); const dirB = path.resolve(process.argv[3]);
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  if (!p.startsWith(dir) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream', 'Cache-Control': 'max-age=600' });
  fs.createReadStream(p).pipe(res);
}).listen(8766);
const build = async (page) => page.evaluate(() => (typeof WORLDS_BUILD !== 'undefined' ? WORLDS_BUILD : '?'));
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const ctx = await browser.newContext({ viewport: { width: 800, height: 450 } });
  const page = await ctx.newPage();
  await page.goto('http://localhost:8766/index.html');
  await page.waitForTimeout(20000);                    // engine + pck cached by the service worker
  const a = await build(page);
  const sw = await page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).length);
  const caches1 = await page.evaluate(async () => caches.keys());
  console.log('build A running:', a, 'service workers:', sw, 'caches:', caches1);
  dir = dirB;                                          // "deploy" build B
  await page.goto('http://localhost:8766/index.html'); // user opens the app again
  await page.waitForTimeout(25000);
  const b1 = await build(page);
  const caches2 = await page.evaluate(async () => caches.keys());
  const label = await page.evaluate(() => (document.getElementById('worlds-version') || {}).textContent || '');
  console.log('after deploy, first open:', b1, 'caches:', caches2, 'label:', label);
  const resp = await page.goto('http://localhost:8766/index.html'); // and once more
  console.log('second nav status', resp && resp.status(), resp && resp.fromServiceWorker());
  await page.waitForTimeout(15000);
  const regs = await page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).map((r) => ({ a: r.active && r.active.scriptURL, s: r.active && r.active.state, w: !!r.waiting, i: !!r.installing })));
  console.log('registrations:', JSON.stringify(regs));
  const upd = await page.evaluate(async () => { try { const r = await navigator.serviceWorker.getRegistration(); await r.update(); return 'updated ' + !!r.installing + ' ' + !!r.waiting; } catch (e) { return String(e); } });
  console.log('manual update:', upd);
  await page.waitForTimeout(8000);
  console.log('caches after manual update:', await page.evaluate(async () => caches.keys()));
  console.log('probe:', await page.evaluate(async () => { const t = await (await fetch('index.html')).text(); return (t.match(/var WORLDS_BUILD='[^']*'/) || ['none'])[0] + ' ctl=' + !!navigator.serviceWorker.controller; }));
  const b2 = await build(page);
  console.log('html has build var:', await page.evaluate(() => document.documentElement.innerHTML.includes('WORLDS_BUILD')), 'url', page.url());
  const caches3 = await page.evaluate(async () => caches.keys());
  const ctl = await page.evaluate(() => !!navigator.serviceWorker.controller);
  console.log('second open:', b2, 'caches:', caches3, 'controlled:', ctl);
  const expect = JSON.parse(fs.readFileSync(path.join(dirB, 'version.json'))).build;
  const ok = b1 === expect && b2 === expect && caches3.length === 1 && caches3[0].endsWith(expect);
  console.log(ok ? 'OK' : 'STALE', 'expected', expect);
  await browser.close(); server.close();
})();
