# `examples/embed-web-snippet/`

wasm-port: **drop-in** Adaptive Cards renderer. No npm install, no
bundler, no build step. Four files are everything you need:

```
index.html        host page (your own HTML can replace this)
ac-embed.js       ES module: WASI shim import + wasm loader + IR walker
ac-host.css       baseline stylesheet for the ac-* classes
ac.wasm           the AdaptiveCardsWasmCABI module (built locally)
```

The integration pattern is two lines of HTML + ~5 lines of JS:

```html
<link rel="stylesheet" href="./ac-host.css">
<div id="my-card"></div>

<script type="module">
  import { loadAdaptiveCards } from "./ac-embed.js";
  const ac = await loadAdaptiveCards("./ac.wasm");
  const cardJSON = await (await fetch("./cards/simple-text.json")).text();
  ac.render(cardJSON, document.getElementById("my-card"), {
    onAction: (action) => console.log("ac:action", action),
  });
</script>
```

The walker emits the same `ac-*` CSS classes + `data-ac-node`
attributes as `examples/embed-web-vanilla/src/walker.js` and the
Swift `DOMRenderer.swift` — so a single stylesheet serves every host.

## How it differs from `embed-web-vanilla`

The `embed-web-vanilla/` directory ships a full Vite + Playwright
project: dev server, hot reload, DOM-snapshot gate, npm dependencies.
This `embed-web-snippet/` directory ships **just the files you need
to drop into any existing static-asset directory**. There is no
build step. You serve these files via whatever HTTP server your app
already uses.

`ac-embed.js` pulls `@bjorn3/browser_wasi_shim` from `esm.sh` so the
host never needs an npm install. If you'd rather pin the WASI shim
into your own asset directory, replace the
`https://esm.sh/@bjorn3/browser_wasi_shim@0.3.0` import URL with a
local path.

## Setup (one-time)

```bash
# 1. Build the WASM module from the repo root.
cd ../../ios
. ~/.local/share/swiftly/env.sh
swift build -c release \
    --swift-sdk swift-6.3.2-RELEASE_wasm \
    --product AdaptiveCardsWasmCABI

# 2. Copy the wasm next to ac-embed.js.
cd ../examples/embed-web-snippet
cp ../../ios/.build/wasm32-unknown-wasip1/release/AdaptiveCardsWasmCABI.wasm \
   ./ac.wasm

# 3. Copy the reference cards (your app supplies its own in
#    production; the cards/ directory is just for the live preview).
mkdir -p cards
cp ../../shared/test-cards/*.json cards/
```

## Serving

Any static HTTP server works. Examples:

```bash
# Python
python3 -m http.server 8080
# Node
npx http-server -p 8080
# Vite, if you have it
npx vite --port 8080
```

Then open <http://localhost:8080/>. WASM streaming instantiation
needs the server to send `Content-Type: application/wasm` — most
modern servers (including the three above) do so automatically.

## Production deployment

Drop `index.html`, `ac-embed.js`, `ac-host.css`, and `ac.wasm` into
your existing static asset directory. They have zero compile-time
dependencies on your app's framework — they will sit happily
alongside React / Vue / Svelte / vanilla static pages / etc. The
only runtime requirement is a modern browser (Chrome ≥ 100,
Firefox ≥ 100, Safari ≥ 16) for streaming wasm + ES modules.

## Status (chore landing commit)

- All four files checked in.
- `cards/` directory is `.gitignored` (mirrors the reference cards
  under `shared/test-cards/` at copy time).
- `ac.wasm` is `.gitignored` (size + binary; built locally per the
  setup instructions).
