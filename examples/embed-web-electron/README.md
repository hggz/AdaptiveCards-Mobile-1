# `examples/embed-web-electron/`

wasm-port: Electron desktop host. Same renderer + IR walker as the
browser-only examples; the new piece is an Electron `main` process
that opens a `BrowserWindow` pointed at `index.html`. Useful when
you want to ship Adaptive Cards in a desktop app shell rather than
a browser tab.

## Pattern at a glance

* `main.cjs` (Electron main process) creates a single
  `BrowserWindow` with default-on `contextIsolation` + `sandbox`
  and loads `index.html` via `file://`.
* `index.html` is structurally identical to the snippet example.
  Electron's renderer process treats `file://` as a same-origin web
  context, so the renderer's `fetch("./ac.wasm")` + dynamic ES
  imports work without preload bridge plumbing.
* `ac-embed.js` is shared with `embed-web-snippet/` and
  `embed-web-htmx/`.

## Layout

```
examples/embed-web-electron/
├── README.md            this file
├── package.json         Electron dev dep + `npm start` script
├── main.cjs             Electron main process
├── index.html           renderer-process host page
├── ac-embed.js          shared with snippet / htmx samples
├── ac-host.css          shared with snippet / htmx samples
├── .gitignore           node_modules / ac.wasm / cards/
└── (runtime)
    ├── ac.wasm          built locally per the setup steps below
    └── cards/           copied from ../../shared/test-cards/
```

## Setup (one-time)

```bash
# 1. Build the WASM module from the repo root.
cd ../../ios
. ~/.local/share/swiftly/env.sh
swift build -c release \
    --swift-sdk swift-6.3.2-RELEASE_wasm \
    --product AdaptiveCardsWasmCABI

# 2. Copy the wasm next to ac-embed.js.
cd ../examples/embed-web-electron
cp ../../ios/.build/wasm32-unknown-wasip1/release/AdaptiveCardsWasmCABI.wasm \
   ./ac.wasm

# 3. Reference cards.
mkdir -p cards
cp ../../shared/test-cards/*.json cards/

# 4. Install Electron.
npm install
```

## Run

```bash
npm start
```

A native window opens with the same card picker + mount UI as the
browser-only examples.

## Going hermetic (no esm.sh fetch)

`ac-embed.js` imports the WASI shim from
`https://esm.sh/@bjorn3/browser_wasi_shim@0.3.0` so the example
keeps working without an `npm install` of the shim itself. For an
offline Electron build:

1. `npm install @bjorn3/browser_wasi_shim`
2. Copy `node_modules/@bjorn3/browser_wasi_shim/dist/index.js` to
   `./browser_wasi_shim.js` (or use Electron's `app.getAppPath()`
   resolution).
3. In `ac-embed.js`, replace the `https://esm.sh/...` import URL
   with `./browser_wasi_shim.js`.
4. Tighten the `Content-Security-Policy` meta in `index.html` to
   drop the `https://esm.sh` allowance.

## Packaging into a distributable

Beyond the scope of this example. Standard Electron packaging
toolchains apply unchanged:

* `electron-builder` or `electron-forge` for cross-platform
  installers.
* `asar` for the renderer assets (the `ac.wasm` is fine inside
  asar; the wasm streaming instantiate works against `file://`).
* For code-signing + auto-update, see the Electron docs.

The renderer side has zero Electron-specific code — every line in
`index.html` and `ac-embed.js` runs unmodified in a regular browser
too. This dir is the smallest possible Electron skeleton around the
same drop-in renderer the snippet example ships.

## Status (chore landing commit)

- `main.cjs`, `index.html`, `ac-embed.js`, `ac-host.css`,
  `package.json` checked in.
- `node_modules/`, `ac.wasm`, and `cards/` are `.gitignore`d.
- No build step; `npm install` only fetches Electron + its
  transitive deps.
