# Handoff — `wasm-port` sibling branch (Swift → WebAssembly + browser UI)

> **Audience.** A second agent picking up parallel work on a
> `wasm-port` branch. This document is your starting briefing — read
> it once end-to-end before you touch a file. The windows-port chief
> of staff retains ownership of everything in
> `ios/Sources/AdaptiveCardsCrossUI/`, `ios/Sources/AdaptiveCardsCABI*/`,
> `ios/Sources/AdaptiveCardsWindowsDemo/`, `examples/embed-windows*/`
> and `.github/workflows/windows-port-ci.yml`. Your scope is
> everything web / WASM under new namespaces (see § 4).

## TL;DR

* You're delivering the **same renderer pipeline** the
  [`windows-port`](https://github.com/hggz/AdaptiveCards-Mobile-1/tree/windows-port)
  branch ships, but targeting **Swift → WebAssembly** and rendering
  to the **browser DOM** instead of WinUI.
* Same parse layer (`ACCore`), same `RenderingNode` IR, same
  `A11yDump`, same reference cards, same snapshot + a11y baselines.
  **The IR is invariant.** The only thing that varies is what the
  View layer draws.
* Three host-integration paths to deliver, mirroring the windows
  trio:
  1. Pure SwiftWASM web app
     (`AdaptiveCardsWebDemo`) — analogous to `AdaptiveCardsWindowsDemo`.
  2. WASM module called from **vanilla JS** + static HTML
     (`examples/embed-web-vanilla/`) — analogous to
     `examples/embed-windows/` (static C-ABI link).
  3. WASM module called from a **TypeScript/React** app
     (`examples/embed-web-react/`) — analogous to
     `examples/embed-windows-csharp/` (P/Invoke from a non-Swift
     host).
* Identity, branching, commit shape, PR posture, baseline-bootstrap
  pattern: **identical** to the windows-port rules (see § 11).
  Open a draft PR on **`hggz/AdaptiveCards-Mobile-1` only**; do
  **not** PR upstream without explicit user direction.

---

## 1. Identity & hosting rules (unchanged from windows-port)

* **Author:** `hggz <6015420+hggz@users.noreply.github.com>` on every
  commit. Verify with `git config --get user.name` /
  `--get user.email` immediately after cloning.
* **Push only via SSH alias `github.com-hggz`** to
  `git@github.com-hggz:hggz/AdaptiveCards-Mobile-1.git`.
* **GitHub CLI** must be authenticated as `hggz`:
  `gh auth status` and check the active account is `hggz`. Confirm
  with `gh api user --jq '.login'` → `hggz`.
* **Never** commit as your work identity
  (`hugogonzalez@microsoft.com`) on this repo.
* **No upstream PRs** to `VikrantSingh01/AdaptiveCards-Mobile` or
  `microsoft/AdaptiveCards`. Draft PR within the fork only.

If you are working from a fresh clone and `gh repo set-default`
complains, set: `gh repo set-default hggz/AdaptiveCards-Mobile-1`.

## 2. Why a separate branch (not a merge into windows-port)

* swift-cross-ui's WinUI backend does **not** target browsers, and
  there's no shared compilation between the Windows toolchain
  (`x86_64-unknown-windows-msvc`) and the WASM SDK
  (`wasm32-unknown-wasi`). The renderer-Views layer **must** fork:
  one View layer per platform, both consuming the same IR.
* The windows-port branch ships 30 commits of working code, a green
  CI matrix on five jobs, and a parked draft PR (#2). It should
  remain stable while you work.
* Your branch:
  ```bash
  git fetch origin
  git checkout -b wasm-port origin/main      # base on main, not windows-port
  ```
  Cherry-pick **only** the documents you need from `windows-port`
  (see § 12); avoid pulling in `ios/Sources/AdaptiveCardsCrossUI/`,
  `ios/Sources/AdaptiveCardsCABI*/`, the embed-windows examples, or
  `windows-port-ci.yml` — those belong to the windows-port lineage.

## 3. Required reading (in this order)

1. **The windows-port doc.** `docs/windows-port.md` on the
   `windows-port` branch. Read it whole — it's the architectural
   blueprint you are mirroring. Pay attention to:
   * § The `RenderingNode` IR (the contract you must NOT touch)
   * § The validation loop (your gates will mirror this)
   * § Embedding from a host app (the three-paths shape)
   * § Status — phased history (the commit-cadence pattern)
2. **Swift WASM getting-started.**
   <https://www.swift.org/documentation/articles/wasm-getting-started.html>
3. **swiftlang's official WASM examples.**
   <https://github.com/swiftlang/swift-for-wasm-examples>
   Read the `WebGPUDemo` and `DOMRefTypes` package layouts; they
   are the closest officially-supported templates to what you'll
   build. `WasmGuide.docc` under that repo's `Sources/` is
   secondary reading for advanced cases.
4. **swiftwasm/swift-web-github-example.**
   <https://github.com/swiftwasm/swift-web-github-example>
   Older (5.4 toolchain era) but the JS-bundler + webpack +
   `JavaScriptKit` integration pattern is still relevant for
   `examples/embed-web-vanilla/` and `examples/embed-web-react/`.
5. **WebAssembly Vision for Swift.**
   <https://github.com/swiftlang/swift-evolution/blob/main/visions/webassembly.md>
   For the "why" + the policy direction the toolchain is taking.
6. **JavaScriptKit.**
   <https://github.com/swiftwasm/JavaScriptKit> — your DOM bridge.
   API tour at <https://swiftpackageindex.com/swiftwasm/JavaScriptKit>.

## 4. Target namespaces (mirror of the windows-port targets)

Pick names that mirror the windows-port pattern so a reviewer
flipping between the two branches can see the symmetry instantly.
Suggested:

| Concern | windows-port name | wasm-port name |
|---|---|---|
| Platform-specific View + IR walker | `AdaptiveCardsCrossUI` | `AdaptiveCardsWebUI` |
| Embedding facade (typed Swift API) | `AdaptiveCardsWindowsEmbedded` | `AdaptiveCardsWasmEmbedded` |
| C-ABI (compiled to WASM exports) | `AdaptiveCardsCABI` (static) | `AdaptiveCardsWasmCABI` (static) — produces WASM module exports |
| Demo app | `AdaptiveCardsWindowsDemo` | `AdaptiveCardsWebDemo` |
| Headless validator | `AdaptiveCardsValidate` | **reuse** (same target name, OS-gated additions where needed) |
| Test harness | `AdaptiveCardsCrossUITests` | `AdaptiveCardsWebUITests` |

**Critical:** the validator + test scaffolding under
`ios/Sources/AdaptiveCardsValidate/` and
`ios/Tests/AdaptiveCardsCrossUITests/` is **shared**. The IR
snapshots in `Sources/AdaptiveCardsValidate/Snapshots/*.json` and
the a11y baselines in `Sources/AdaptiveCardsValidate/A11yBaselines/*.txt`
**must remain byte-identical** between branches. The IR is the
contract; if your branch produces different IR for the same card,
you have a renderer bug, not a baseline drift.

## 5. Environment — Swift WASM on WSL

You **must** build from Linux (or macOS). The Swift toolchain
[explicitly does not support cross-compiling to WASM from Windows
hosts](https://github.com/swiftlang/swift-package-manager/issues/9148).
WSL 2 with Ubuntu 22.04 is the recommended setup.

```bash
# In WSL Ubuntu 22.04+:

# 1. Install swiftly.
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar -xzf swiftly-$(uname -m).tar.gz
./swiftly init
source ~/.local/share/swiftly/env.sh

# 2. Install a Swift toolchain matching the wasm SDK.
swiftly install 6.3.2
swiftly use 6.3.2

# 3. Install the WASM SDK. The URL + checksum are pinned in
#    the Swift.org getting-started article (URL #2 above) and
#    bumped per release; verify before pasting.
swift sdk install \
  https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum a61f0584c93283589f8b2f42db05c1f9a182b506c2957271402992655591dd7c

# 4. Confirm the SDK ID — you'll need it for every build invocation.
swift sdk list
# Expect two entries: swift-6.3.2-RELEASE_wasm and ..._wasm-embedded.

# 5. Smoke-test with the canonical hello.
mkdir hello && cd hello
swift package init --type executable
swift build --swift-sdk swift-6.3.2-RELEASE_wasm
swift run   --swift-sdk swift-6.3.2-RELEASE_wasm
# Expect: "Hello from WASI!"
```

### Browser + JS tooling (for the demo + examples)

The minimum viable JS-side toolchain is **Node 20 LTS + pnpm**
(or npm; pnpm has the better workspace story for the two example
dirs). Add a tiny `package.json` per example dir.

The Swift-side WASM build produces `<product>.wasm` under
`.build/wasm32-unknown-wasi/debug/`; the JS side instantiates it
via `WebAssembly.instantiateStreaming` (or `WebAssembly.instantiate`
for Node).

For `JavaScriptKit`-based DOM interop, the simplest dev story is:

* **Vite** for the demo + examples — zero-config, native ESM,
  built-in dev server with HMR.
* **`@bjorn3/browser_wasi_shim`** or
  **`@wasmer/wasi`** for WASI shim in the browser
  (the WASM SDK produces WASI binaries; browsers need a JS
  polyfill for `wasi_snapshot_preview1`).

Use the swiftwasm/swift-webpack-template / swift-web-github-example
pattern as a *reference* for project structure, but prefer Vite +
modern toolchain over the older webpack setup.

## 6. Architecture — what maps to what

```
┌─────────────────┐    ┌─────────────────────────┐   ┌──────────────────────────┐
│ ACCore (shared) │───▶│ Renderer + RenderingNode│◀──┤ AdaptiveCardsWebUI       │
│ pure parse layer│    │   IR (SHARED, do not    │   │ (your new target)        │
│                 │    │   modify)               │   │ JavaScriptKit / Tokamak  │
└─────────────────┘    │                         │   │ ↓                        │
                       │                         │   │ DOM elements             │
                       └─────────────────────────┘   └──────────────────────────┘
                                  │
                                  ▼
                       ┌─────────────────────────┐
                       │ A11yDump (SHARED) +     │
                       │ snapshot baselines      │
                       └─────────────────────────┘
```

* **You do not touch** `ACCore`, `RenderingNode`,
  `RenderingNode+Codable.swift`, `A11yDump.swift`, `Renderer.swift`,
  the `Snapshots/*.json`, the `A11yBaselines/*.txt`, or any
  `shared/test-cards/*.json` files except for adding new ones for
  new platform-specific coverage (and only if absolutely required —
  prefer not to). These are the IR contract surface.
* **You implement** the View layer: walk `RenderingNode` and emit
  DOM elements (via JavaScriptKit's `JSObject`, or — easier — pick
  Tokamak and let it do the View-protocol → DOM mapping for you).

### Picking the View layer

Two viable options. Try (a) first, fall back to (b) if you hit
toolchain incompatibility:

| Option | Pro | Con |
|---|---|---|
| **(a) Tokamak** (`TokamakUI/Tokamak`) | SwiftUI-shaped API → smallest delta from windows-port's `AdaptiveCardView.swift`. `Text`, `VStack`, `Button` etc. exist; `@State` works. | Maintenance varies; verify it builds against Swift 6.3.2 WASM SDK before committing to it. |
| **(b) JavaScriptKit + manual DOM walker** | Maximum control, no third-party UI framework risk. Matches the WPF host POC pattern in `examples/embed-windows-csharp/RenderingNodeWalker.cs` — that walker is 600 lines of "given an IR, produce native controls"; the Swift analog is the same shape against `document.createElement(...)`. | More code to maintain; need your own `@State` equivalent for live tab / page selection. |

Option (b) is the **safer bet** for a v1 because it has zero
external UI-framework risk and the walker shape is already proven
twice (Swift-cross-ui `AdaptiveCardView.swift` and C#
`RenderingNodeWalker.cs`).

## 7. Three integration paths to ship

Mirror the windows-port trio. Land them in this order — each
unlocks the next:

### Path 1 — `AdaptiveCardsWebDemo` (analogous to `AdaptiveCardsWindowsDemo`)

A standalone Swift app compiled to WASM. Drives the renderer +
View layer + an action transcript. The browser loads
`AdaptiveCardsWebDemo.wasm` and the app populates the DOM directly
via JavaScriptKit / Tokamak. This is your "hello adaptive card"
and the basis for the smoke gate.

Source layout to aim for:
```
ios/Sources/AdaptiveCardsWebDemo/
  ├ AdaptiveCardsWebDemoApp.swift   (entry; mirror the Win demo)
  ├ WebActionRouter.swift           (action handling: openUrl→window.open)
  └ index.html / index.ts           (only if Tokamak/JSK needs bootstrap glue)
```

`window.open(url, "_blank")` from JavaScriptKit is your
analog of `ShellExecuteW`. Action routing belongs in the demo,
**not** in `AdaptiveCardsWebUI` — same rule as the windows-port.
Hosts decide policy.

### Path 2 — `examples/embed-web-vanilla/` (analogous to `examples/embed-windows/`)

Static HTML + vanilla JS that instantiates `AdaptiveCardsWasmCABI.wasm`,
calls the exported WASI function `ac_host_render_json`, parses the
returned IR JSON, walks it into the DOM. Demonstrates that **no
Swift is required on the host side** — same property the C example
proves for native Windows.

Use the same `@_cdecl` shim already implemented in
`ios/Sources/AdaptiveCardsCABI/CABI.swift` (don't duplicate it;
add a new target product `AdaptiveCardsWasmCABI` that depends on
the same source files OR fork CABI.swift if module rules make it
necessary). The exports survive WASM compilation; verify with
`wasm-objdump -x <module>.wasm | grep ac_host_`.

### Path 3 — `examples/embed-web-react/` (analogous to `examples/embed-windows-csharp/`)

A small Vite + React + TypeScript app that imports
`AdaptiveCardsWasmCABI.wasm`, instantiates it once, exposes a
`<AdaptiveCard json={...} />` component that calls
`ac_host_render_json` under the hood and walks the IR into React
elements. Same shape as the WPF host POC.

This is the path that lets **any** modern web app
(Next.js, SvelteKit, Vue) embed the renderer with no Swift in their
build chain.

## 8. Validation gates (carry over wholesale)

* **`AdaptiveCardsValidate` (REQUIRED)** — same harness. On
  Linux/WSL: `swift run AdaptiveCardsValidate`. Same 93 checks
  pass; your branch must not regress the snapshot or a11y baselines.
* **`AdaptiveCardsWebUITests` (REQUIRED)** — port the
  `IRBaselineSnapshotTests` pattern from Phase 25. Three test
  cases, reading the **same** files
  (`Sources/AdaptiveCardsValidate/{Snapshots,A11yBaselines}/`).
* **Browser DOM smoke (REQUIRED)** — analog of
  `windows-render-smoke`. Use Playwright (Chromium headless) to
  load `examples/embed-web-vanilla/` against each reference card
  in turn, take a screenshot, pixel-diff against committed
  baselines at ≤2% drift tolerance. **Use the same image-diff
  helper** the windows job uses
  (`.github/workflows/windows-port-ci.yml`'s pixel-diff step is
  PowerShell; port the algorithm to JS/Node — it's ~30 lines).
* **WASM module export surface (REQUIRED)** — analog of
  `windows-c-example`. A tiny Node script that
  `WebAssembly.instantiateStreaming`s the `.wasm`, asserts the 8
  `ac_*` exports exist with the right arity, calls
  `ac_host_render_json` against `simple-text.json`, and prints the
  IR JSON. Fails CI if the export list changes.
* **macOS + Linux build sanity** — make sure your additions don't
  break the existing iOS package or the Linux validator. Add a
  `wasm-port-ci.yml` workflow modeled on `windows-port-ci.yml`.

Violation budget locks the SAME numbers we lock today:
`MISSING_LABEL: 0`, `MISSING_ALT: 1`, `UNRENDERED: 0`.

## 9. Reference cards

**Reuse the 8 cards** under `shared/test-cards/`:
* `simple-text.json`, `containers.json`, `input-form.json`,
  `all-actions.json`, `table.json`, `rating.json`,
  `edge-empty-card.json`, `windows-extras.json`.

`windows-extras.json` is the omnibus card and should also be your
omnibus — chart + tabset + carousel + list + media + compound-button
+ input.rating. Same IR will be produced from the same JSON, so
your test bench is plug-and-play.

Do **not** rename the file. The IR snapshot file is
`Snapshots/windows-extras.rendertree.json` and the a11y baseline is
`A11yBaselines/windows-extras.a11y.txt` — both are read by your
new XCTest target and by `AdaptiveCardsValidate.exe` (Windows) /
`AdaptiveCardsValidate` (Linux) / your WASM runtime. If a renamed
"web-extras" baseline is genuinely needed for additional web-only
coverage, ADD a new card alongside, don't rename.

## 10. Phased commit cadence (the windows-port playbook)

Mirror our phase numbering and granularity. Each phase = one
focused commit with a detailed message in this shape:

```
feat(wasm-port): <one-line summary>

Phase N <reason>.

Files:
  ...
What this does:
  ...
What it does NOT do:
  ...
Validation:
  swift build --swift-sdk swift-6.3.2-RELEASE_wasm --target X -- clean
  npm run test:dom-snapshot -- clean
  ...
Backlog:
  ...

PR remains parked at draft #<N> in hggz/AdaptiveCards-Mobile-1.
```

Suggested first ~10 phases (subject to your judgement):

| Phase | Goal |
|---|---|
| W1 | Add `AdaptiveCardsWebUI` skeleton + the JavaScriptKit / Tokamak dependency in `Package.swift`. Gated `#if canImport(JavaScriptKit)`. |
| W2 | Render `.text`, `.richRun`, `.image`, `.verticalStack`, `.horizontalStack`. |
| W3 | Render `.button` + `WebActionRouter` for `Action.OpenUrl` via `window.open`. |
| W4 | All input fields (`.textField` / `.numberField` / `.toggleField` / `.choiceField` / `.dateField` / `.timeField` / `.ratingField`) + submit payload merge. |
| W5 | Render `.facts`, `.code`, `.progressBar`, `.spinner`, `.accordion`, `.table`, `.rating` (display). |
| W6 | Render `.chart` (with `#RRGGBB` colour application), `.tabSet`, `.compoundButton`. |
| W7 | Render `.carousel`, `.list`, `.media`. Auto-rotation with WCAG Pause button. |
| W8 | `AdaptiveCardsWebDemo` (the swift-cross-ui-style demo equivalent). |
| W9 | `AdaptiveCardsWasmCABI` product + WASI export verification. |
| W10 | `examples/embed-web-vanilla/` + Playwright pixel-diff CI gate. |
| W11 | `examples/embed-web-react/`. |
| W12 | Docs (`docs/wasm-port.md`, mirror of `docs/windows-port.md`). |
| W13 | Draft PR within `hggz/AdaptiveCards-Mobile-1` (parked, never upstream without explicit go). |

## 11. Working rules — non-negotiable (carry over from windows-port)

1. **Strictly additive.** No edits to:
   * `Sources/ACCore/**` (the parser; shared).
   * `Sources/AC*` Apple iOS targets.
   * `android/**`.
   * `shared/RENDERING_PARITY_CHECKLIST.md`,
     `docs/architecture/PARITY_MATRIX.md` (iOS-vs-Android docs).
   * Anything the windows-port owns (§ section header).
2. **PR posture.** Open ONE draft PR within
   `hggz/AdaptiveCards-Mobile-1` (windows-port → main pattern;
   yours is wasm-port → main). **Do NOT open against**:
   * `microsoft/AdaptiveCards`
   * `VikrantSingh01/AdaptiveCards-Mobile`
   * any other upstream
   without explicit user direction. The user must say "open
   upstream" out loud; until then, parked draft in the fork only.
3. **Per-commit identity check.** Run before every push:
   ```bash
   git config user.name      # must be: hggz
   git config user.email     # must be: 6015420+hggz@users.noreply.github.com
   gh api user --jq '.login' # must be: hggz
   ```
4. **Baseline-drift handling.** Identical pattern to windows-port:
   * If your DOM snapshot drifts because of a known visual change
     (analog of the Phase 21 rating star promotion), download the
     CI artifact, replace the baseline PNG, commit as
     `chore(wasm-port): refresh <card>.png baseline for Phase W<N>`.
     Don't try to recapture locally if your devbox renders
     differently than the CI runner — that's exactly the trap that
     consumed two commits on windows-port (rating refresh +
     windows-extras dark-theme refresh).
5. **One commit per phase**, fully self-contained with detailed
   message. The windows-port has 30 commits over ~3 weeks and every
   one is independently readable. Optimise for the reviewer.
6. **No NPMs / Cargo / pip / etc. checked in.** Lockfiles only
   (`pnpm-lock.yaml`, etc.). All node_modules / .build / .swiftpm
   gitignored.
7. **Never push from `hugogonzalez_microsoft`.**

## 12. What to copy from `windows-port` (and what NOT to)

| Copy verbatim | Re-use unchanged | Do NOT pull |
|---|---|---|
| Phase commit-message style | `Sources/ACCore/` (it's already on `main`) | `Sources/AdaptiveCardsCrossUI/` |
| Reference card list (`SampleCardLibrary.referenceSampleFilenames`) | `Sources/AdaptiveCardsValidate/Snapshots/*.json` | `Sources/AdaptiveCardsCABI/` (you'll write your own) |
| `IRBaselineSnapshotTests` shape | `Sources/AdaptiveCardsValidate/A11yBaselines/*.txt` | `Sources/AdaptiveCardsWindowsDemo/` |
| 2 % pixel-drift gate algorithm | `shared/test-cards/*.json` | `Sources/AdaptiveCardsValidate/Screenshots/*.png` (those are windows-port pixel baselines) |
| Three-integration-paths story | `docs/windows-port.md` as the template for `docs/wasm-port.md` | `examples/embed-windows*/` |

## 13. Resources — bookmark these

* Swift WASM getting-started — <https://www.swift.org/documentation/articles/wasm-getting-started.html>
* Official examples — <https://github.com/swiftlang/swift-for-wasm-examples>
* Web demo template — <https://github.com/swiftwasm/swift-web-github-example>
* WASM vision document — <https://github.com/swiftlang/swift-evolution/blob/main/visions/webassembly.md>
* JavaScriptKit (DOM bridge) — <https://github.com/swiftwasm/JavaScriptKit>
* SwiftWasm org — <https://github.com/swiftwasm>
* WasmKit (runtime, used by `swift run --swift-sdk …`) — <https://github.com/swiftwasm/wasmkit>
* Tokamak (SwiftUI-shaped framework for the DOM) — <https://github.com/TokamakUI/Tokamak>
* Reference siblings:
  * `docs/windows-port.md` — your architectural blueprint
  * `examples/embed-windows-csharp/README.md` — the integration-host
    template you're paralleling
  * `examples/embed-windows/README.md` — the static-link C-ABI
    template you're paralleling

## 14. Definition of done (handoff-back checklist)

You hand the windows-port chief of staff back control when:

* [ ] `wasm-port` branch on `hggz/AdaptiveCards-Mobile-1` has all
      13 phases above committed and pushed.
* [ ] `wasm-port-ci.yml` is green on the latest HEAD (all five
      analog jobs).
* [ ] Reference-set violation totals match windows-port exactly:
      `MISSING_LABEL: 0`, `MISSING_ALT: 1`, `UNRENDERED: 0`.
* [ ] `docs/wasm-port.md` is the wasm-port's `docs/windows-port.md`
      — exhaustive, complete with the three-integration-paths story
      and per-phase commit table.
* [ ] All three example dirs build + run from a fresh WSL Ubuntu
      checkout following only the READMEs.
* [ ] Draft PR opened within `hggz/AdaptiveCards-Mobile-1`
      (wasm-port → main); the body embeds DOM screenshots of the
      8 reference cards via `raw.githubusercontent.com`.
* [ ] You write a similar handoff doc for whoever picks up
      `tokamak-port` or `flutter-port` or whatever the third
      sibling becomes.

---

## 15. Identity reminders for contributors (carry over)

* Author: `hggz <6015420+hggz@users.noreply.github.com>` for every
  commit on `wasm-port`.
* Push only via SSH alias `github.com-hggz` to
  `hggz/AdaptiveCards-Mobile-1`.
* Never push from `hugogonzalez_microsoft` (corporate AAD account)
  or any other identity.
* `gh repo set-default hggz/AdaptiveCards-Mobile-1` once per fresh
  clone so every `gh` command knows where to go.
* Draft PRs stay draft and stay in the fork until the user
  explicitly says "open upstream".

Good luck. The IR is invariant. The View layer is your canvas.
