// Renders icon.svg into the PNG sizes needed by the PWA / iOS home screen.
// Usage: node tools/render_icons.js  (uses the Playwright Chromium)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const root = path.resolve(__dirname, '..');
  const svg = fs.readFileSync(path.join(root, 'icon.svg'), 'utf8');
  const browser = await chromium.launch();
  for (const size of [144, 180, 192, 512]) {
    const page = await browser.newPage({ viewport: { width: size, height: size } });
    await page.setContent(`<html><body style="margin:0;background:#121720">${svg.replace('width="512" height="512"', `width="${size}" height="${size}"`)}</body></html>`);
    await page.screenshot({ path: path.join(root, 'web', 'icons', `icon-${size}.png`) });
    await page.close();
  }
  await browser.close();
})();
