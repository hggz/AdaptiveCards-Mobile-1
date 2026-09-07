# Examples

Worked, runnable examples of consuming the windows-port Adaptive
Cards renderer from different host environments. Every example reads
the same `RenderingNode` IR produced by the same Swift renderer; the
only thing that varies is how the host links to it and how it draws
the IR.

| Directory | What it shows | Link model | Visual surface |
|---|---|---|---|
| [`embed-windows/`](embed-windows/README.md) | Minimal C consumer of the C ABI | Static link of `AdaptiveCardsCABI.lib` via `cl.exe` | Console / headless (text dump of the IR) |
| [`embed-windows-csharp/`](embed-windows-csharp/README.md) | .NET WPF host that walks the IR into native Windows controls | Dynamic load of `AdaptiveCardsCABIShared.dll` via P/Invoke | Real WPF `TextBlock` / `Button` / `TabControl` / `ProgressBar` etc. |

For the full Swift-cross-ui demo (`AdaptiveCardsWindowsDemo`) that
renders cards through the native swift-cross-ui WinUI backend, see
[`docs/windows-port.md`](../docs/windows-port.md) — it's the
canonical reference + has architectural context the examples assume.

## Picking an integration path

You're in this directory because you want to embed Adaptive Cards in
something other than a swift-cross-ui app. The three live paths in
this repo are:

1. **Pure Swift host (most ergonomic)** — depend on the
   `AdaptiveCardsWindowsEmbedded` product, get a typed
   `RenderingNode` tree and `ActionKind` callbacks. Skip the
   examples here; the `AdaptiveCardsWindowsDemo` target IS the
   worked example. Documented in
   [`docs/windows-port.md` § Embedding from a host app](../docs/windows-port.md#embedding-from-a-host-app).
2. **Native C / C++ host** — static link
   `AdaptiveCardsCABI.lib` against your existing `cl.exe` / clang
   build. See [`embed-windows/`](embed-windows/README.md).
3. **Non-Swift, non-C host** (.NET, Electron, Rust, Python,
   anything-with-FFI) — dynamic load
   `AdaptiveCardsCABIShared.dll`. See
   [`embed-windows-csharp/`](embed-windows-csharp/README.md) for
   a working .NET 10 WPF host as the template; the same
   `DllImport` shape works for any FFI-capable runtime.

Either C-ABI path produces the same IR JSON. Pick by your existing
toolchain, not by feature parity.
