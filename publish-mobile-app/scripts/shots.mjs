// scripts/shots.mjs — App Store / Google Play marketing screenshot capture.
//
// Drives the app's ?shot=1 web screenshot mode with Playwright and writes PNGs
// to store-screenshots/. The shot list is app-specific, so it is read from a
// `shots.config.json` in the project root (or SHOTS_CONFIG). If no config is
// found, a documented default set is used — see references/screenshots.md for
// the full config shape.
//
// Env overrides:
//   PLAYWRIGHT_PATH  explicit path to playwright's index.mjs (playwright often
//                    lives in the npx cache, not local node_modules).
//   PORT             port the ?shot=1 web build is served on (default 5174,
//                    or config.port).
//   SHOTS_CONFIG     path to the shots config JSON (default ./shots.config.json).

import { mkdirSync, readFileSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';

// ─────────── Load config (optional) ───────────
const CONFIG_PATH = process.env.SHOTS_CONFIG || 'shots.config.json';

// Documented default. Screens, accents, and selectors here are placeholders —
// override them in shots.config.json to match your app's ?shot=1 screens.
const DEFAULT_CONFIG = {
  port: 5174,
  // Optional per-screen CSS selector to wait for before capturing. A screen
  // with no entry here just waits for network idle + a short settle timeout.
  selectors: {},
  portrait: {
    shots: [
      { screen: 'home', theme: 'dark', accent: '#4F6D7A', name: '01-home' },
      { screen: 'detail', theme: 'dark', accent: '#4F6D7A', name: '02-detail' },
      { screen: 'summary', theme: 'light', accent: '#4F6D7A', name: '03-summary' },
    ],
    // Vary deviceScaleFactor to hit each store size at exactly 9:16 from one
    // CSS viewport.
    devices: [
      { dir: 'phone', width: 540, height: 960, deviceScaleFactor: 2 }, //                 1080x1920
      { dir: 'tablet-portrait', suffix: '-7in', width: 540, height: 960, deviceScaleFactor: 2.6667 }, // 1440x2560
      { dir: 'tablet-portrait', suffix: '-10in', width: 540, height: 960, deviceScaleFactor: 3 }, //     1620x2880
    ],
  },
  landscape: {
    // 1280x720 @ dsf 2 => 2560x1440 (exactly 16:9).
    viewport: { width: 1280, height: 720, deviceScaleFactor: 2 },
    hero: { screen: 'home', theme: 'dark', accent: '#4F6D7A', layout: 'landscape', hero: true, path: 'hero.png' },
    shots: [
      { screen: 'home', theme: 'dark', accent: '#4F6D7A', layout: 'landscape', path: 'tablet-landscape/01-home.png' },
      { screen: 'detail', theme: 'dark', accent: '#4F6D7A', layout: 'landscape', path: 'tablet-landscape/02-detail.png' },
      { screen: 'summary', theme: 'light', accent: '#4F6D7A', layout: 'landscape', path: 'tablet-landscape/03-summary.png' },
    ],
  },
};

let config = DEFAULT_CONFIG;
if (existsSync(CONFIG_PATH)) {
  try {
    config = { ...DEFAULT_CONFIG, ...JSON.parse(readFileSync(CONFIG_PATH, 'utf8')) };
    console.log(`using shot config: ${CONFIG_PATH}`);
  } catch (err) {
    console.error(`failed to parse ${CONFIG_PATH}: ${err.message}`);
    process.exit(1);
  }
} else {
  console.log(`no ${CONFIG_PATH} found — using built-in default shot set`);
}

// ─────────── Resolve Playwright ───────────
// playwright often lives in the npx cache (not local node_modules); resolve it
// explicitly when PLAYWRIGHT_PATH is set, otherwise import the package normally.
const pwPath = process.env.PLAYWRIGHT_PATH || 'playwright';
const { chromium } = await import(pwPath);

const PORT = process.env.PORT || String(config.port || 5174);
const BASE = `http://localhost:${PORT}`;
const OUT = new URL('../store-screenshots/', import.meta.url).pathname;

const selectors = config.selectors || {};
const selFor = (screen) => selectors[screen];

const url = (s) =>
  `${BASE}/?shot=1&screen=${s.screen}&theme=${s.theme}&accent=${encodeURIComponent(s.accent)}` +
  (s.layout ? `&layout=${s.layout}` : '') +
  (s.hero ? `&hero=1` : '');

const settle = async (page, screen) => {
  await page.evaluate(() => document.fonts.ready);
  const sel = selFor(screen);
  if (sel) {
    await page.waitForSelector(sel, { state: 'visible' });
  }
  await page.waitForTimeout(500);
};

const portrait = config.portrait || { shots: [], devices: [] };
const landscape = config.landscape || null;

mkdirSync(OUT, { recursive: true });
for (const dev of portrait.devices || []) {
  mkdirSync(`${OUT}${dev.dir}`, { recursive: true });
}
if (landscape) {
  mkdirSync(`${OUT}tablet-landscape`, { recursive: true });
}

const browser = await chromium.launch();
try {
  // Portrait store sets.
  for (const dev of portrait.devices || []) {
    const context = await browser.newContext({
      viewport: { width: dev.width, height: dev.height },
      deviceScaleFactor: dev.deviceScaleFactor,
      reducedMotion: 'reduce',
    });
    for (const s of portrait.shots || []) {
      const page = await context.newPage();
      await page.goto(url(s), { waitUntil: 'networkidle' });
      await settle(page, s.screen);
      const outPath = `${OUT}${dev.dir}/${s.name}${dev.suffix || ''}.png`;
      await page.screenshot({
        path: outPath,
        clip: { x: 0, y: 0, width: dev.width, height: dev.height },
      });
      console.log(`wrote ${outPath}`);
      await page.close();
    }
    await context.close();
  }

  // Landscape marketing set (hero + tablet-landscape).
  if (landscape) {
    const vp = landscape.viewport;
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: vp.deviceScaleFactor,
      reducedMotion: 'reduce',
    });
    const landscapeShots = [...(landscape.hero ? [landscape.hero] : []), ...(landscape.shots || [])];
    for (const s of landscapeShots) {
      const page = await context.newPage();
      await page.goto(url(s), { waitUntil: 'networkidle' });
      await settle(page, s.screen);
      const outPath = `${OUT}${s.path}`;
      mkdirSync(dirname(outPath), { recursive: true });
      await page.screenshot({
        path: outPath,
        clip: { x: 0, y: 0, width: vp.width, height: vp.height },
      });
      console.log(`wrote ${outPath}`);
      await page.close();
    }
    await context.close();
  }
} finally {
  await browser.close();
}
