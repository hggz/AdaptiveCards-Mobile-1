# `examples/embed-web-react/`

wasm-port: TypeScript + React host integration example. Analogue of
`examples/embed-windows-csharp/` on the windows-port branch — same
"non-Swift host language calls into a Swift-compiled WASM module"
proof, with React on the host side instead of WPF / C#.

## Layout

```
examples/embed-web-react/
├── README.md                  this file
├── package.json               React 18 + TypeScript + Vite +
│                              Playwright dev deps
├── tsconfig.json              strict TS for the app
├── vite.config.ts             Vite + React plugin
├── playwright.config.ts       Chromium-headless gate config
├── index.html                 Vite entry HTML
├── src/
│   ├── main.tsx               renders <App /> into #root
│   ├── App.tsx                page chrome + card picker +
│   │                          <AdaptiveCard json={...} /> demo
│   ├── wasm.ts                single-instance WASM loader, exposes
│   │                          renderIR(json) -> Promise<RenderingNode>
│   ├── AdaptiveCard.tsx       React component: takes card JSON,
│   │                          renders the IR as React elements via
│   │                          the walker, plus controlled-input
│   │                          state + submit-payload merge.
│   └── walker.tsx             IR JSON -> React element walker
│                              (mirrors the W2-W7 Swift DOMRenderer
│                              and the W10 vanilla walker — same
│                              CSS classes + data-ac-* attributes).
├── tests/
│   └── snapshot.spec.ts       Playwright DOM-snapshot gate (same
│                              shape as W10).
├── baselines/                 committed React-rendered DOM snapshots
│                              (populated on first local run).
└── public/
    ├── ac.wasm                copied from
    │                          ../../ios/.build/wasm32-unknown-wasip1/
    │                                       release/AdaptiveCardsWasmCABI.wasm
    └── cards/                 copied from ../../shared/test-cards/
```

## Setup (one-time)

```bash
# 1. Build the WASM module.
cd ../../ios && . ~/.local/share/swiftly/env.sh
swift build -c release \
    --swift-sdk swift-6.3.2-RELEASE_wasm \
    --product AdaptiveCardsWasmCABI

# 2. Copy artifacts.
cd ../examples/embed-web-react
mkdir -p public/cards
cp ../../ios/.build/wasm32-unknown-wasip1/release/AdaptiveCardsWasmCABI.wasm \
   public/ac.wasm
cp ../../shared/test-cards/*.json public/cards/

# 3. Install deps.
npm install
```

## Local dev loop

```bash
npm run dev      # vite dev server on :5174
npm run build    # static build to dist/
npm run test     # playwright DOM-snapshot gate
```

## Public API

```tsx
import { AdaptiveCard } from "./AdaptiveCard";

<AdaptiveCard
  json={cardJSON}
  onAction={(action) => {
    if (action.kind === "submit") {
      fetch("/api/submit", { method: "POST", body: action.dataJSON });
    } else if (action.kind === "openUrl") {
      window.open(action.openUrl, "_blank");
    }
  }}
/>
```

The component manages:
* lazy-loading the WASM module on first render (shared singleton),
* parsing + rendering the card JSON to IR via `ac_host_render_json`,
* maintaining controlled-input state per `data-ac-input-id`,
* merging input values into the `Action.Submit.data` payload before
  invoking `onAction`.

## Status (W11 landing commit)

- Component + walker + demo app checked in.
- `baselines/` deliberately empty — same first-capture policy as W10.
- No GitHub Actions workflow checked in (local-only per the user's
  directive); a sibling `wasm-port-ci.yml` is held for W13 / a later
  phase.
- The walker matches the W2-W7 Swift renderer and the W10 vanilla
  walker on `data-ac-node` + CSS class output, so the React-rendered
  DOM baseline should match the vanilla one for the same card and
  the same IR (which it always should be — same WASM module, same
  IR JSON).
