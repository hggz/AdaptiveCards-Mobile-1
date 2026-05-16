# Draft PR description — `windows-port`

> **Status: parked.** Open the PR by copying this content into a new
> Pull Request on GitHub once the user gives the go. This file lives
> on-branch so reviewers can preview the body without clicking Open.

---

## Title

`feat(windows): native Windows renderer for AdaptiveCards-Mobile via swift-cross-ui`

## Description

This PR adds a Windows-native renderer for AdaptiveCards-Mobile on top
of `swift-cross-ui`'s WinUI backend. It is **strictly additive** —
zero changes to `Sources/AC*` (the existing iOS / SwiftUI renderer),
zero changes to `android/`, and zero changes to the shared parity
docs (`PARITY_MATRIX.md`, `RENDERING_PARITY_CHECKLIST.md`) which are
iOS-vs-Android by design.

The Windows port lives in its own targets:

| Target | What it is |
|---|---|
| `AdaptiveCardsCrossUI` | Library: `swift-cross-ui`-backed renderer, IR (`RenderingNode`), `Renderer`, `AdaptiveCardView`, `A11yDump`. |
| `AdaptiveCardsWindowsEmbedded` | Library: stable embedding facade (`AdaptiveCardHost`) — pure-data API for non-Swift hosts. |
| `AdaptiveCardsCABI` | Static lib: `@_cdecl` C-ABI shim around `AdaptiveCardHost`. |
| `AdaptiveCardsWindowsDemo` | Executable: WinUI demo window that walks all reference cards. |
| `AdaptiveCardsValidate` | Executable: headless validation harness; 93/93 deterministic checks. |

See `docs/windows-port.md` for the full architecture + per-phase
status table.

## What's in scope

All seven non-trivial AdaptiveCards 1.6 element families that the
SwiftUI renderer handles, now rendered through the Windows port too:

* TextBlock, RichTextBlock, Image (incl. URL-loaded posters), Container,
  ColumnSet, FactSet, CodeBlock, Table, ProgressBar, Spinner,
  Accordion, Rating (read-only display).
* Inputs: Input.Text, Input.Number, Input.Toggle, Input.ChoiceSet,
  Input.Date, Input.Time, Input.Rating (interactive, contributes to
  the Action.Submit payload).
* Charts: DonutChart, BarChart, LineChart, PieChart (text-summary
  fallback with per-datum colour via `.foregroundColor`).
* TabSet (with live tab selection via `@State`).
* Carousel (live page selection + WCAG-2.2.2-compliant
  Pause/Resume button when `autoAdvanceMs` is set).
* List (default / bulleted / numbered styles).
* CompoundButton (title + subtitle + icon hint, wired to either
  Action.Submit or Action.OpenUrl).
* Media (audio / video). swift-cross-ui has no native AV widget, so
  the View renders a text summary with poster + caption + per-source
  mimeType+url rows; A11yDump flags `MISSING_ALT` when altText is
  absent.

`UNRENDERED` count across the reference set: **0**.

## What it does NOT do

* No changes to the iOS or Android renderers.
* No changes to `shared/test-cards/*.json` other than adding one new
  card `windows-extras.json` that consolidates Chart/TabSet/Carousel/
  List/Media/CompoundButton/Input.Rating coverage in a single
  reference (Phase 17 introduced it; Phase 18-24 extended it as new
  elements landed).
* No Carousel auto-rotation without a user-visible Pause control.
* No image-based chart rendering — datums render as labelled bar
  rows with optional `.foregroundColor`. Reasoning: text rendering is
  what assistive tech narrates anyway, and the bar visualisation
  conveys magnitude without needing canvas drawing primitives that
  swift-cross-ui's WinUI backend doesn't yet expose.

## Validation gate

Three reading the same baseline files at
`Sources/AdaptiveCardsValidate/{Snapshots,A11yBaselines}/`:

1. **Windows / build + AdaptiveCardsValidate (REQUIRED)** —
   `AdaptiveCardsValidate.exe` runs 93 checks: renderer unit
   mappings, submit-payload merge, reference-card IR snapshot
   diffs, broad parse coverage across `shared/test-cards/`, C-ABI
   surface, and IR-level a11y baselines.
2. **Linux / AdaptiveCardsCrossUI compiles** — runs
   `swift run AdaptiveCardsValidate` so IR snapshot + a11y baseline
   drift is caught on Linux too. Same code, same baselines.
3. **macOS / existing iOS package compiles** — confirms the
   `swift-tools-version` bump didn't regress the existing iOS
   renderer's manifest. The `AdaptiveCardsCrossUITests` XCTest
   target's `IRBaselineSnapshotTests` runs the same baseline diffs
   on macOS when `swift test --parallel` is invoked (the
   `ios-tests.yml` workflow exercises this on `main` /
   `feat/**` / `copilot/**`).

Plus two visual gates:

4. **Windows / demo launch smoke (per reference card)** — spawns
   `AdaptiveCardsWindowsDemo.exe` with each reference card
   preselected, captures the window via PrintWindow, pixel-diffs
   against committed PNG baselines at ≤2% drift tolerance.
5. **Windows / C-ABI example (cl.exe link + run)** — links
   `main.c` against the static `AdaptiveCardsCABI.lib`, runs the
   produced exe, verifies every public C function (including
   `ac_host_render_json` which parses + renders Adaptive Card JSON
   from C).

All five jobs are hard-required (no `continue-on-error`).

Final reference-set violation totals:
* `MISSING_LABEL: 0`
* `MISSING_ALT: 1` (the cat image in `containers.json` — preserved
  as a stable signal that the violation detector works)
* `UNRENDERED: 0`

## Commit history

Single chain on `windows-port`, ~25 phased commits each containing
one feature. The full sequence is in `git log windows-port`. Highlights:

* Phase 15 (`82b126e`) — replace flaky live-UIA walker with the
  IR-level a11y baseline gate.
* Phase 16 (`c2078ce`) — Chart, TabSet, CompoundButton.
* Phase 17 (`80d807f`) — introduce `windows-extras.json` reference card.
* Phase 18-20 — Carousel, List, Media.
* Phase 21 (`d7fc23d`) — Input.Rating interactive; UNRENDERED drops
  from 1 → 0.
* Phase 22 (`be16e2d`) — live tab + page switching via dedicated
  sub-View structs.
* Phase 23 (`1a3a09f`) — Carousel auto-rotation timer + WCAG Pause
  button.
* Phase 24 (`ddea0fe`) — Chart datum colour rendering.
* Phase 25 (`118d3c7`) — Cross-platform IR baseline gate via XCTest +
  Linux validator step.
* Phase 26 (this PR description) — Pre-PR housekeeping.

## Cross-Platform Parity Checklist (filled per upstream template)

The upstream `PULL_REQUEST_TEMPLATE.md` is shaped for iOS-vs-Android
features. The windows-port doesn't fit that frame cleanly; here's how
each box maps:

* [n/a] **iOS Implementation** — the existing iOS renderer is
  unchanged; this PR doesn't add any iOS-rendered feature.
* [n/a] **Android Implementation** — same: untouched.
* [x] **Tests Added** — `AdaptiveCardsValidate` (93 checks),
  `IRBaselineSnapshotTests` (3 XCTest cases), demo smoke + C-ABI
  example end-to-end.
* [n/a] **Schema Updated** — schema is already 1.6-complete in
  `ACCore`; this PR only consumes existing model types.
* [x] **PARITY_MATRIX.md Updated** — intentionally NOT updated
  (Windows status lives in `docs/windows-port.md` per the
  document's own scope; the iOS-vs-Android matrix is unchanged).
* [x] **Shared Test Card** — `shared/test-cards/windows-extras.json`
  added.
* [x] **Parity Gate Passes** — windows-port-ci.yml all 5 jobs green
  on `HEAD`.

## Testing Checklist

* [x] **Unit Tests** — `AdaptiveCardsValidate` 93/93,
  `IRBaselineSnapshotTests` 3 cases.
* [x] **Integration Tests** — windows-render-smoke + windows-c-example.
* [x] **All Tests Pass** — last green run: see latest
  windows-port-ci.yml run on HEAD.
* [x] **Test Coverage** — every renderer code path has a baseline
  diff; a11y dump covers every IR case.
* [x] **Manual Testing** — `AdaptiveCardsWindowsDemo.exe` exercised
  against all 8 reference cards on a Windows DevBox.
* [x] **Edge Cases** — `edge-empty-card.json` (empty body),
  defensive clamps for `tabSet.selectedTabIndex` /
  `carousel.selectedPageIndex` out of range, malformed hex colour
  string in `parseHexColor`.

## Accessibility

* [x] **Screen Reader** — every focusable element is a real `Button`
  with a string label; `A11yDump` records role + accessible name +
  flags for every IR case. `Carousel` Pause button satisfies WCAG
  2.2.2 explicitly.
* [n/a] **Dynamic Type** — swift-cross-ui doesn't expose system font
  scaling on WinUI today; this is a swift-cross-ui upstream issue.
* [n/a] **Touch Targets** — Windows is mouse + keyboard first; no
  spec lists a minimum touch target.
* [x] **Contrast** — `ChartDatum.color` is the only user-controlled
  colour and the View only applies it to the bar segment (not
  label or value text) so the rest of the row keeps default
  foreground contrast.
* [x] **Semantic Labels** — every input field's label flows into the
  rendered `Text(fieldLabel(...))`; missing labels surface as
  `MISSING_LABEL` in the a11y dump (`testAggregateA11yViolationBudget`
  fails CI if any new violation appears).

## Performance

* [x] **No Performance Regression** — the windows-port targets are
  all additive; existing iOS / Android performance is unaffected.
* [x] **Memory Leaks** — IR is value-type (`Equatable` enum); no
  reference cycles possible in the pure-data path. The View layer
  uses swift-cross-ui's `@State` / `@Binding` lifecycle which
  cleans up via the framework.
* [x] **Large Card Handling** — `windows-extras.json` is the most
  complex test card (Chart + TabSet + CompoundButton + Carousel +
  List + Media + Input.Rating) and renders + diffs cleanly.

## Security

* [x] **No Security Vulnerabilities** — no network code; URL fields
  are passed verbatim to swift-cross-ui's image loader (existing
  upstream behaviour).
* [x] **Input Validation** — every submit value runs through
  `SubmitPayload.merge` which serialises only known field
  identifiers.
* [x] **XSS Prevention** — N/A; no HTML rendering.
* [x] **Secrets** — none in code.

## Breaking Changes

None. The PR is additive: it adds new targets and a new branch CI
workflow without modifying existing iOS / Android source.

## Screenshots

See `Sources/AdaptiveCardsValidate/Screenshots/*.png` for the
committed PrintWindow baselines of each reference card. The
`windows-render-smoke` CI job uploads fresh captures as the
`windows-render-smoke.zip` artifact on every run.

## Related Issues

n/a — this is the initial Windows port landing.

## Additional Notes

* SSH push from the `hggz` account only (per the agent
  customization rules in `agents/SwiftyScript.agent.md`); never
  from the corporate AAD account.
* `windows-port-ci.yml` is gated to `push: branches: [windows-port]`
  + `workflow_dispatch`, so existing `main`-branch CI is unaffected.
* `docs/windows-port.md` is the single source of truth for the
  Windows port's architecture and status.
