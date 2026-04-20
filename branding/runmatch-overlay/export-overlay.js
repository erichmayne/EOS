const puppeteer = require('puppeteer');
const path = require('path');

(async () => {
  const browser = await puppeteer.launch({ headless: true });
  const page = await browser.newPage();
  await page.setViewport({ width: 800, height: 1000, deviceScaleFactor: 2 });

  const htmlPath = path.join(__dirname, 'overlay.html');
  await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle0', timeout: 15000 });
  await new Promise(r => setTimeout(r, 1500));

  await page.screenshot({
    path: path.join(__dirname, 'runmatch-overlay.png'),
    type: 'png',
    omitBackground: true
  });

  console.log('Exported: runmatch-overlay.png (transparent)');
  await browser.close();
})();
