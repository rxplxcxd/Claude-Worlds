// Living Assets: measures the TEST GALLERY (?gallery=living) once per quality
// profile with PerfMonitor's 20-s measurement and saves a screenshot per
// profile. Reports carry context "testgalerie" – they must not be compared
// with measurements of the real game (context "spiel"), because the gallery
// loads many states at once.
// Usage: node tools/gallery_measure.js <build_dir> <out_dir> [desktop|iphone]
// NOTE: headless Chromium = SwiftShader (software GL): absolute FPS are not
// representative of an iPhone GPU; draw calls, objects and memory are.
const http = require('http'); const fs = require('fs'); const path = require('path');
const { chromium, devices } = require('playwright');
const dir = path.resolve(process.argv[2]); const out = path.resolve(process.argv[3]);
const device = process.argv[4] || 'desktop';
fs.mkdirSync(out, { recursive: true });
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm' };
const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  if (!p.startsWith(dir) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' }); fs.createReadStream(p).pipe(res);
}).listen(8776);
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const opts = device === 'iphone' ? { ...devices['iPhone 15 Pro Max'] } : { viewport: { width: 1600, height: 900 } };
  const all = {}; const errors = [];
  for (const profile of ['ultra', 'hoch', 'leistung']) {
    const ctx = await browser.newContext({ ...opts, timezoneId: 'Europe/Berlin' });
    const page = await ctx.newPage();
    const reports = [];
    page.on('console', m => { const t = m.text(); if (t.startsWith('PERF_REPORT ')) reports.push(JSON.parse(t.slice(12))); if (m.type() === 'error') errors.push(profile + ': ' + t); });
    await page.goto(`http://localhost:8776/index.html?gallery=living&profile=${profile}&perf=1&perfauto=4`);
    await page.waitForTimeout(40000);
    await page.screenshot({ path: `${out}/${device}-gallery-${profile}.png` });
    all[profile] = reports;
    await ctx.close();
  }
  fs.writeFileSync(`${out}/${device}-gallery-reports.json`, JSON.stringify(all, null, 1));
  for (const [p, r] of Object.entries(all)) {
    const x = r[r.length - 1] || {};
    console.log(p, JSON.stringify({ context: x.context, view: x.view, draw_calls_avg: x.draw_calls_avg, objects: (x.view_details || {}).visible_objects, texture_mem_mb: x.texture_mem_mb, video_mem_mb: x.video_mem_mb, fps_avg: x.fps_avg }));
  }
  console.log('errors:', errors.length ? errors.slice(0, 8) : 'none');
  await browser.close(); server.close();
})();
