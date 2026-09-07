# Windows Port: Agent Handoff

Consolidated 2026-09-06. Implementation baseline at the start of this handoff:
`eedb209` on `windows-port`. This handoff is documentation, not a new crash fix.

**First task: fix the reproduced WPF deferred-JSON lifetime bug.** A page-2-to-3
click and a Submit click both throw `ObjectDisposedException` in the unchanged
WPF walker after `Build(string)` returns. This is distinct from the previously
fixed Swift static-link startup problem. See the reproduction below.

## Start Here

Continue the Windows-native Adaptive Cards port in **AdaptiveCards-Mobile**,
not SwiftReactKit, SwiftyScript, or a newly scaffolded application. The long
transcript is historical evidence; the checked-out code and fresh validation
results take precedence over its phase numbers and repeated summaries.

The existing fork is **hggz/AdaptiveCards-Mobile-1**. The local checkout is
`C:\Users\hugogonzalez\code\AdaptiveCards-Mobile`. At initial inspection the
worktree was clean. A fresh `git fetch origin` confirmed both local and remote
`windows-port` at `eedb20985e1a05a5a558635a545cc88f7fc859c4`: all implementation
work was already published before this documentation pass.

| Setting | Verified value |
| --- | --- |
| Working branch | `windows-port` |
| `origin` fetch/push | `git@github.com-hggz:hggz/AdaptiveCards-Mobile-1.git` |
| `upstream` | `https://github.com/VikrantSingh01/AdaptiveCards-Mobile.git` |
| Local author | `hggz <6015420+hggz@users.noreply.github.com>` |
| Active `gh` account | `hggz` |

Do not switch this work to `hggzm`, push to upstream, or transplant it onto
`main`. Preserve the existing branch and history. Draft PR preparation remains
parked pending the user's approval; publishing the work to the fork does not
authorize opening, readying, or merging an upstream PR. The opening transcript
brief's `hggzm` and WSL paths are superseded by the verified checkout above.

Live GitHub checks confirmed:

- Authenticated `hggz` has `ADMIN` access to the existing fork.
- [Fork PR #2](https://github.com/hggz/AdaptiveCards-Mobile-1/pull/2) is OPEN and
   DRAFT, targeting the fork's `main` from `windows-port`. Leave it that way.
- No upstream PR from `hggz:windows-port` was found.
- `origin/wasm-port` is a separate, published sibling branch. Do not merge,
   reset, or modify it while working on Windows.

## Read in This Order

1. This handoff, especially the crash-status and continuation sections.
2. [Windows architecture and developer guide](windows-port.md). Some early
   sections describe the original v1 state and are not current coverage counts.
3. [Parked PR description](windows-port-pr-description.md).
4. [WPF P/Invoke example](../examples/embed-windows-csharp/README.md) and
   [static C embedding example](../examples/embed-windows/README.md).
5. [Windows CI workflow](../.github/workflows/windows-port-ci.yml) for the
   authoritative build and validation commands.
6. [Wasm sibling handoff](wasm-port-handoff.md) only when considering that
   separate line of work. It is not the Windows crash investigation.

## Architecture and Host Boundaries

The original Apple renderer uses Apple SwiftUI. Windows does **not** run
Apple SwiftUI. It reuses the Foundation-based `ACCore` models and parser,
then maps card elements into the platform-neutral `RenderingNode` IR through
`AdaptiveCardsCrossUI`.

| Host path | What crosses the boundary | What draws the UI |
| --- | --- | --- |
| Swift native demo, `AdaptiveCardsWindowsDemo` | Typed Swift rendering tree and actions | swift-cross-ui with WinUIBackend |
| Static C example, `AdaptiveCardsCABI` | C ABI returning an opaque host and UTF-8 IR JSON | The consumer; the included C console example validates the ABI |
| C# WPF example, `AdaptiveCardsCABIShared.dll` | P/Invoke calls into the same C ABI | C# `RenderingNodeWalker` builds WPF controls |

`AdaptiveCardsWindowsEmbedded.AdaptiveCardHost` is the data-oriented embedding
facade. The WPF POC uses Swift for parsing and IR construction; it does not
embed the swift-cross-ui WinUI widget tree. A crash in one host is not evidence
of the same failure in the other.

The manifest is Swift tools 5.10 and pins `stackotter/swift-cross-ui` to **0.6.0**.
Actual validated toolchains are Swift **6.3.1 locally** and **6.3.2 in Windows /
Linux CI**. Do not infer that every Swift 5.10/6.0 compiler can parse all
transitive manifests. WinUI requires the WindowsAppSDK
**1.5.240205001-preview1** runtime used by the workflow. A static C ABI link
does not make the Swift runtime or WinUI runtime deployment requirements vanish.

Primary implementation surfaces:

- [Package manifest](../ios/Package.swift): products and platform dependencies.
- [CrossUI implementation](../ios/Sources/AdaptiveCardsCrossUI/): IR, renderer,
  native view construction, samples, and semantic accessibility dumps.
- [C ABI](../ios/Sources/AdaptiveCardsCABI/CABI.swift): exported functions and
  ownership boundary.
- [Static C build](../examples/embed-windows/c_abi/build.ps1): non-Swift startup
  and linker integration.
- [WPF application startup](../examples/embed-windows-csharp/AdaptiveCardsWpf/App.xaml.cs):
  discovery of the Swift DLL and runtime directories.
- [WPF P/Invoke declarations](../examples/embed-windows-csharp/AdaptiveCardsWpf/AdaptiveCardsCabi.cs):
  UTF-8 marshaling and native allocation ownership.
- [WPF window](../examples/embed-windows-csharp/AdaptiveCardsWpf/MainWindow.xaml.cs):
  host lifetime and sample selection.
- [WPF walker](../examples/embed-windows-csharp/AdaptiveCardsWpf/RenderingNodeWalker.cs):
  control construction and interactions.

### C ABI ownership and integration contract

The DLL exports eight symbols: `ac_host_create`, `ac_host_destroy`,
`ac_host_backend_identifier`, `ac_host_render_json`,
`ac_host_set_action_callback`, `ac_host_fire_action`, `ac_free`, and
`ac_last_error`.

- Destroy each successfully created host exactly once.
- Returned render/backend UTF-8 buffers must be copied and released with
   `ac_free`, not a .NET allocator.
- `ac_last_error` is a borrowed, process-global pointer. Copy it immediately;
   another error-producing/clearing API call can invalidate it. Do not free it.
- Callback payloads are borrowed for the callback's duration. Retain a copy
   if needed later; dispatch to the UI thread when required. A managed callback
   delegate must remain rooted for as long as native code can call it.
- The current WPF wrapper declares the six lifecycle/render/error/free APIs,
   not the two action-callback APIs. WPF actions are handled in the walker;
   do not mistake the POC for a complete C ABI callback/input integration.

## What Already Landed After the Transcript

The transcript reaches Phase 15, begins Phase 16, then repeats Phase 14 while
trying to resume a crash report. It is not a complete account of the current
branch. The following later commits are already in the initial checkout:

| Commit | Completed work |
| --- | --- |
| `82b126e` | Deterministic IR accessibility baselines replaced the unreliable live UIA CI walker |
| `c2078ce`, `80d807f` | Chart, TabSet, CompoundButton support and the windows-extras reference card |
| `a4957a0`, `5017caf`, `a14a0be` | Carousel, List, and Media mappings |
| `d7fc23d` | Interactive Input.Rating |
| `be16e2d`, `1a3a09f` | Live tabs/pages and carousel auto-rotation with Pause |
| `ddea0fe`, `118d3c7` | Chart datum colors and cross-platform IR baseline validation |
| `9caf1f5`, `2f0a402`, `d1960dc` | windows-extras smoke capture and refreshed screenshot baselines/count |
| `a4b5c87` | Native Action.OpenUrl dispatch through ShellExecuteW |
| `5bbc405`, `eb60da6` | Dynamic C ABI consumed by a WPF host and its screenshot |
| `1377d29`, `eedb209` | Three embedding paths documented; separate wasm handoff |

Do not restart Phase 16 or describe these elements as wholly unimplemented.
Implemented IR cases and POC controls do not imply full Adaptive Cards visual,
interaction, accessibility, or security parity.

## Verified Validation and Its Limits

[CI run 26105725363](https://github.com/hggz/AdaptiveCards-Mobile-1/actions/runs/26105725363)
completed successfully for the exact implementation baseline `eedb209`.
The API still reports all five jobs as successful. Historical detailed logs
now return HTTP 410, so the per-assertion counts below come from the fresh local
run, not a newly downloaded historical log.

| Existing job | Actual scope |
| --- | --- |
| `macos-existing` | Builds ACCore, AdaptiveCardsCrossUI, AdaptiveCardsWindowsEmbedded, AdaptiveCardsCABI |
| `linux-build` | Builds those targets in `swift:6.3.2-jammy` and runs the headless validator |
| `windows-build` | Builds the Windows targets and runs the headless validator |
| `windows-render-smoke` | Launches the native WinUI demo with each of eight cards and compares PrintWindow captures with committed PNGs at 2% tolerance |
| `windows-c-example` | Builds, links, and runs the static C consumer, including the render path |

None uses `continue-on-error`. Nevertheless, this workflow does **not** run
the WPF host, dynamic-DLL consumer tests, deferred WPF click handlers, live
UIA/Narrator tests, the full iOS app build, Android tests, or `swift test`.
The macOS job's display name and some older guide text overstate its scope.
The `AdaptiveCardsCrossUITests` XCTest target exists, but this workflow does
not execute it.

Fresh checks performed during consolidation:

| Check | Result |
| --- | --- |
| Scoped `AdaptiveCardsValidate` build and run | **93 passed, 0 failed** |
| Aggregate semantic a11y markers | **MISSING_LABEL=0, MISSING_ALT=1, UNRENDERED=0** |
| WPF `dotnet build`, .NET SDK 10.0.303 | Succeeded |
| External .NET P/Invoke success-path probe | **8/8** cards returned non-null UTF-8 IR; create/backend/render/free/destroy completed |
| WPF deferred-event characterization probe, unchanged walker linked as source | **2/2 expected failures reproduced**, page navigation and Submit |

The eight P/Invoke outputs, in characters: `simple-text` 686, `containers`
1648, `input-form` 1023, `all-actions` 1188, `table` 2599, `rating` 2706,
`edge-empty-card` 70, and `windows-extras` 6656. This probe checked successful
FFI returns and ownership cleanup, not WPF interactions or every error/callback
path. The earlier shared-DLL build also succeeded at this same code baseline.

Baseline locations under [the validator](../ios/Sources/AdaptiveCardsValidate/):
`Snapshots/`, `A11yBaselines/`, and `Screenshots/`. Review intentional output
changes before regenerating baselines. Do not bless a failing test merely to
make the count green. The single missing-alt marker is a known budget, not
proof of full accessibility compliance. Semantic IR baselines do not establish
live focus order, keyboard behavior, screen-reader announcements, or contrast.

## Reproducible Windows Setup

Use the existing checkout, or clone the existing branch using an SSH alias
configured for the `hggz` key:

```pwsh
git clone --branch windows-port git@github.com-hggz:hggz/AdaptiveCards-Mobile-1.git AdaptiveCards-Mobile
Set-Location AdaptiveCards-Mobile
git config --local user.name hggz
git config --local user.email 6015420+hggz@users.noreply.github.com
gh api user --jq '.login'
git remote -v
```

On the current devbox, initialize the VS shell **before** exporting Swift
variables. The VS launcher can clear `SDKROOT`. Adjust installation paths on
another machine; do not silently mix compiler, SDK, and runtime versions.

```pwsh
Set-Location "$HOME\code\AdaptiveCards-Mobile"
& 'C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\Tools\Launch-VsDevShell.ps1' `
   -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
$swiftRoot = "$HOME\AppData\Local\Programs\Swift"
$env:Path = "$swiftRoot\Toolchains\6.3.1+Asserts\usr\bin;$swiftRoot\Runtimes\6.3.1\usr\bin;$env:Path"
$env:SDKROOT = "$swiftRoot\Platforms\6.3.1\Windows.platform\Developer\SDKs\Windows.sdk"
$env:DEVELOPER_DIR = "$swiftRoot\Platforms\6.3.1\Windows.platform\Developer"

swift build --package-path ios --product AdaptiveCardsValidate
if ($LASTEXITCODE -ne 0) { throw 'Validator build failed' }
& .\ios\.build\x86_64-unknown-windows-msvc\debug\AdaptiveCardsValidate.exe
if ($LASTEXITCODE -ne 0) { throw 'Validator failed' }

swift build --package-path ios --product AdaptiveCardsCABIShared
if ($LASTEXITCODE -ne 0) { throw 'Shared C ABI build failed' }
dotnet build .\examples\embed-windows-csharp\AdaptiveCardsWpf\AdaptiveCardsWpf.csproj
if ($LASTEXITCODE -ne 0) { throw 'WPF build failed' }
& .\examples\embed-windows\c_abi\build.ps1 -Run
```

The package also contains Apple-only targets. Do not use an unscoped
`swift build` or `swift test --parallel` on Windows as the regression gate:
they pull those siblings into the graph and fail on Apple UI imports. Use the
supported validator here; separately qualify XCTest and full Apple/Android
validation on suitable hosts. Linux CI does not prove GTK GUI operation.

For interactive investigation, launch **one host at a time** from the repo
root so the process identity is unambiguous:

```pwsh
swift build --package-path ios --product AdaptiveCardsWindowsDemo
if ($LASTEXITCODE -ne 0) { throw 'Native demo build failed' }
$env:AC_DEFAULT_SAMPLE = 'windows-extras.json'
& .\ios\.build\x86_64-unknown-windows-msvc\debug\AdaptiveCardsWindowsDemo.exe

dotnet run --project .\examples\embed-windows-csharp\AdaptiveCardsWpf\AdaptiveCardsWpf.csproj
```

The native app needs the matching WindowsAppSDK runtime. The WPF app discovers
the built Swift DLL and Swift runtime directories in `App.OnStartup`; its
default sample is also windows-extras. Keep the repository's shared test-card
files available. Do not copy DLLs from an unrelated checkout or patch SwiftPM
dependency checkouts to make the demo start. The workflow documents its manual
Swift 6.3.2 installation workaround; do not replace it with an older generic
CI recipe during this task.

## Crash Status: Two Different Questions

### Historical static C-host crash: diagnosed and fixed

The Phase 14 investigation isolated an access violation in **any Codable
decode** from a C main, including a local Codable struct. Swift printing,
UTF-8 conversion, and `JSONSerialization` worked. The issue was missing Swift
protocol-conformance registration in the non-Swift executable startup.

The fix was to link the SDK's `swiftrt.obj` before the Swift object archive in
the C executable. Keep that input in the static C build. Merely adding Swift
runtime import libraries is not equivalent. The transcript records the full
render path succeeding locally and on CI run `25949581644`.

The SwiftPM-built dynamic DLL is a separate link path. Successful P/Invoke
renders do not require adding `swiftrt.obj` to the C# project. Do not diagnose
every subsequent UI failure as missing conformance registration without a
native stack and a failing decode probe.

### Current WPF page 2 -> page 3 failure: reproduced, not yet fixed

Near the end of the transcript, the user reports the running native demo
crashing when moving from page 2 to page 3. The attempted investigation
initially entered the wrong repository, then was interrupted. It did not
capture a stack or establish which host/control caused that navigation.

The prior continuation only checked builds, startup survival, and eight
successful DLL renders. Its conclusion that there was "nothing to fix" was
broader than the evidence. Consolidation found and reproduced a concrete
managed-host bug consistent with the user's sequence:

1. `RenderingNodeWalker.Build(string)` parses with `using var doc`, then calls
   `Build(doc.RootElement)`. The document is disposed when this method returns.
2. `BuildCarousel` saves borrowed `JsonElement` pages in `pageList`. The first
   render occurs while the document is alive and succeeds.
3. A later Next/Prev click calls `RenderPage`, which reads
   `pageList[current].GetProperty("content")` from the disposed document.
4. `HookActionClick` also captures borrowed action JSON, so Submit and OpenUrl
   payload reads have the same lifetime problem. Submit was independently
   reproduced without opening a browser.

An external **STA .NET 10 / UseWPF console probe** compiled the unchanged
repository walker as a linked source file, built a three-page IR carousel
with `selectedPageIndex: 1`, let `Build` return, and raised the Next button's
`Click` event. No Swift DLL was loaded. The captured failures were:

```text
Initial carousel: Page 2 of 3
Page 2 -> Page 3: ObjectDisposedException: Object name: 'JsonDocument'.
  RenderingNodeWalker.BuildCarousel -> RenderPage: line 594
  RenderingNodeWalker.BuildCarousel -> Next.Click: line 600
Submit after Build returns: ObjectDisposedException: Object name: 'JsonDocument'.
  RenderingNodeWalker.HookActionClick -> Submit payload read: line 674
Expected lifetime failures reproduced: 2/2
```

These source line numbers refer to the unchanged implementation baseline.
This proves a WPF managed-lifetime failure, not a new Swift Codable/runtime
failure or a crash in native `CarouselView`. No original crash dump exists
to prove it was the only failure the user experienced.

The current [windows-extras sample](../shared/test-cards/windows-extras.json)
has three carousel pages, `initialPage: 1` (displayed page 2), and `timer: 4000`.
The native Swift host implements auto-rotation; the WPF carousel is manual
Prev/Next only. Native manual buttons clamp at endpoints; its timer wraps.

**Minimal repair to test next, not applied in this handoff:** detach the JSON
root before creating any controls/callbacks, for example replacing
`Build(doc.RootElement)` with `Build(doc.RootElement.Clone())`. Retained child
elements then reference a document owned independently of the disposed parser
scope. Fix ownership at this boundary so both page and action callbacks are
covered; do not just catch and hide `ObjectDisposedException` in one button.

The local characterization project is at
`C:\temp\acwpf-navigation-repro\NavigationProbe.csproj`; the older DLL probe is
at `C:\temp\acwpf-probe\Probe.csproj`. Both are scratch diagnostics, not part
of the repository or required on another agent's machine. A portable regression
can link the walker source into a `net10.0-windows` console/test project with
`UseWPF=true` and run this core on an STA thread after construction returns:

```csharp
var walker = new RenderingNodeWalker();
var carousel = (StackPanel)walker.Build("""
    {"type":"carousel","selectedPageIndex":1,"pages":[
      {"content":[{"type":"text","string":"Page 1"}]},
      {"content":[{"type":"text","string":"Page 2"}]},
      {"content":[{"type":"text","string":"Page 3"}]}
    ]}
    """);
var navigation = (StackPanel)carousel.Children[1];
var next = (Button)navigation.Children[1];
next.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
// After the ownership fix, assert the header and body show Page 3 without throwing.
```

For the committed regression, also cover standard Submit, CompoundButton
Submit, nested carousel actions, repeated Next/Prev, endpoints, and replacing
the displayed card. Verify expected action payloads, not just absence of an
exception. Test URL handling without launching external processes.

## Continuation Priorities

1. Add a durable failing deferred-event regression and fix the WPF JSON
   ownership boundary above. Rerun it immediately, then the scoped Swift
   validator and WPF build. No Swift ABI change should be needed for this bug.
2. Verify the actual WPF windows-extras Page 2 -> Next -> Page 3 sequence,
   Submit actions, sample switching, and shutdown on an interactive desktop.
   A passing characterization probe after repair does not replace visual checks.
3. Independently exercise the native WinUI carousel, including timed 3 -> 1
   wraparound, Pause/resume, switching samples with a timer active, tab changes,
   and closing the window. Start in `CarouselView` / `TabSetView` inside
   [AdaptiveCardView.swift](../ios/Sources/AdaptiveCardsCrossUI/Rendering/AdaptiveCardView.swift).
   Diagnose any remaining native failure from its own stack, not the WPF fix.
4. Add a durable dynamic-DLL success/error/UTF-8/lifecycle smoke check. Reuse
   the P/Invoke declarations where possible. The static C test is not a
   substitute for DLL loading, managed callbacks, or deferred GUI events.
5. Reconcile the parked PR description and remaining acceptance gaps after
   the bug fix, with fresh CI evidence. Keep the PR draft until approved.

### Remaining acceptance and POC gaps

- Native Media is a text fallback; charts are simplified native views, not
  full visual parity for every chart type.
- WPF does not wire Input.Time, media playback, placeholder behavior, or
  native-style carousel auto-rotation/Pause. Its action logging is not full
  input-to-Submit data integration.
- Live UIA, Narrator, keyboard-only navigation, contrast, and focus need real
  validation. Phase 15 removed the unreliable UIA CI walker; it did not prove
  the original live-accessibility requirement satisfied.
- Full Apple/Android regression gates, dynamic consumer coverage, packaging,
  and runtime discovery/versioning need explicit qualification before release.
- The cosmetic static-link `LNK4217` warning is not the diagnosed decode or
  WPF navigation failure; investigate separately only if it becomes material.
- Keep changes additive and Windows-scoped. Do not relicense the inherited
  project, change unrelated iOS/Android targets, mass-update baselines, or
  rewrite the shared branch history as part of this repair.

## Source Transcript

The local source is
`C:\Users\hugogonzalez\Documents\Bucket\adaptivecards_winui_swiftui.md`.
It is not the earlier, nonexistent `Documents\transcriptbackup` path.
Useful local anchors: original brief at lines 1-120; Phase 15 summary at 4296;
Phase 16 start at 4352; the navigation-crash report at 4458; the repeated Phase
14 summary at 4599; the interrupted WPF resume at 4651. The transcript was
reviewed through its tail, a bounded heading/request index, and those targeted
sections, then reconciled with code, Git refs, CI metadata, and local probes.
Do not commit the raw transcript, temporary probes, dumps, or machine-local
backups to the public fork. This document retains the actionable conclusions
without making the next agent ingest the full transcript.