# Windows port — architecture & developer guide

> Branch: `windows-port` on `hggz/AdaptiveCards-Mobile-1`  
> Status: POC coverage implemented; WPF interaction crash remains to be fixed.\
> Current evidence and next steps: [Windows agent handoff](windows-port-handoff.md).\
> Draft PR stays parked until the user approves.\
> History: phased commits (one feature per commit) on top of the
> Phase 15 a11y-baseline commit. See `git log --oneline windows-port`
> for the running list.

This document describes the Windows-native port of the SwiftUI fork of
AdaptiveCards-Mobile. The port adds a `swift-cross-ui`-backed renderer
without touching the existing iOS or Android targets, demonstrating a
generalizable "Windows Catalyst" pattern: the rendering substrate is a
protocol-shaped abstraction that can be swapped per platform.

---

## What's reused vs reimplemented

| Layer | Source of truth | Windows behaviour |
|---|---|---|
| Card JSON schema + sample cards | `shared/test-cards/*.json` | **Reused verbatim** — `SampleCardLibrary` reads the same files iOS and Android consume, via `#filePath` resolution. Zero JSON duplication. |
| ObjectModel + parser | `ACCore` (pure `import Foundation`) | **Reused verbatim**. Cross-platform stdlib + Foundation only; works on macOS, iOS, Linux, Windows. |
| Foundation extensions / utilities | `ACCore` types like `AnyCodable`, `HostConfig` JSON | Reused. |
| Renderer (element → view) | `ACRendering`, `ACInputs`, `ACActions`, … (Apple-only, `import SwiftUI`) | **Not used on Windows.** A new `AdaptiveCardsCrossUI` target maps the same `ACCore` element types to `swift-cross-ui` views. |
| Native UI substrate | SwiftUI on Apple platforms | **`swift-cross-ui` + WinUIBackend** on Windows. Same SwiftUI-style declarative DSL, different platform-native widgets underneath. |
| Embedding facade | n/a in the SwiftUI fork | `AdaptiveCardsWindowsEmbedded` exposes `AdaptiveCardHost` — a stable, swift-cross-ui-free embedding API for non-Swift hosts. |

---

## Target graph (windows-port additions)

```
                      ┌─────────────────────────┐
                      │  shared/test-cards/*.json  (shared with iOS/Android)
                      └─────────────┬───────────┘
                                    │
                                    ▼
                          ┌────────────────┐
                          │     ACCore      │   Foundation-only;
                          │  (parser + OM)  │   reused verbatim
                          └────────┬────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌─────────────────┐   ┌───────────────────────────┐   ┌─────────────────────────┐
│ AdaptiveCards   │   │   AdaptiveCardsCrossUI    │   │ AdaptiveCardsWindows-   │
│ CrossUITests    │◀──┤   library (Foundation +   │──▶│ Embedded library        │
│ (XCTest)        │   │   swift-cross-ui)         │   │ (pure-data facade)      │
└─────────────────┘   │                            │   │  AdaptiveCardHost       │
                       │ • RenderingNode (IR)      │   │  parse + renderTree     │
                       │ • Renderer                │   └─────────────────────────┘
                       │ • AdaptiveCardView        │
                       │ • SampleCardLibrary       │
                       │ • WindowsCardHost         │
                       └───┬───────────────┬──────┘
                           │               │
                           ▼               ▼
                  ┌──────────────────┐  ┌──────────────────────────┐
                  │ AdaptiveCards    │  │ AdaptiveCardsWindowsDemo  │
                  │ Validate         │  │ executable (WinUI window) │
                  │ (headless .exe)  │  └──────────────────────────┘
                  └──────────────────┘
```

---

## The `RenderingNode` IR

The renderer never builds swift-cross-ui views directly. Instead it
produces a `RenderingNode` enum value — a pure-Swift, platform-neutral
description of what the card should draw:

```swift
public indirect enum RenderingNode: Equatable, Codable, Sendable {
    case text(String, size: TextSize, weight: TextWeight, wrap: Bool, isSubtle: Bool)
    case richRun(String, size:, weight:, italic:, underline:, strikethrough:, isSubtle:)
    case image(url: String, alt: String, displayHint: ImageDisplayHint)
    case verticalStack(spacing: Int, children: [RenderingNode])
    case horizontalStack(spacing: Int, children: [RenderingNode])
    case facts([(title: String, value: String)])
    case code(text: String, language: String?, wrap: Bool)
    case textField(id:, label:, placeholder:, value:, isRequired:, isMultiline:)
    case numberField(id:, label:, placeholder:, value:, isRequired:)
    case toggleField(id:, title:, label:, value:, isRequired:)
    case choiceField(id:, label:, choices:, selected:, isMultiSelect:, isRequired:)
    case button(title: String, kind: ActionKind)
    case unsupported(typeString: String)
}
```

Three benefits of having the IR as a stable layer:

1. **Headless unit testing.** Every element-to-view mapping is asserted
   on the IR shape, no swift-cross-ui imports required. The XCTest
   suite and the `AdaptiveCardsValidate` harness both consume it.
2. **Snapshot regression.** `RenderingNode` is `Codable`, so the IR for
   every reference sample is committed under
   `Sources/AdaptiveCardsValidate/Snapshots/*.rendertree.json`. CI
   diffs current renders against those baselines.
3. **Multi-backend.** A future Linux/GTK or Win32-direct backend
   doesn't need to re-implement the element-to-view logic — only the
   IR-to-widget walker.

### Adding a new platform

The "Windows Catalyst" generalization is concrete: adding e.g. a
Linux/GTK backend requires three things and nothing else.

1. Make sure swift-cross-ui's `GtkBackend` is conditionally pulled into
   `AdaptiveCardsCrossUI` for `.linux`:
   ```swift
   .product(
       name: "GtkBackend",
       package: "swift-cross-ui",
       condition: .when(platforms: [.linux])),
   ```
2. Add a per-platform branch in `WindowsCardHost.backendIdentifier`
   returning `"gtk"`.
3. Optional: a `LinuxCardHost` named after the platform if you want a
   facade symmetric with `WindowsCardHost`. The renderer + view layer
   are platform-neutral and don't change.

That's the abstraction — no rewrite, no per-element fork.

---

## Build & run on Windows

### Prerequisites

| Component | Version | Install |
|---|---|---|
| Swift toolchain | 6.3.1-RELEASE | `winget install --id Swift.Toolchain` |
| Visual Studio MSVC + Win11 SDK | 2022+ or 2026 | VS installer with `VC.Tools.x86.x64` + `Windows11SDK.22621` |
| WindowsAppSDK runtime | 1.5.240205001-preview1 | `aka.ms/windowsappsdk/1.5/.../windowsappruntimeinstall-x64.exe` |

### Per-shell setup

```pwsh
& "C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\Tools\Launch-VsDevShell.ps1" `
    -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
$env:Path = "$HOME\AppData\Local\Programs\Swift\Toolchains\6.3.1+Asserts\usr\bin;" +
            "$HOME\AppData\Local\Programs\Swift\Runtimes\6.3.1\usr\bin;$env:Path"
$env:SDKROOT = "$HOME\AppData\Local\Programs\Swift\Platforms\6.3.1\Windows.platform\Developer\SDKs\Windows.sdk"
$env:DEVELOPER_DIR = "$HOME\AppData\Local\Programs\Swift\Platforms\6.3.1\Windows.platform\Developer"
```

The VS dev shell launcher clears `$env:SDKROOT` even when it's set at
User scope, so the explicit re-export above is mandatory.

### Critical: always scope `swift build`

The package contains Apple-only sibling targets (`ACFluentUI`,
`ACAccessibility`, `ACCopilotExtensions`, `ACRendering`, etc.) that
`import SwiftUI`. Those cannot compile on Windows. Running a bare
`swift build`, `swift test`, or `swift run` from the package root fails
immediately with `error: no such module 'SwiftUI'`.

Always scope the invocation:

```pwsh
swift build --target AdaptiveCardsCrossUI          # library
swift build --target AdaptiveCardsWindowsEmbedded  # embedding facade
swift build --product AdaptiveCardsValidate        # headless harness
swift build --product AdaptiveCardsWindowsDemo     # GUI demo
```

Launch the produced binaries directly — `swift run` will trigger a
full-package build:

```pwsh
& .build\debug\AdaptiveCardsValidate.exe           # 26 checks
& .build\debug\AdaptiveCardsWindowsDemo.exe        # WinUI window
```

A future cleanup option is to split the SwiftPM manifest into two
`Package.swift` files (Apple-only vs cross-platform) — but that's a
larger architectural change that should be discussed upstream first.

---

## The validation loop

`AdaptiveCardsValidate.exe` is the imperative regression harness. It
runs three suites:

1. **Renderer unit checks** — every element mapping (`TextBlock`,
   `Image`, `Container`, `ColumnSet`, `FactSet`, `Action.Submit`, …)
   asserts the exact `RenderingNode` produced.
2. **Reference sample renders** — each of the 5 curated cards in
   `SampleCardLibrary.referenceSampleFilenames` parses through `ACCore`
   and renders to a non-empty IR tree (except `edge-empty-card.json`,
   which deliberately renders to empty).
3. **Broad parse coverage** — every static `*.json` under
   `shared/test-cards/` (currently 38 files) round-trips through
   `CardParser` without error. Templating samples (5 files with
   `${var}` placeholders in spec-typed slots) are skip-listed because
   `ACTemplating` expansion is Apple-only.
4. **Snapshot baselines** — every reference card's `RenderingNode`
   tree is encoded as canonical JSON and diffed against a committed
   baseline. The harness writes a `Snapshots/<card>.rendertree.json`
   file per sample. Run with `--update-snapshots` to regenerate them
   after intentional renderer changes; default mode is strict diff.

```pwsh
& .build\debug\AdaptiveCardsValidate.exe                     # strict
& .build\debug\AdaptiveCardsValidate.exe --update-snapshots  # bootstrap
```

Exit code 0 on all-green, 1 on any failure.

---

## The Windows demo

`AdaptiveCardsWindowsDemo` is a real WinUI app (verified via
`PrintWindow` screenshot, title bar `"Adaptive Cards · Windows"`).
The window contains:

* A picker over the 5 reference samples.
* A `ScrollView` rendering the currently-selected card via
  `AdaptiveCardView`.
* A live action transcript that records every `Action.Submit` /
  `Action.OpenUrl` press.

For CI screenshot capture, set the `AC_DEFAULT_SAMPLE` env var to
pre-select a card filename before launch.

### Known visual placeholders

These are deliberately string-tagged in the rendered output, not
silently dropped. The IR carries the real spec value so the snapshot
diff catches any regression.

| Spec feature | v1 behaviour |
|---|---|
| Text size (`Large`, `ExtraLarge`) | Prefixed glyph (`■■ ` for extra-large, `■ ` for large). Real WinUI font sizing pending. |
| Text weight (`Bolder`) | Prefix `*`. |
| `isSubtle` | Prefix `~`. |
| RichTextBlock italics/underline/strikethrough | Prefix `/`, `_`, `-` respectively. |
| Image (HTTP URL) | Rendered as `[Image: <alt or url>]`. Async HTTP loader is v2. |
| Input.Text (read-only) | `[_] <placeholder>` or `[_] <value>`. Interactive binding is v2. |
| Input.Toggle | `[x] <title>` or `[ ] <title>`. |
| Input.ChoiceSet | `(*) <choice>` for radio, `[x] <choice>` for multi-select. |
| Unimplemented elements (`Carousel`, `Accordion`, etc.) | `[Unsupported element: TypeName]`. |

---

## Embedding from a host app

Three integration paths land on this branch — pick by your host's
existing toolchain, not by feature parity (they all reach the same
Swift renderer + the same `RenderingNode` IR):

| Path | When to use | Where |
|---|---|---|
| `AdaptiveCardsWindowsEmbedded` Swift API | Your host is itself a Swift / swift-cross-ui app and you want a typed `RenderingNode` tree + `ActionKind` callbacks | `ios/Sources/AdaptiveCardsWindowsEmbedded/` and the `AdaptiveCardsWindowsDemo` target |
| Static C-ABI link (`AdaptiveCardsCABI.lib`) | Your host is C / C++ / Rust with a `cl.exe` or clang build, and you want a single-executable, no-DLL deployment | [`examples/embed-windows/`](../examples/embed-windows/README.md) |
| Dynamic C-ABI load (`AdaptiveCardsCABIShared.dll`) | Your host is .NET / Electron / Python / anything with FFI but no static-link path | [`examples/embed-windows-csharp/`](../examples/embed-windows-csharp/README.md) (a working .NET 10 WPF host) |

### Swift API

The `AdaptiveCardsWindowsEmbedded` library product offers a stable
facade for non-Swift hosts (and Swift hosts that prefer a flat API):

```swift
import AdaptiveCardsWindowsEmbedded

let host = AdaptiveCardHost(hostConfigJSON: hostConfigJson)
host.onAction = { action in
    switch action {
    case let .submit(data): print("Submit:", data ?? "<no data>")
    case let .openUrl(url): print("Open:", url)
    default: break
    }
}

// Option A: pure-data — the host walks the IR itself
let tree = try host.renderTree(json: cardJson)

// Option B: pure-data via JSON over the wire
let jsonPlan = try host.renderJSON(json: cardJson)

// Option C (swift-cross-ui hosts): use AdaptiveCardView from the
// AdaptiveCardsCrossUI library and place it in your own SceneBuilder.
```

`AdaptiveCardsWindowsDemo` is the canonical worked example —
swift-cross-ui's WinUI 3 backend + the demo's
`ActionRouter.swift` showing how to wire `Action.OpenUrl` to
`ShellExecuteW` so the system browser actually launches.

### Static C-ABI link (`cl.exe`)

[`examples/embed-windows/`](../examples/embed-windows/README.md)
exposes a `@_cdecl` shim around `AdaptiveCardHost`:

```c
// adaptive_cards.h
typedef struct ACHost ACHost;
typedef void (*ACActionCallback)(int kind, const char* payload, void* userdata);

ACHost* ac_host_create(const char* host_config_json);
void    ac_host_destroy(ACHost*);
char*   ac_host_render_json(ACHost*, const char* card_json);  // caller frees with ac_free
void    ac_host_set_action_callback(ACHost*, ACActionCallback, void* userdata);
void    ac_free(char*);
```

`AdaptiveCardsCABI` is a **static** library target backed by `@_cdecl`
Swift functions. Build via
[`examples/embed-windows/c_abi/build.ps1`](../examples/embed-windows/c_abi/build.ps1);
the resulting `host-demo.exe` links `main.c` against the static lib +
Swift runtime, parses Adaptive Card JSON from C, and runs the renderer
headlessly. CI exercises this path via the `windows-c-example` job.

> ⚠ Critical link-order detail: `swiftrt.obj` must be the **first**
> input to `link.exe`. It registers Swift's protocol-conformance
> descriptors with the runtime; without it, any `JSONDecoder` /
> `Codable` call from C-hosted Swift crashes with
> `E_ACCESSVIOLATION`. See
> [`examples/embed-windows/README.md`](../examples/embed-windows/README.md#why-swiftrtobj-is-the-first-link-input)
> for the full rationale.

### Dynamic C-ABI load (P/Invoke / FFI)

`AdaptiveCardsCABIShared` is a **dynamic** library product (Phase 29)
backed by the same `AdaptiveCardsCABI` source target. SwiftPM
auto-exports every `@_cdecl` symbol when linked as a shared library on
Windows; verified via `dumpbin /exports`:

```
ac_free
ac_host_backend_identifier
ac_host_create
ac_host_destroy
ac_host_fire_action
ac_host_render_json
ac_host_set_action_callback
ac_last_error
```

[`examples/embed-windows-csharp/`](../examples/embed-windows-csharp/README.md)
is a worked .NET 10 WPF host (~600 lines C#) that:

1. Walks up from `AppContext.BaseDirectory` to locate
   `AdaptiveCardsCABIShared.dll` + the Swift runtime bin dir, then
   `AddDllDirectory`'s both so the Win32 loader resolves the DLL +
   its transitive Swift-runtime deps.
2. `DllImport`'s the 8 `ac_*` entry points (`AdaptiveCardsCabi.cs`).
3. Calls `ac_host_render_json(host, cardJson)`, parses the returned
   IR JSON with `System.Text.Json`, and walks every IR `"type"` into
   the matching WPF control: `TextBlock` / `Button` / `CheckBox` /
   `ComboBox` / `ProgressBar` / `Expander` / `Grid` / `TabControl`
   / `Image` / `DatePicker` (`RenderingNodeWalker.cs`).
4. Routes `Action.OpenUrl` clicks via `Process.Start(UseShellExecute = true)`
   — WPF's portable equivalent of the swift-cross-ui demo's
   `ShellExecuteW` path.

Substitute the WPF mappings for `Microsoft.UI.Xaml.Controls.*` and
you have a WinUI 3 host; substitute `System.Windows.Forms.*` and you
have a WinForms host; substitute Electron + node-ffi-napi and you
have an Electron host. The contract is the same.

---

## Status — phased history

The original brief listed a v1 scope that this branch now fully covers,
plus several follow-ups that are also landed. Each item below maps to
one commit on `windows-port`; see `git log --oneline windows-port` for
the full chain.

### Renderer coverage (every AdaptiveCards 1.6 element ACCore parses)

| Element | Phase | Status |
|---|---|---|
| TextBlock, RichTextBlock, Image, Container, ColumnSet | Phase 1–7 | Rendered |
| FactSet, CodeBlock, Table, ProgressBar, Spinner, Accordion, Rating (display) | Phase 8–11 | Rendered |
| Input.Text, Input.Number, Input.Toggle, Input.ChoiceSet, Input.Date, Input.Time | Phase 12–14 | Rendered + bound to submit payload |
| Chart (donut / bar / line / pie), TabSet, CompoundButton | Phase 16 | Rendered |
| Carousel | Phase 18 | Rendered |
| List (bulleted / numbered / default) | Phase 19 | Rendered |
| Media (audio / video) | Phase 20 | Text-fallback rendered (swift-cross-ui has no native AV widget) |
| Input.Rating (interactive) | Phase 21 | Rendered as a clickable star bar; binds to submit payload |

**UNRENDERED count across the reference set: 0.** Every spec element
ACCore decodes now reaches the View; the renderer has no remaining
`.unsupported` fallthrough cases.

### Live behaviour

* Tab and Carousel page selection lift to `@State` so users can switch
  at runtime (Phase 22).
* Carousel `autoAdvanceMs` drives a `.task(id:)` rotation loop with a
  WCAG-2.2.2-compliant Pause / Resume button (Phase 23).
* `ChartDatum.color` (`#RRGGBB` / `#RRGGBBAA`) applies to bar segments
  via `.foregroundColor` (Phase 24).
* `Action.OpenUrl` opens the system default browser via
  `ShellExecuteW`; the `ActionRouter` helper in the demo is the
  worked example of host-side action routing (Phase 28). Library
  itself stays side-effect-free — emitting `ActionKind` through
  `onAction` is the contract.

### Host integration paths

* `examples/embed-windows-csharp/` — .NET 10 WPF host POC that
  P/Invokes `AdaptiveCardsCABIShared.dll` and walks the IR into real
  WPF controls (Phase 29). Proves the embedding story for any
  non-Swift, non-C Windows host — WinUI 3 / WinForms / Electron /
  Rust / Python all use the same C ABI through the same DLL.
* `examples/embed-windows/` — minimal C host that statically links
  `AdaptiveCardsCABI.lib` via `cl.exe`. Same ABI, different link
  model. Exercised end-to-end by the `windows-c-example` CI job.

### Validation gate

Three layers, all reading the same baseline files at
`Sources/AdaptiveCardsValidate/{Snapshots,A11yBaselines}/`:

* `AdaptiveCardsValidate.exe` — headless harness; 93 / 93 deterministic
  checks covering renderer unit tests, submit-payload merges,
  reference-card snapshot diffs, broad parse coverage, C-ABI surface,
  and IR-level a11y baseline diffs. Runs on Windows and Linux CI.
* `AdaptiveCardsCrossUITests` XCTest target — reads the same baselines
  via three XCTestCase methods (Phase 25):
  `testEveryReferenceCardMatchesItsSnapshotBaseline`,
  `testEveryReferenceCardMatchesItsA11yBaseline`,
  `testAggregateA11yViolationBudget` (locks MISSING_LABEL: 0 /
  MISSING_ALT: 1 / UNRENDERED: 0). Exercised on macOS via
  `swift test --parallel`.
* PrintWindow pixel-diff smoke job — captures each reference card
  from a live `AdaptiveCardsWindowsDemo.exe` window, diffs against
  `Screenshots/<card>.png` baselines at ≤2% drift tolerance. Catches
  visual regressions the IR can't see.

### Reference cards (8)

The original 7 (`simple-text`, `containers`, `input-form`,
`all-actions`, `table`, `rating`, `edge-empty-card`) plus
`windows-extras.json` (Phase 17, extended in 18/19/20/21/24) which
consolidates Chart, TabSet, CompoundButton, Carousel, List, Media, and
Input.Rating into one card so all later renderer additions pick up
baseline coverage without adding more reference files.

### CI matrix

`.github/workflows/windows-port-ci.yml` runs five required jobs:

* **macos-existing** — confirms the iOS package still builds (sanity
  check the `swift-tools-version` bump didn't regress).
* **linux-build** — builds the four windows-port targets in a
  `swift:6.3.2-jammy` container; runs `swift run AdaptiveCardsValidate`
  so IR snapshot + a11y baseline drift gets caught on Linux too.
* **windows-build (REQUIRED)** — builds all four targets, runs
  `AdaptiveCardsValidate.exe`'s 93 checks.
* **windows-render-smoke** — PrintWindow capture + pixel diff per
  reference card. Uploads the fresh captures as an artifact so
  baseline refresh is mechanical.
* **windows-c-example** — builds `examples/embed-windows/c_abi/`,
  links `main.c` against the static lib, runs the produced exe.

All five jobs are hard-required; none use `continue-on-error`.

### What's intentionally NOT on this branch

* No changes to `Sources/ACRendering`, `Sources/ACInputs`,
  `Sources/ACActions`, `Sources/ACAccessibility`, `Sources/ACFluentUI`,
  `Sources/ACMarkdown`, `Sources/ACCharts`, or anything iOS-specific.
  The windows-port is strictly additive.
* No changes to `android/`.
* No new entries in `shared/RENDERING_PARITY_CHECKLIST.md` or
  `docs/architecture/PARITY_MATRIX.md` — those are iOS-vs-Android
  parity docs by design; Windows status lives here in
  `docs/windows-port.md`.
* No production Carousel auto-rotation timer behaviour without a
  user-pause control (every auto-rotating Carousel surfaces a
  Pause / Resume button per WCAG 2.2.2).

The draft PR stays parked until the user gives the go.

---

## Identity reminders for contributors

* Author: `hggz <6015420+hggz@users.noreply.github.com>` for every
  commit on `windows-port`.
* Push only via SSH alias `github.com-hggz` to
  `hggz/AdaptiveCards-Mobile-1`.
* Never push from `hugogonzalez_microsoft` (corporate AAD account) or
  `hggzm` (Microsoft-fork account).
* History is **phased commits** — one feature per commit, descriptive
  multi-paragraph commit messages, every commit independently passes
  CI. Don't squash into one giant commit before opening the PR; the
  shape of the history is the audit trail.
