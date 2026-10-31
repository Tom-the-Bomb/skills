// usage: node ui-shots.mjs [--out dir] [--widths 320,390,768,1280] [--text 16,32] [--modes light,dark,forced,forced-dark]
//                          [--height 900] [--wait 1500] [--tiles 6] [--no-axe] <url>...
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { parseArgs } from 'node:util';

const { values: opt, positionals: urls } = parseArgs({
  allowPositionals: true,
  allowNegative: true,
  options: {
    out: { type: 'string', default: 'ui-shots' },
    widths: { type: 'string', default: '320,390,768,1280' },
    text: { type: 'string', default: '16,32' },
    modes: { type: 'string', default: 'light' },
    height: { type: 'string', default: '900' },
    wait: { type: 'string', default: '1500' },
    tiles: { type: 'string', default: '6' },
    axe: { type: 'boolean', default: true },
  },
});
if (!urls.length) {
  console.error('usage: node ui-shots.mjs [options] <url>...');
  process.exit(2);
}
const list = (s) => s.split(',').map((x) => x.trim());
const nums = (s) => list(s).map(Number);

const deps = process.env.AUDIT_DEPS ?? path.join(os.tmpdir(), 'audit-skill-deps');
const req = createRequire(path.join(deps, 'package.json'));
try {
  req.resolve('playwright-core');
  req.resolve('axe-core');
} catch {
  execFileSync('npm', ['install', '--prefix', deps, 'playwright-core', 'axe-core'], {
    stdio: ['ignore', 'ignore', 'inherit'],
  });
}
const { chromium } = req('playwright-core');
const axeSource = readFileSync(req.resolve('axe-core/axe.min.js'), 'utf8');

const browser = await chromium.launch().catch(() => chromium.launch({ channel: 'chrome' }));
const height = Number(opt.height);
const report = [];
mkdirSync(opt.out, { recursive: true });

for (const url of urls) {
  const slug = new URL(url).pathname.replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'root';
  const dir = path.join(opt.out, slug);
  mkdirSync(dir, { recursive: true });

  for (const mode of list(opt.modes)) {
    for (const width of nums(opt.widths)) {
      for (const text of nums(opt.text)) {
        const context = await browser.newContext({
          viewport: { width, height },
          colorScheme: mode.endsWith('dark') ? 'dark' : 'light',
          forcedColors: mode.startsWith('forced') ? 'active' : 'none',
          reducedMotion: 'reduce',
        });
        const page = await context.newPage();
        const cdp = await context.newCDPSession(page);
        await cdp.send('Page.enable');
        if (text !== 16)
          await cdp.send('Page.setFontSizes', {
            fontSizes: { standard: text, fixed: Math.round(text * 0.8125) },
          });
        await page.goto(url, { waitUntil: 'load' });
        await page.waitForTimeout(Number(opt.wait));
        const m = await page.evaluate(() => ({
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          pageHeight: document.documentElement.scrollHeight,
          root: getComputedStyle(document.documentElement).fontSize,
        }));
        const shots = [];
        for (let y = 0, i = 0; y < m.pageHeight && i < Number(opt.tiles); y += height, i++) {
          await page.evaluate((top) => window.scrollTo(0, top), y);
          await page.waitForTimeout(150);
          const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' });
          const file = path.join(dir, `${mode}-w${width}-t${text}-${i}.png`);
          writeFileSync(file, Buffer.from(data, 'base64'));
          shots.push(file);
        }
        report.push(
          `${url} mode=${mode} w=${width} text=${text} root=${m.root} overflow=${m.overflow}px height=${m.pageHeight} shots=${shots.join(',')}`,
        );
        await context.close();
      }
    }
  }

  if (opt.axe) {
    const context = await browser.newContext({
      viewport: { width: 1280, height },
      reducedMotion: 'reduce',
    });
    const page = await context.newPage();
    await page.goto(url, { waitUntil: 'load' });
    await page.waitForTimeout(Number(opt.wait));
    await page.addScriptTag({ content: axeSource });
    const violations = await page.evaluate(async () => {
      const r = await window['axe'].run(document, {
        runOnly: ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa', 'best-practice'],
      });
      return r.violations.map((v) => ({
        id: v.id,
        impact: v.impact,
        help: v.help,
        targets: v.nodes.map((n) => n.target.join(' ')),
      }));
    });
    writeFileSync(path.join(dir, 'axe.json'), JSON.stringify(violations, null, 2));
    for (const v of violations)
      report.push(
        `${url} axe [${v.impact}] ${v.id} x${v.targets.length}: ${v.help} -> ${v.targets.slice(0, 3).join(' | ')}`,
      );
    if (!violations.length) report.push(`${url} axe: no violations`);
    await context.close();
  }
}

await browser.close();
writeFileSync(path.join(opt.out, 'report.txt'), `${report.join('\n')}\n`);
console.log(report.join('\n'));
