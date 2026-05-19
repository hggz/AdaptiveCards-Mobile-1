# `examples/embed-web-vanilla/`

wasm-port: vanilla-JS host integration example. Analogue of
`examples/embed-windows/` on the windows-port branch.

Demonstrates that **no Swift is required on the host side** — a static
HTML page + ESM bundle instantiates `AdaptiveCardsWasmCABI.wasm`, calls
`ac_host_render_json(cardJSON)`, and walks the returned
`RenderingNode` IR JSON into the browser DOM with a hand-written
~300-line walker that mirrors the W2-W7 `DOMRenderer.swift` switch.

## Layout

```
examples/embed-web-vanilla/
├── README.md                  this file
├── package.json               Vite + Playwright dev deps (uncommitted
│                              lockfile until W12; run `npm install`
│                              once locally to generate one)
├── playwright.config.js       Chromium-headless, single project
├── index.html                 host page with mount + card picker
├── src/
│   ├── main.js                wasm load + UI wiring
│   ├── wasi.js                tiny browser WASI shim (uses
│                              @bjorn3/browser_wasi_shim)
│   └── walker.js              IR JSON -> DOM walker
├── tests/
│   └── dom-snapshot.spec.js   Playwright DOM-snapshot gate per card
├── baselines/                 committed DOM snapshots per reference
│                              card (populated by the first local
│                              run; intentionally empty for the W10
│                              landing commit so we don't ship a
│                              baseline captured on a single machine)
└── public/
    ├── ac.wasm                copied at build time from
    │                          ../../ios/.build/wasm32-unknown-wasip1/
    │                                       release/AdaptiveCardsWasmCABI.wasm
    └── cards/                 copied at build time from
                               ../../shared/test-cards/
```

## One-time setup

```bash
# 1. Build the WASM module under release for size + speed.
cd ../../ios
. ~/.local/share/swiftly/env.sh
swift build -c release \
    --swift-sdk swift-6.3.2-RELEASE_wasm \
    --product AdaptiveCardsWasmCABI

# 2. Copy artifacts into the example's public/ tree.
cd ../examples/embed-web-vanilla
mkdir -p public/cards
cp ../../ios/.build/wasm32-unknown-wasip1/release/AdaptiveCardsWasmCABI.wasm \
   public/ac.wasm
cp ../../shared/test-cards/*.json public/cards/

# 3. Install JS dev deps.
npm install
```

## Local dev loop

```bash
npm run dev      # vite dev server with HMR; serves on :5173
npm run build    # static build to dist/
npm run test     # playwright DOM-snapshot gate
```

## How the integration works

1. `src/main.js` fetches `public/ac.wasm` and instantiates it via
   `WebAssembly.instantiateStreaming(...)`, passing a WASI shim from
   `@bjorn3/browser_wasi_shim` as the `wasi_snapshot_preview1` import.
2. The WASM module's `_start` runs once on instantiation; it only
   touches the `ac_version` static so `--gc-sections` doesn't strip
   it. No further main-loop is needed — the module is "reactor"-style.
3. To render a card:
   - JS allocates room for the card JSON via `instance.exports.ac_alloc`.
   - JS writes the UTF-8 bytes (plus a NUL terminator) into the
     module's linear memory.
   - JS calls `instance.exports.ac_host_render_json(ptr)`.
   - The returned pointer points at a NUL-terminated UTF-8
     `RenderingNode` IR JSON string. JS reads it via a `TextDecoder`
     and immediately calls `ac_free(ptr)` to release.
4. `src/walker.js` walks the IR JSON and emits DOM elements. The CSS
   classes + `data-ac-*` attributes are byte-identical to the ones
   `AdaptiveCardsWebUI.DOMRenderer` emits — same `ac-text`,
   `data-ac-node="text"`, etc. — so a single stylesheet can serve
   both this vanilla path and a JavaScriptKit-driven path.

## Why a separate JS walker?

The walker reimplements what `AdaptiveCardsWebUI.DOMRenderer` does on
the Swift side. Reusing the Swift walker would require linking
JavaScriptKit into the WASM module, which:

* doubles the artifact size,
* adds a `bjs.*` JS-side bridge to maintain, and
* couples the host's HTML/JS layout to Swift's interop conventions.

The "no Swift on the host side" guarantee from the windows-port C
example only stays believable if vanilla JS hosts can drive the
renderer with `WebAssembly.instantiateStreaming` and a hand-rolled
walker.

## Playwright DOM-snapshot gate

`tests/dom-snapshot.spec.js` loads the page, picks each reference card
in turn, waits for `#ac-card-mount` to populate, captures the
serialized `outerHTML` of the mount tree, and diffs against the
committed `baselines/<card>.html` file. Baseline drift fails the
test — same posture as windows-port's pixel-diff gate.

First-time capture:

```bash
npm run test -- --update-snapshots
git status   # baselines/<card>.html show as new files
git add baselines/
```

After the initial capture commit, any unintentional drift surfaces as
a test failure with a `actual vs expected` diff.

## Status (W10 landing commit)

- HTML + JS + walker checked in.
- `baselines/` deliberately empty: the first capture happens on the
  user's workstation so the baselines reflect the OS-canonical
  rendering, not whatever runner the agent had access to. The
  windows-port playbook explicitly warns against this trap
  (see windows-port-handoff "baseline-drift handling").
- No GitHub Actions workflow checked in — we want this gate to run
  locally only until W13's PR open lands. Once it lands, a sibling
  `wasm-port-ci.yml` can be added modelled on
  `.github/workflows/windows-port-ci.yml`.
