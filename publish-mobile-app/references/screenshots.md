# Store screenshots (`shots.mjs`)

`scripts/shots.mjs` captures App Store / Google Play marketing screenshots with
Playwright by driving a **web screenshot mode** in your app. The runner is fully
parameterized; the shot mode itself is app-specific and you must implement it.

## The `?shot=1` web pattern

`shots.mjs` navigates to your locally-served web build with a query string and
screenshots the viewport. Your app must implement a "shot mode" that reads these
query params and renders a single, deterministic, chrome-free screen:

```
http://localhost:<PORT>/?shot=1&screen=<name>&theme=<theme>&accent=<hex>&layout=<layout>&hero=1
```

- `shot=1` — enter shot mode: hide dev chrome, disable animations/looping,
  freeze any time-based UI so captures are deterministic.
- `screen=<name>` — which screen to render (e.g. `home`, `detail`, `summary`).
  The names are entirely app-defined; they just have to match your config.
- `theme=<light|dark>` — color scheme.
- `accent=<hex>` — accent color (URL-encoded `#RRGGBB`).
- `layout=<layout>` — optional layout hint (e.g. `landscape`) for wide captures.
- `hero=1` — optional flag for a hero/marketing composition.

The runner also waits for `document.fonts.ready`, optionally waits for a
per-screen CSS selector (see `selectors` below) to confirm the screen actually
rendered, then settles 500ms before capturing. It requests
`reducedMotion: 'reduce'` on the browser context.

Because these params and the shot-mode implementation live in the app, this is
the one part of the skill that cannot be fully generalized — the runner is
generic, but you provide the shot mode and the `shots.config.json` describing it.

## Running it

Serve your web build in `?shot=1`-capable mode (e.g. `vite`) on a known port,
then from the **project root**:

```bash
npm run shots
# or directly:
PORT=5174 node scripts/shots.mjs
```

Output goes to `store-screenshots/` (`phone/`, `tablet-portrait/`,
`tablet-landscape/`, plus `hero.png`).

### Environment overrides

- `PORT` — port the web build is served on. Default `5174` (or `config.port`).
- `PLAYWRIGHT_PATH` — explicit path to Playwright's `index.mjs`. Playwright is
  often only in the npx cache rather than local `node_modules`, e.g.
  `~/.npm/_npx/<hash>/node_modules/playwright/index.mjs`. Without this the runner
  imports the `playwright` package from `node_modules`.
- `SHOTS_CONFIG` — path to the config JSON. Default `./shots.config.json`.

## `shots.config.json`

If a `shots.config.json` exists in the project root it drives the run; otherwise
a built-in default set is used (with placeholder screens/accents — override it).
Shape:

```json
{
  "port": 5174,
  "selectors": {
    "home": ".home-root",
    "detail": ".detail-card",
    "summary": ".summary-view"
  },
  "portrait": {
    "shots": [
      { "screen": "home",    "theme": "dark",  "accent": "#4F6D7A", "name": "01-home" },
      { "screen": "detail",  "theme": "dark",  "accent": "#4F6D7A", "name": "02-detail" },
      { "screen": "summary", "theme": "light", "accent": "#4F6D7A", "name": "03-summary" }
    ],
    "devices": [
      { "dir": "phone",           "width": 540, "height": 960, "deviceScaleFactor": 2 },
      { "dir": "tablet-portrait", "suffix": "-7in",  "width": 540, "height": 960, "deviceScaleFactor": 2.6667 },
      { "dir": "tablet-portrait", "suffix": "-10in", "width": 540, "height": 960, "deviceScaleFactor": 3 }
    ]
  },
  "landscape": {
    "viewport": { "width": 1280, "height": 720, "deviceScaleFactor": 2 },
    "hero":  { "screen": "home", "theme": "dark", "accent": "#4F6D7A", "layout": "landscape", "hero": true, "path": "hero.png" },
    "shots": [
      { "screen": "home",    "theme": "dark",  "accent": "#4F6D7A", "layout": "landscape", "path": "tablet-landscape/01-home.png" },
      { "screen": "detail",  "theme": "dark",  "accent": "#4F6D7A", "layout": "landscape", "path": "tablet-landscape/02-detail.png" },
      { "screen": "summary", "theme": "light", "accent": "#4F6D7A", "layout": "landscape", "path": "tablet-landscape/03-summary.png" }
    ]
  }
}
```

Field notes:

- `selectors` — optional. Map of `screen -> CSS selector` the runner waits for
  before capturing. A screen with no selector just waits for network idle + a
  short settle.
- `portrait.shots[].name` — output basename (a `dev.suffix` is appended per
  device, e.g. `01-home-7in.png`).
- `portrait.devices` — each renders every portrait shot into `dir/`. `suffix` is
  optional; `deviceScaleFactor` is what actually changes the exported pixel size
  from a fixed CSS viewport.
- `landscape.hero` / `landscape.shots[].path` — output path relative to
  `store-screenshots/` (subdirectories are created as needed).

## Size + aspect-ratio specs

Screenshots must hit exact aspect ratios or the stores reject them. The default
config values are chosen to land on-spec from a fixed CSS viewport by varying
`deviceScaleFactor`:

**Google Play** — accepts 16:9 or 9:16.
- Phone (portrait 9:16): 1080×1920 → CSS 540×960 @ dsf 2.
- 7" tablet (portrait 9:16): 1440×2560 → CSS 540×960 @ dsf 2.6667.
- 10" tablet (portrait 9:16): 1620×2880 → CSS 540×960 @ dsf 3.
- Tablet landscape (16:9): 2560×1440 → CSS 1280×720 @ dsf 2.
- Feature graphic / hero: 16:9 landscape.

**Apple App Store** — uses fixed per-device pixel dimensions (e.g. 6.7"/6.9"
iPhone and 12.9"/13" iPad portrait/landscape sizes). Confirm current required
sizes in App Store Connect and add matching `portrait.devices` entries; the
9:16 phone portrait output doubles for the tall iPhone displays, and the 16:9
landscape output covers iPad landscape.

Always verify final pixel dimensions before uploading; Apple in particular
rejects off-by-one sizes.
