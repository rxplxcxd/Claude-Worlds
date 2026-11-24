// Local smoke test of the web export: serves build/web, opens it in Chromium
// (desktop + iPhone emulation), takes screenshots and reports console errors.
// Usage: node tools/serve_and_shoot.js <build_dir> <out_dir>
const http = require('http'); const fs = require('fs'); const path = require('path');
const { chromium, devices } = require('playwright');
const dir = path.resolve(process.argv[2] || 'build/web'); const out = path.resolve(process.argv[3] || 'build/shots');
fs.mkdirSync(out, { recursive: true });
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  if (!p.startsWith(dir) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(res);
}).listen(8765);
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const runs = [
    { name: 'desktop', ctx: { viewport: { width: 1280, height: 720 } } },
    { name: 'iphone-landscape', ctx: { ...devices['iPhone 14 landscape'] } },
    { name: 'iphone-portrait', ctx: { ...devices['iPhone 14'] } },
  ];
  for (const r of runs) {
    const ctx = await browser.newContext(r.ctx); const page = await ctx.newPage(); const errors = [];
    page.on('console', m => { if (m.type() === 'error' || /ERROR|SCRIPT ERROR/.test(m.text())) errors.push(m.text()); });
    page.on('pageerror', e => errors.push(String(e)));
    await page.goto('http://localhost:8765/index.html');
    await page.waitForTimeout(15000);
    await page.screenshot({ path: path.join(out, `${r.name}.png`) });
    if (r.name === 'iphone-portrait') {
      // Tap the notice board area is unknown in screen space; tap world centre-ish and the menu.
      await page.touchscreen.tap(r.ctx.viewport.width * 0.5, r.ctx.viewport.height * 0.62);
      await page.waitForTimeout(2500);
      await page.screenshot({ path: path.join(out, `${r.name}-after-tap.png`) });
    }
    console.log(r.name, 'errors:', errors.length ? errors.slice(0, 5) : 'none');
    await ctx.close();
  }
  await browser.close(); server.close();
})();
