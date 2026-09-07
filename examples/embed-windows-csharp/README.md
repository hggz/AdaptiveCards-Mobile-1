# Adaptive Cards · WPF host (P/Invoke POC)

A minimal C# .NET 10 WPF app that consumes
`AdaptiveCardsCABIShared.dll` (the dynamic-library variant of the
Adaptive Cards C ABI shipped by this repo) via P/Invoke and renders
the resulting IR JSON to **real WPF controls** — `TextBlock`,
`Button`, `CheckBox`, `ComboBox`, `ProgressBar`, `Expander`, `Grid`,
`TabControl`, `Image`, etc.

No SwiftUI, no swift-cross-ui in this process. The Swift side does
parsing + IR construction; C# does everything visual. This is the
integration model for **any non-Swift Windows host** — WPF, WinUI 3,
WinForms, Electron via node-ffi, Rust via libloading, Python via
ctypes. Substitute the WPF control mapping for your framework's
equivalents and the rest of the contract is the same.

## What it does

1. On startup it walks up from `AppContext.BaseDirectory` looking for
   the repo's Swift build output
   (`ios/.build/x86_64-unknown-windows-msvc/debug/AdaptiveCardsCABIShared.dll`)
   and the Swift runtime bin dir
   (`%USERPROFILE%\AppData\Local\Programs\Swift\Runtimes\<version>\usr\bin`),
   then `AddDllDirectory`s both so the Win32 loader can resolve the
   DLL plus its `swiftCore.dll` / `swiftFoundation.dll` / etc.
   transitive deps.
2. Calls `ac_host_create(nil)` to spin up a Swift `AdaptiveCardHost`.
3. Calls `ac_host_backend_identifier(host)` and prints it (should
   say `winui`).
4. On every sample-picker selection: reads the chosen
   `shared/test-cards/*.json`, calls
   `ac_host_render_json(host, cardJson)`, parses the returned IR
   JSON with `System.Text.Json`, and walks it into a WPF control tree
   via `RenderingNodeWalker`.
5. On `Action.OpenUrl` button clicks: opens the URL in the system
   default browser via `Process.Start(UseShellExecute = true)`.
6. On window close: calls `ac_host_destroy(host)`.

## Build + run

From the repo root, in a Visual Studio Developer PowerShell session
(so the Swift toolchain can find `link.exe` / `lib.exe`):

```pwsh
# 1. Build the Swift dynamic library + its transitive deps.
cd ios
swift build --product AdaptiveCardsCABIShared
cd ..

# 2. Build + run the C# WPF host. It auto-discovers the .dll.
dotnet run --project examples/embed-windows-csharp/AdaptiveCardsWpf
```

The window opens with `windows-extras.json` preselected; the picker
switches between the 8 reference cards.

## What's mapped (POC scope)

| IR `"type"` | WPF control |
|---|---|
| `text` / `richRun` | `TextBlock` with font size + weight + wrap + italic + underline + strikethrough |
| `image` | `Image` via `BitmapImage(UriSource)` |
| `verticalStack` / `horizontalStack` | `StackPanel` |
| `facts` | `Grid` (2 columns) |
| `code` | `TextBlock` in `Consolas` |
| `textField` / `numberField` | `TextBox` |
| `toggleField` | `CheckBox` |
| `choiceField` | `ComboBox` |
| `progressBar` | `ProgressBar` |
| `spinner` | `ProgressBar IsIndeterminate=True` |
| `accordion` | `Expander` |
| `table` | `Grid` |
| `rating` | `TextBlock` with ★ / ☆ |
| `ratingField` | row of `Button`s with click-to-set behaviour |
| `dateField` | `DatePicker` |
| `list` (default / bulleted / numbered) | `StackPanel` with marker prefix |
| `chart` | `Grid` per datum with label + `ProgressBar` (with hex `Foreground` if present) + value |
| `tabSet` | `TabControl` |
| `carousel` | `StackPanel` with prev / next buttons that rebuild the body |
| `compoundButton` | `Button` wrapping title + subtitle `StackPanel` |
| `button` | `Button` |
| `unsupported` | gray `[Unsupported]` `TextBlock` |
| anything else | gray `[Unhandled in WPF POC]` `TextBlock` |

`textField` placeholder behaviour, `Input.Time`, `media` audio/video
playback, and the WCAG-style Pause control for auto-rotating
carousels are **NOT** wired in this POC — they're orthogonal to the
"can it embed" question. The IR carries the values; a production
host adds the controls.

## Why a separate dynamic library product?

The original `AdaptiveCardsCABI` ships as a **static** library
because the existing `windows-c-example` job links it directly into
`cl.exe`'s output (single-image executable, all of swiftCore /
swiftFoundation statically resolved). C# / .NET can't statically
link Swift archives, so the `AdaptiveCardsCABIShared` product
re-uses the same target with `type: .dynamic` to produce a real
Windows DLL whose `@_cdecl` symbols are auto-exported.

Verified via `dumpbin /exports`:

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

## Headless / CI

The WPF POC is **not** wired into `windows-port-ci.yml` because it
needs an interactive desktop session to render. The existing
`windows-c-example` job already gates the same C ABI surface end-to-
end via `cl.exe` link + run, so the contract this POC consumes is
already CI-proven.
