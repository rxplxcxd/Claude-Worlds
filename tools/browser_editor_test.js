// Browser flow test: character editor -> world -> reload keeps the character.
// Usage: node tools/browser_editor_test.js <build_dir> <out_dir>
// Coordinates are page pixels of a 1280x720 viewport.
const http = require('http'); const fs = require('fs'); const path = require('path');
const { chromium } = require('playwright');
const dir = path.resolve(process.argv[2] || 'build/web'); const out = path.resolve(process.argv[3] || 'build/shots');
fs.mkdirSync(out, { recursive: true });
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm' };
const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  if (!p.startsWith(dir) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(res);
}).listen(8767);
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error' || /SCRIPT ERROR/.test(m.text())) errors.push(m.text()); });
  await page.goto('http://localhost:8767/index.html');
  await page.waitForTimeout(14000);
  await page.screenshot({ path: `${out}/1-editor.png` });
  // page coordinates (1280x720)
  const tap = async (x, y, wait = 600) => { await page.mouse.click(x, y); await page.waitForTimeout(wait); };
  await tap(740, 66);              // tab "Haare"
  await tap(927, 270);             // card "Lang"
  await page.screenshot({ path: `${out}/2-hair-long.png` });
  await tap(632, 654);             // "Zufall"
  await page.screenshot({ path: `${out}/3-random.png` });
  await tap(780, 654);             // "Rückgängig" -> back to long hair
  await page.screenshot({ path: `${out}/4-undo.png` });
  await tap(208, 671);             // "Gehen"
  await tap(510, 427, 900);        // rotate right once
  await page.screenshot({ path: `${out}/5-walk-right1.png` });
  await tap(510, 427, 900);        // rotate right twice
  await page.screenshot({ path: `${out}/6-walk-right2.png` });
  await tap(1159, 654, 3000);      // "Fertig"
  await page.screenshot({ path: `${out}/7-world.png` });
  await page.waitForTimeout(1500);
  await page.reload();
  await page.waitForTimeout(13000);
  await page.screenshot({ path: `${out}/8-after-reload.png` });
  console.log('errors:', errors.length ? errors.slice(0, 6) : 'none');
  await browser.close(); server.close();
})();
