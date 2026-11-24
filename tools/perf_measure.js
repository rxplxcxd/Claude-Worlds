// Automated diagnostic measurement (Paket 2.1). Uses PerfMonitor's
// "?perf=1&perfauto=N" hook and collects its PERF_REPORT console lines.
// Usage: node tools/perf_measure.js <build_dir> <out_dir> [desktop|iphone]
// NOTE: headless Chromium renders with SwiftShader (software GL on the CPU).
// Absolute FPS/frame times are NOT representative of an iPhone GPU; draw
// calls, primitives, object counts and memory are (same engine, same scene).
const http = require('http'); const fs = require('fs'); const path = require('path');
const { chromium, devices } = require('playwright');
const dir = path.resolve(process.argv[2]); const out = path.resolve(process.argv[3]);
const profile = process.argv[4] || 'desktop';
fs.mkdirSync(out, { recursive: true });
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm' };
const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  if (!p.startsWith(dir) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(res);
}).listen(8775);
const base = 'http://localhost:8775/index.html';
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const opts = profile === 'iphone' ? { ...devices['iPhone 15 Pro Max'] } : { viewport: { width: 1280, height: 720 } };
  const ctx = await browser.newContext({ ...opts, timezoneId: 'Europe/Berlin' });
  const page = await ctx.newPage();
  const reports = []; const errors = [];
  page.on('console', m => { const t = m.text(); if (t.startsWith('PERF_REPORT ')) reports.push(JSON.parse(t.slice(12))); if (m.type() === 'error') errors.push(t); });
  const vw = opts.viewport.width, vh = opts.viewport.height;
  const at = (x, y) => [x / 1280 * vw, y / 720 * vh];
  // 1) New player: editor → start choice → globe → suggestion → found.
  // (QA hook ?qa_quickstart=1: default character + founding at the best site.)
  // 2) Settlement view: automatic 20 s measurement after 4 s.
  await page.goto(base + '?qa_quickstart=1&perf=1&perfauto=4'); await page.waitForTimeout(16000 + 26000);
  await page.screenshot({ path: `${out}/${profile}-settlement.png` });
  // 3) Globe view: open the map (desktop button position), measure.
  await page.goto(base + '?perf=1&perfauto=22'); await page.waitForTimeout(16000);
  await page.keyboard.press('m'); await page.waitForTimeout(34000);
  await page.screenshot({ path: `${out}/${profile}-globe.png` });
  fs.writeFileSync(`${out}/${profile}-reports.json`, JSON.stringify(reports, null, 1));
  console.log(JSON.stringify(reports, null, 1));
  console.log('errors:', errors.length ? errors.slice(0, 5) : 'none');
  await browser.close(); server.close();
})();
