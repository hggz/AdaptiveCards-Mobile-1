# Windows port — architecture & developer guide

> Branch: `windows-port` on `hggz/AdaptiveCards-Mobile-1`
> Status: pre-v1, single-commit-amend, draft PR deferred until the user
> approves.

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

### C-ABI shim (sketched, not implemented in v1)

A future `examples/embed-windows/c_abi/` directory will expose:

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

This is just a sketch — the implementation lands once a host actually
needs it. The Swift facade exists today so when the shim is added it's
a thin `@_cdecl` wrapper around `AdaptiveCardHost`.

---

## What's not yet on the windows-port branch

These are all called out explicitly in the brief as v1 in-scope but
remain to be done:

* Interactive input bindings (so `Input.Text`, `Input.Toggle`,
  `Input.ChoiceSet` actually mutate state and feed into
  `Action.Submit.data`).
* Remote image loading.
* `Table`, `ImageSet`-style grid layout, `Carousel`, `Accordion`,
  `ProgressBar`, `Spinner`, `Rating`, chart elements.
* Pixel-diff snapshot harness (the current snapshot diff is at the IR
  level only).
* A11y dump comparing against the SkypeSpaces accessibility-reviewer
  pipeline.
* `.github/workflows/windows-port-ci.yml` with the 5 required jobs:
  macos-existing, linux-build, windows-build, windows-render-smoke,
  windows-a11y-overlay.
* Verifying the existing iOS / Android pipelines stay green after the
  `swift-tools-version` 5.9 → 5.10 bump.

The draft PR stays parked until those land and the user gives the go.

---

## Identity reminders for contributors

* Author: `hggz <6015420+hggz@users.noreply.github.com>` for every
  commit on `windows-port`.
* Push only via SSH alias `github.com-hggz` to
  `hggz/AdaptiveCards-Mobile-1`.
* Never push from `hugogonzalez_microsoft` (corporate AAD account) or
  `hggzm` (Microsoft-fork account).
* Single-commit-amend discipline on `windows-port` until the branch is
  PR-ready; then split into logical commits if useful.
