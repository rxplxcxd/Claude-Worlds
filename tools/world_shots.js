// Screenshots of the world (passes the character editor with "Fertig").
// Usage: node tools/world_shots.js <build_dir> <out_dir> [query...]
const http = require('http'); const fs = require('fs'); const path = require('path');
const { chromium } = require('playwright');
const dir = path.resolve(process.argv[2]); const out = path.resolve(process.argv[3]);
const queries = process.argv.slice(4).length ? process.argv.slice(4) : [''];
fs.mkdirSync(out, { recursive: true });
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm' };
const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  if (!p.startsWith(dir) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(res);
}).listen(8768);
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 }, timezoneId: 'Europe/Berlin' });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error' || /SCRIPT ERROR/.test(m.text())) errors.push(m.text()); });
  await page.goto('http://localhost:8768/index.html');
  await page.waitForTimeout(16000);
  await page.mouse.click(1159, 654); // "Fertig" in the character editor
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `${out}/after-fertig.png` });
  for (const [i, q] of queries.entries()) {
    if (i > 0 || q) { await page.goto('http://localhost:8768/index.html' + q); await page.waitForTimeout(14000); }
    await page.screenshot({ path: `${out}/world-${i}.png` });
  }
  console.log('errors:', errors.length ? errors.slice(0, 6) : 'none');
  await browser.close(); server.close();
})();
