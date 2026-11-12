// Isolated headless rendering of the generated layout fixture; never attaches to a user's browser.
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const {pathToFileURL} = require('node:url');
const path = require('node:path');

(async () => {
  const [input, output, width = '1280', height = '760'] = process.argv.slice(2);
  if (!input || !output) throw Error('Usage: node capture.cjs <local.html> <out.png> [width] [height]');
  const url = pathToFileURL(path.resolve(input));
  if (path.extname(url.pathname).toLowerCase() !== '.html') throw Error('Expected a local HTML fixture.');
  const browser = await chromium.launch({channel: 'msedge', headless: true});
  try {
    const page = await browser.newPage({viewport: {width: Number(width), height: Number(height)}});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(url.href, {waitUntil: 'load'});
    await page.screenshot({path: path.resolve(output)});
    if (errors.length) throw Error(errors.join('\n'));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
