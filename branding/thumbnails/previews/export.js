const puppeteer = require('puppeteer');
const path = require('path');

const WIDTH = 1260;
const HEIGHT = 2736;

const previews = [
  { id: 'home',      headline: 'Set it. Do it.<br>Or lose it.',       img: 'home.png',      objectiveClass: false },
  { id: 'stakes',    headline: 'Put real money<br>on the line.',      img: 'stakes.png',    objectiveClass: false },
  { id: 'objective', headline: 'Your goals.<br>Your rules.',         img: 'objective.png', objectiveClass: true  },
  { id: 'compete',   headline: 'Compete<br>and win.',                img: 'compete.png',   objectiveClass: false },
  { id: 'strava',    headline: 'Your runs, tracked<br>automatically.',img: 'strava.png',    objectiveClass: false },
  { id: 'comp',      headline: 'Challenge<br>your friends.',         img: 'comp.png',      objectiveClass: false },
  { id: 'pushups',   headline: 'AI Pushup<br>Tracking.',             img: 'pushups.png',   objectiveClass: false },
  { id: 'habits',    headline: 'Compete or build<br>better habits.',  img: 'habits.png',    objectiveClass: false },
];

function buildHTML(preview) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@700;800;900&display=swap');
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: ${WIDTH}px;
      height: ${HEIGHT}px;
      overflow: hidden;
      font-family: 'Inter', -apple-system, sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    .preview {
      width: ${WIDTH}px;
      height: ${HEIGHT}px;
      background: #ffffff;
      display: flex;
      flex-direction: column;
      align-items: center;
      overflow: hidden;
    }
    .headline {
      padding: 180px 90px 0;
      font-size: 115px;
      font-weight: 800;
      text-align: center;
      background: linear-gradient(135deg, #C49200 0%, #D9A600 30%, #F2BF1A 60%, #D9A600 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      line-height: 1.15;
      flex-shrink: 0;
    }
    .spacer {
      flex: 1;
      min-height: 50px;
      max-height: 120px;
    }
    .screen-wrapper {
      width: 1080px;
      height: 2100px;
      border-radius: 120px;
      overflow: hidden;
      position: relative;
      flex-shrink: 0;
      margin-bottom: 80px;
      box-shadow: 0 16px 60px rgba(0,0,0,0.08);
      border: 5px solid rgba(0,0,0,0.1);
    }
    .screen-wrapper img {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      width: 112%;
      height: 106%;
      object-fit: cover;
    }
    .screen-wrapper.objective-screen img {
      transform: translate(-50%, -47%);
    }
  </style>
</head>
<body>
  <div class="preview">
    <div class="headline">${preview.headline}</div>
    <div class="spacer"></div>
    <div class="screen-wrapper${preview.objectiveClass ? ' objective-screen' : ''}">
      <img src="${preview.img}">
    </div>
  </div>
</body>
</html>`;
}

(async () => {
  const browser = await puppeteer.launch({ headless: true });
  const outputDir = path.join(__dirname, 'export');
  const fs = require('fs');
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir);

  for (let i = 0; i < previews.length; i++) {
    const p = previews[i];
    const page = await browser.newPage();
    await page.setViewport({ width: WIDTH, height: HEIGHT, deviceScaleFactor: 1 });

    const htmlPath = path.join(__dirname, `_temp_${p.id}.html`);
    fs.writeFileSync(htmlPath, buildHTML(p));
    await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle0', timeout: 15000 });
    await new Promise(r => setTimeout(r, 1000));

    const outPath = path.join(outputDir, `${i + 1}-${p.id}.png`);
    await page.screenshot({ path: outPath, type: 'png' });
    await page.close();
    fs.unlinkSync(htmlPath);

    console.log(`Exported: ${outPath}`);
  }

  await browser.close();
  console.log('\nAll 8 previews exported to ./export/');
})();
