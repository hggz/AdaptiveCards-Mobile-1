# Adaptive Cards · C host (static link)

A minimal C-language consumer of `AdaptiveCardsCABI.lib` (the
static-library variant of the windows-port C ABI). Demonstrates the
**static-link** integration path: a single `cl.exe`-built executable
that statically pulls in the Swift renderer + the Swift runtime, with
no external `.dll` dependencies at run time.

If you want **dynamic** load (P/Invoke from .NET, Electron, etc.) the
sibling [`../embed-windows-csharp/`](../embed-windows-csharp/README.md)
example uses the same C ABI through the dynamic-library product
`AdaptiveCardsCABIShared.dll`. Both paths reach the same Swift entry
points.

## What it does

`main.c` is ~80 lines that walk through every public C entry point:

1. `ac_host_create(NULL)` to spin up an `AdaptiveCardHost`.
2. `ac_host_backend_identifier(host)` to confirm the renderer
   detected the runtime backend (prints e.g. `winui`).
3. `ac_host_set_action_callback(host, cb, user_data)` to register a
   C function that the Swift side calls when Adaptive Card actions
   fire.
4. `ac_host_render_json(host, card_json)` to parse + render an
   inline `simple-text.json`-equivalent card; prints the produced
   `RenderingNode` IR JSON.
5. `ac_host_fire_action(host, AC_KIND_OPEN_URL, "https://example.com")`
   to drive the callback synchronously and confirm the C ↔ Swift
   round-trip works.
6. `ac_host_destroy(host)` to release everything.

CI exercises this exact recipe via the `windows-c-example` job in
[`.github/workflows/windows-port-ci.yml`](../../.github/workflows/windows-port-ci.yml).

## Build + run

From a **Visual Studio Developer PowerShell** (so `cl.exe` /
`lib.exe` / `link.exe` are on PATH; the Swift toolchain on Windows
also needs MSVC to link Swift runtime):

```pwsh
# From the repo root:
cd examples\embed-windows\c_abi
.\build.ps1 -Run
```

`build.ps1` is a single deterministic script. It does, in order:

1. `swift build --target AdaptiveCardsCABI` to compile the Swift
   static target's `.o` files.
2. Pack the produced object files
   (`AdaptiveCardsCABI` + `AdaptiveCardsWindowsEmbedded` +
   `AdaptiveCardsCrossUI` + `ACCore`) into a single
   `AdaptiveCardsCABI.lib` via `lib.exe`.
3. `cl.exe /Fe:host-demo.exe main.c …` linking against the
   produced `.lib` + the Swift runtime libraries
   (`swiftCore.lib`, `swiftFoundation.lib`, etc.) shipped with the
   Swift toolchain.
4. With `-Run`, executes the resulting `host-demo.exe`.

Drop the `-Run` flag to just produce the binary.

## Why `swiftrt.obj` is the first link input

A subtle gotcha worth highlighting because it'll cost you an
afternoon otherwise. `swiftrt.obj` (note the `.obj`, not `.lib`)
contains the static initializer that walks the `__swift5_proto*`
COFF sections and registers protocol conformance descriptors with
the Swift runtime. **Swift's own executable startup links it
automatically; C hosts MUST do so explicitly.**

Without `swiftrt.obj` linked **first**, every `JSONDecoder` /
`Codable` call from C-hosted Swift code crashes with
`E_ACCESSVIOLATION` (0xC0000005) on the first decode. The error is
genuinely cryptic — the decode appears to succeed up to the point
where it tries to look up a conformance for a `Decodable` type —
so the `build.ps1` script pins this with a comment and CI gates it.

If you write your own build recipe for this ABI, put
`%LOCALAPPDATA%\Programs\Swift\Platforms\<ver>\Windows.platform\Developer\SDKs\Windows.sdk\usr\lib\swift\windows\x86_64\swiftrt.obj`
as the first input to `link.exe` / `cl.exe`'s `/link` step.

## C ABI header

The header your host includes is
[`adaptive_cards.h`](adaptive_cards.h) — keep it in lock-step with
[`ios/Sources/AdaptiveCardsCABI/CABI.swift`](../../ios/Sources/AdaptiveCardsCABI/CABI.swift),
which is the source of truth for every signature and the
documented memory contract.

Quick contract reminders:

* `ac_host_create` returns an opaque `ACHost*`; pair with one
  `ac_host_destroy`.
* Functions returning `char*` allocate with `malloc`. The host
  **must** `ac_free` the returned pointer.
* `ac_last_error()` returns a static-lifetime `const char*` that
  the Swift side owns; **do not** free it.
* Strings are UTF-8 on the wire.
* Action callbacks fire on the same thread that produced them; if
  your host has a UI thread, marshal yourself.

## What's NOT in this example

The C example produces no UI. It prints IR JSON to stdout and exits.
The two visual hosts are:

* The Swift demo `AdaptiveCardsWindowsDemo`
  ([`ios/Sources/AdaptiveCardsWindowsDemo/`](../../ios/Sources/AdaptiveCardsWindowsDemo/)) —
  swift-cross-ui + WinUI 3 backend.
* The .NET WPF host
  ([`../embed-windows-csharp/`](../embed-windows-csharp/README.md)) —
  walks the IR into real WPF controls via P/Invoke.

Both are layered on top of the same Swift renderer + IR this C host
talks to.
