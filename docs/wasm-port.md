# wasm-port — Swift → WebAssembly + browser DOM

Branch:  [`wasm-port`](https://github.com/hggz/AdaptiveCards-Mobile-1/tree/wasm-port)
Status:  v0.11 — every renderer-side `RenderingNode` case implemented,
         demo + CABI + vanilla-JS + React example hosts checked in,
         Playwright DOM-snapshot gate scaffolded (local-only baselines).
Reading order:
 1. This file.
 2. [`docs/wasm-port-handoff.md`](wasm-port-handoff.md) — the initial briefing.
 3. The per-phase commit log (`git log --oneline wasm-port`).

This branch is the parallel sibling of the
[`windows-port`](https://github.com/hggz/AdaptiveCards-Mobile-1/tree/windows-port)
branch. Both consume the same `RenderingNode` IR; only the View layer
differs (WinUI / swift-cross-ui there, browser DOM here).

---

## 1. TL;DR

* **The IR is the contract.** A single `RenderingNode` tree
  (`ios/Sources/AdaptiveCardsRenderingIR/`) encodes everything the
  Adaptive Cards renderer wants to draw. Both windows-port and
  wasm-port walk this same tree. The IR's wire format (JSON) is
  byte-for-byte identical between branches; the baselines
  (`Snapshots/*.rendertree.json`, `A11yBaselines/*.a11y.txt` — held on
  windows-port for now) apply unchanged here.
* **The View layer is the only thing that varies.**
  `AdaptiveCardsWebUI.DOMRenderer` (~700 lines, split across four
  files for reviewability) walks `RenderingNode` into browser DOM
  elements via JavaScriptKit.
* **Hosts choose their integration pattern.** Three example hosts
  cover the full spread:
  1. `AdaptiveCardsWebDemo` — pure Swift WASM with JavaScriptKit
     drawing into `<div id="ac-card-mount">`.
  2. `examples/embed-web-vanilla` — static HTML + ESM JS. Loads the
     `AdaptiveCardsWasmCABI.wasm`, calls C-ABI exports, walks the
     returned IR JSON with hand-written ~500 lines of JS. No Swift
     on the host side.
  3. `examples/embed-web-react` — TypeScript + React. Same WASM
     module, but the walker emits React elements instead of raw DOM,
     and inputs are controlled.

---

## 2. Architecture

```
┌────────────────────────┐   ┌────────────────────────────────┐
│ ACCore                 │──▶│ AdaptiveCardsRenderingIR       │
│  - CardParser          │   │  - RenderingNode (the IR)      │
│  - AdaptiveCard model  │   │  - Renderer(card) -> Node      │
└────────────────────────┘   │  - A11yDump (shared)           │
                             │  - SubmitPayload (shared)      │
                             │  - SampleCardLibrary           │
                             └────────────────────────────────┘
                                       │
                                       │ (RenderingNode tree)
                                       ▼
              ┌─────────────────────────────────────────────┐
              │ View layer — picks ONE of:                  │
              │                                             │
              │ (a) AdaptiveCardsWebUI.DOMRenderer          │
              │     Swift -> JavaScriptKit -> document.*    │
              │                                             │
              │ (b) AdaptiveCardsWasmCABI exports +         │
              │     vanilla JS walker (examples/embed-web-  │
              │     vanilla)                                │
              │                                             │
              │ (c) AdaptiveCardsWasmCABI exports +         │
              │     React walker (examples/embed-web-react) │
              └─────────────────────────────────────────────┘
```

### The renderer-side modules

| Target                       | Type                | What                                                                                                            |
|------------------------------|---------------------|-----------------------------------------------------------------------------------------------------------------|
| `ACCore`                     | library             | Pre-existing iOS parser; produces `AdaptiveCard` from JSON.                                                     |
| `AdaptiveCardsRenderingIR`   | library             | Cherry-pick from windows-port (`Renderer`, `RenderingNode`, `A11yDump`, `SubmitPayload`, `SampleCardLibrary`).  |
| `AdaptiveCardsWebUI`         | library             | JavaScriptKit-backed DOM walker. 4 files: `DOMRenderer.swift`, `+Display.swift`, `+Composite.swift`, `+Media.swift`. |
| `AdaptiveCardsWebDemo`       | executable (.wasm)  | W8 demo: parse + render + JavaScriptKit mount.                                                                  |
| `AdaptiveCardsWasmCABI`      | executable (.wasm)  | W9 C-ABI module: `ac_alloc` / `ac_free` / `ac_host_render_json` / `ac_last_error` / `ac_version`.               |

### What lives in `examples/`

| Directory                       | Purpose                                                              |
|---------------------------------|----------------------------------------------------------------------|
| `examples/embed-web-vanilla/`   | Static HTML + Vite + vanilla JS host (W10). DOM-snapshot gate.       |
| `examples/embed-web-react/`     | Vite + React 18 + TS host (W11). DOM-snapshot gate.                  |

Both example directories include a Playwright config that drives a
Chromium-headless run against committed `baselines/*.html` DOM
snapshots. Baselines are deliberately captured on the user's local
machine the first time `npm run test -- --update-snapshots` is run.

---

## 3. Working with the IR contract

`RenderingNode` is the same indirect enum the windows-port uses. The
JSON encoding is the same too (see
`AdaptiveCardsRenderingIR/RenderingNode+Codable.swift`). All 27
non-`unsupported` cases are implemented by both the Swift DOM walker
and both JS walkers.

### Stable DOM attributes

The single most important promise the renderer makes to hosts: every
emitted element carries a `data-ac-node="<case>"` attribute and one
or more `ac-*` CSS classes. Hosts and tests select by those. Examples:

| IR case             | DOM tag    | `data-ac-node`       | Primary class(es)            |
|---------------------|------------|----------------------|------------------------------|
| `.text`             | `<div>`    | `text`               | `ac-text` + size + weight    |
| `.richRun`          | `<span>`   | `richRun`            | `ac-rich-run` + size + weight |
| `.image`            | `<img>`    | `image`              | `ac-image` + display-hint    |
| `.verticalStack`    | `<div>`    | `verticalStack`      | `ac-stack ac-vertical-stack` |
| `.horizontalStack`  | `<div>`    | `horizontalStack`    | `ac-stack ac-horizontal-stack` |
| `.facts`            | `<dl>`     | `facts`              | `ac-facts`                   |
| `.code`             | `<pre>`    | `code`               | `ac-code`                    |
| `.progressBar`      | `<div>` + `<progress>` | `progressBar` | `ac-progressbar-row` / `ac-progressbar` |
| `.spinner`          | `<div>`    | `spinner`            | `ac-spinner`                 |
| `.accordion`        | `<div>` + `<details>` | `accordion` | `ac-accordion`              |
| `.table`            | `<table>`  | `table`              | `ac-table`                   |
| `.rating`           | `<div>`    | `rating`             | `ac-rating-display`          |
| `.textField`        | `<div>` wrapping `<input>` / `<textarea>` | `textField` | `ac-input-row ac-input-textField` |
| `.numberField`      | wrapper + `<input type="number">` | `numberField` | `ac-input-row ac-input-numberField` |
| `.toggleField`      | wrapper + `<input type="checkbox">` | `toggleField` | `ac-input-row ac-input-toggleField` |
| `.choiceField`      | wrapper + `<select>` | `choiceField` | `ac-input-row ac-input-choiceField` |
| `.dateField`        | wrapper + `<input type="date">` | `dateField` | `ac-input-row ac-input-dateField` |
| `.timeField`        | wrapper + `<input type="time">` | `timeField` | `ac-input-row ac-input-timeField` |
| `.ratingField`      | wrapper + `<input type="range">` | `ratingField` | `ac-input-row ac-input-ratingField` |
| `.chart`            | `<figure>` + `<table>` | `chart`    | `ac-chart ac-chart-<kind>`   |
| `.tabSet`           | `<div role="tablist">` + `<div role="tabpanel">` | `tabSet` | `ac-tabset`           |
| `.carousel`         | `<section>` + dots + panel | `carousel` | `ac-carousel`            |
| `.list`             | `<ul>` / `<ol>` / `<div>` per style | `list` | `ac-list ac-list-<style>` |
| `.media`            | `<figure>` + `<video>`/`<audio>` | `media` | `ac-media`                |
| `.compoundButton`   | `<button>` | `compoundButton`     | `ac-compound-button`         |
| `.button`           | `<button>` | `button`             | `ac-button ac-action-<kind>` |
| `.unsupported`      | `<div>`    | `unsupported`        | `ac-unsupported`             |

Hosts that want to restyle the renderer write CSS against `ac-*`
classes — they do not need to touch the renderer code.

### Submit-payload merge

`Action.Submit` clicks pass through one of two converging code paths:

- **Swift side** (`DOMRenderer.swift`):
  `mergedSubmitPayload(originalJSON:)` parses the IR-emitted
  `dataJSON`, overlays live `registeredInputs[].read()` values, and
  re-serializes with `JSONEncoder(.sortedKeys)`. Hands the merged
  string to the host's `ActionDispatcher`.
- **JS / React side** (`walker.js` / `walker.tsx`):
  `buildSubmitPayload(originalJSON)` does the same overlay against
  the per-component input-state map and re-serializes with sorted
  keys.

Both paths produce the SAME merged JSON for the same inputs.

### What lives in shared baselines

`Snapshots/<card>.rendertree.json` and `A11yBaselines/<card>.a11y.txt`
on the **windows-port** branch are the canonical IR baselines for
the 8 reference cards. wasm-port doesn't have a copy yet — once a
shared validator target lands (currently parked because
windows-port's `AdaptiveCardsValidate` depends on the WinUI-side CABI
target), the snapshots get pulled into a `AdaptiveCardsValidate-Web`
or equivalent and run via `swift run`.

---

## 4. Three integration paths

### Path 1 — `AdaptiveCardsWebDemo` (pure-Swift WASM)

For hosts that already ship a Swift WASM module and want to consume
Adaptive Cards in-process. Reuses
`AdaptiveCardsWebUI.DOMRenderer` directly; the cost is linking
JavaScriptKit (which roughly doubles the WASM artifact).

```bash
cd ios
. ~/.local/share/swiftly/env.sh
swift build -c release \
    --swift-sdk swift-6.3.2-RELEASE_wasm \
    --product AdaptiveCardsWebDemo
# .build/wasm32-unknown-wasip1/release/AdaptiveCardsWebDemo.wasm
```

The host wraps the .wasm in any JavaScriptKit-compatible bootstrap
(see `examples/embed-web-vanilla/src/main.js` for one).

### Path 2 — `examples/embed-web-vanilla/` (static HTML + JS)

For hosts that want zero Swift on the JS side. Bundle size is
roughly half Path 1's because `AdaptiveCardsWasmCABI` doesn't link
JavaScriptKit; the walker is plain JS.

```bash
cd ios
swift build -c release \
    --swift-sdk swift-6.3.2-RELEASE_wasm \
    --product AdaptiveCardsWasmCABI
cd ../examples/embed-web-vanilla
mkdir -p public/cards
cp ../../ios/.build/wasm32-unknown-wasip1/release/AdaptiveCardsWasmCABI.wasm \
   public/ac.wasm
cp ../../shared/test-cards/*.json public/cards/
npm install
npm run dev   # http://localhost:5173
```

The CABI surface is documented in
`ios/Sources/AdaptiveCardsWasmCABI/AdaptiveCardsWasmCABI.swift`'s
header comment.

### Path 3 — `examples/embed-web-react/` (TypeScript + React)

Same `ac.wasm` as Path 2; the host swaps the vanilla walker for a
React-element walker and exposes an `<AdaptiveCard json={...} />`
component. Inputs become controlled; the component manages
input-state + submit-payload merge automatically.

```bash
cd examples/embed-web-react
# same one-time wasm + cards copy as Path 2
npm install
npm run dev   # http://localhost:5174
```

```tsx
import { AdaptiveCard } from "./AdaptiveCard";

<AdaptiveCard
  json={cardJSON}
  onAction={(a) => {
    if (a.kind === "submit") {
      fetch("/api/submit", { method: "POST", body: a.dataJSON });
    }
  }}
/>
```

---

## 5. Validation gates

Local-only for now (per the user's directive — no GitHub Actions
runner-minute burn until W13). All four gates run in WSL Ubuntu
22.04 against the same checkout.

| Gate                                               | How to run                                          | Status                |
|----------------------------------------------------|-----------------------------------------------------|-----------------------|
| Swift build (Linux native)                          | `swift build`                                       | ✅ green (every commit) |
| Swift build (Swift WASM SDK)                        | `swift build --swift-sdk swift-6.3.2-RELEASE_wasm`  | ✅ green (every commit) |
| WASM export surface inspection                      | `strings .../AdaptiveCardsWasmCABI.wasm | grep ^ac_` | ✅ 5 exports, no JS imports |
| Playwright DOM-snapshot (`examples/embed-web-*`)    | `npm run test`                                      | 🟡 scaffolded; baselines on first local capture |

The Playwright gate is the wasm-port analogue of windows-port's
`windows-render-smoke` pixel-diff gate. We compare structured DOM
rather than pixels because:
1. Browser font / antialias rendering varies per-runner-OS; pixel
   diffs are noisy without per-OS baselines.
2. The IR contract is already what we want to assert on — pixel diff
   doesn't add information beyond "did the renderer + walker still
   produce the same DOM for the same IR?".

---

## 6. Phase log

| Phase   | Commit  | Description                                                                  |
|---------|---------|------------------------------------------------------------------------------|
| W1      | (init)  | AdaptiveCardsWebUI skeleton + JavaScriptKit dep.                             |
| W1.5    | (init)  | Extract shared `AdaptiveCardsRenderingIR` target (cherry-pick from windows-port). |
| W2      | (init)  | DOM walker: text, richRun, image, vertical/horizontal stacks.                |
| W3      | (init)  | `.button` rendering + `ActionDispatcher` + `WebActionRouter`.                |
| W4      | (init)  | All seven input fields + live submit-payload merge.                          |
| W5      | (init)  | Display-only nodes: facts, code, progress, spinner, accordion, table, rating. |
| W6      | (init)  | chart, tabSet, compoundButton.                                               |
| W7      | (init)  | carousel, list, media + WCAG SC 2.2.2 pause button.                          |
| W8      | (init)  | `AdaptiveCardsWebDemo` standalone executable target.                         |
| W9      | (init)  | `AdaptiveCardsWasmCABI` C-ABI module (`@_cdecl` exports).                    |
| W10     | (init)  | `examples/embed-web-vanilla/` + Playwright gate.                             |
| W11     | (init)  | `examples/embed-web-react/` (TS + React).                                    |
| W12     | (init)  | This document.                                                               |
| W13     | (open)  | Open the draft PR within `hggz/AdaptiveCards-Mobile-1` (wasm-port → main).   |

Commit hashes are intentionally omitted here so this file stays
diffable across rebases / squashes; `git log --oneline wasm-port`
is the source of truth.

---

## 7. Working rules carried over from windows-port

1. **Strictly additive.** No edits to `Sources/ACCore/`, iOS targets,
   `android/`, or anything the windows-port owns
   (`ios/Sources/AdaptiveCardsCrossUI/`,
   `ios/Sources/AdaptiveCardsCABI*/`,
   `ios/Sources/AdaptiveCardsWindowsDemo/`,
   `examples/embed-windows*/`,
   `.github/workflows/windows-port-ci.yml`).
2. **Draft PR within the fork.** When opening (W13), target
   `hggz/AdaptiveCards-Mobile-1@main` from `wasm-port`. Never open
   against `microsoft/AdaptiveCards` or `VikrantSingh01/AdaptiveCards-Mobile`
   without explicit user direction.
3. **Per-commit identity check.**
   ```bash
   git config user.name      # hggz
   git config user.email     # 6015420+hggz@users.noreply.github.com
   gh api user --jq '.login' # hggz
   ```
4. **One commit per phase**, fully self-contained with a detailed
   message. Reviewer optimisation, not author convenience.
5. **No NPMs / lockfiles / build outputs** committed:
   `examples/*/node_modules/`, `dist/`, `playwright-report/`,
   `public/ac.wasm`, `public/cards/` are all ignored per the
   example dir's `.gitignore`.
6. **Never push from `hugogonzalez_microsoft`** (work AAD account).

---

## 8. Known gaps + non-goals

These are deliberate parking lots, not bugs:

* **Live tab / carousel switching.** The IR pre-resolves
  `selectedTabIndex` / `selectedPageIndex`. The walker honours those
  but does NOT attach click handlers to switch panes live. Matches
  windows-port behaviour and the IR comment.
* **Closure pool cleanup.** `DOMRenderer.retainedClosures` keeps
  every `JSClosure` for the renderer's lifetime. Acceptable for the
  single-card model; if hosts mount and detach many cards a sweep
  will be needed.
* **`AdaptiveCardsValidate` analogue.** windows-port's validator
  target depends on `AdaptiveCardsCABI` (WinUI-side). A
  wasm-port-flavoured validator is parked until a clean split
  between the IR contract and the platform CABI lands on `main`.
* **Rating star row.** `.ratingField` renders as `<input type="range">`
  v1 rather than a clickable star row. The wire value is identical,
  so baselines don't care.
* **GitHub Actions workflow.** None checked in — local-only
  validation per the current directive.
* **Chart SVG visualization.** `.chart` renders as a labelled data
  table + colour swatch. Baseline-equivalent, but a future SVG layer
  is welcome on top of the same IR + `data-ac-chart-kind` attribute.

---

## 9. Related reading

* The handoff briefing: [`docs/wasm-port-handoff.md`](wasm-port-handoff.md).
* The windows-port sibling: [`docs/windows-port.md`](windows-port.md).
* Swift WASM upstream: <https://www.swift.org/documentation/articles/wasm-getting-started.html>.
* JavaScriptKit:  <https://github.com/swiftwasm/JavaScriptKit>.
* `@bjorn3/browser_wasi_shim`: <https://github.com/bjorn3/browser_wasi_shim>.
