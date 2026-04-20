const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

const WIDTH = 1260;
const HEIGHT = 2736;
const SLIDES = 5;

(async () => {
  const browser = await puppeteer.launch({ headless: true });
  const page = await browser.newPage();
  await page.setViewport({ width: WIDTH, height: HEIGHT * (SLIDES + 1), deviceScaleFactor: 1 });

  const htmlPath = path.join(__dirname, 'previews.html');
  await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle0', timeout: 20000 });
  await new Promise(r => setTimeout(r, 2000));

  const outDir = path.join(__dirname, 'export');
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir);

  for (let i = 1; i <= SLIDES; i++) {
    const el = await page.$(`#slide-${i}`);
    const outPath = path.join(outDir, `preview-${i}.png`);
    await el.screenshot({ path: outPath, type: 'png' });
    console.log(`Exported: preview-${i}.png`);
  }

  await browser.close();
  console.log(`\nAll ${SLIDES} previews exported to ./export/`);
})();
