// wasm-port: Phase W8 — `AdaptiveCardsWebDemo` standalone executable.
//
// Loads the curated reference card set from `SampleCardLibrary` when
// running under WASI with filesystem access (i.e. local `swift run` for
// validation), and embeds a fallback sample for browser deployment
// where the filesystem isn't reachable.
//
// Two run paths:
//   1. WASI without a DOM (e.g. `swift run --swift-sdk swift-6.3.2-RELEASE_wasm
//      AdaptiveCardsWebDemo` under wasmkit): walks the reference set,
//      prints filenames + a summary of the rendered IR tree per card.
//      This is the local "is the wasm well-formed?" smoke check we get
//      without standing up a browser.
//   2. WASI inside a browser (W10's `examples/embed-web-vanilla/` host
//      page or its successors): hydrates `<div id="ac-card-mount">`
//      with the rendered DOM. The host page is responsible for the JS
//      side of the wasi shim + JavaScriptKit bridge bootstrap.

import Foundation
import ACCore
import AdaptiveCardsRenderingIR

#if canImport(JavaScriptKit)
import JavaScriptKit
import AdaptiveCardsWebUI
#endif

/// Fallback card JSON embedded into the binary. Used when the reference
/// set isn't reachable via `SampleCardLibrary` — most notably under
/// browser-hosted WASI where the test-cards directory isn't on the
/// virtual filesystem. The contents mirror `simple-text.json` from the
/// shared reference set verbatim.
private let embeddedSampleJSON = """
{
  "type": "AdaptiveCard",
  "version": "1.6",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "body": [
    {
      "type": "TextBlock",
      "text": "Simple Card",
      "size": "Large",
      "weight": "Bolder"
    },
    {
      "type": "TextBlock",
      "text": "This is a simple adaptive card with basic text elements.",
      "wrap": true
    }
  ],
  "actions": [
    {
      "type": "Action.Submit",
      "title": "Submit"
    }
  ]
}
"""

@main
struct AdaptiveCardsWebDemoApp {

    static func main() {
        print("AdaptiveCardsWebDemo — wasm-port W8")
        print("Reference set: \(SampleCardLibrary.referenceSampleFilenames.count) cards")

        // Always parse the embedded sample so the WASI smoke path proves
        // the entire pipeline (parse -> render -> IR) end-to-end. This
        // path runs unconditionally; the browser branch below layers the
        // DOM mount on top.
        let parser = CardParser()
        guard let card = try? parser.parse(embeddedSampleJSON) else {
            FileHandle.standardError.write(Data(
                "[wasm-port] failed to parse embedded sample\n".utf8))
            return
        }
        let tree = Renderer().render(card: card)
        print("Embedded sample IR: \(summary(of: tree)) node(s).")

        // Reference-set walk (best-effort). Skips silently when the
        // filesystem isn't reachable (e.g. browser-hosted WASI without
        // the test-cards dir mounted).
        if let reference = try? SampleCardLibrary.loadReferenceSet() {
            for (name, card) in reference {
                let nodeTree = Renderer().render(card: card)
                print("- \(name): \(summary(of: nodeTree)) node(s)")
            }
        } else {
            print("(reference set not reachable — likely browser-hosted "
                + "WASI; embedded sample remains the source of truth.)")
        }

        #if canImport(JavaScriptKit)
        mountInBrowserIfPossible(card: tree)
        #endif
    }

    /// Recursive count of `RenderingNode`s in the tree, useful as a
    /// one-line smoke summary in the WASI path.
    private static func summary(of node: RenderingNode) -> Int {
        switch node {
        case let .verticalStack(_, c), let .horizontalStack(_, c):
            return 1 + c.map(summary(of:)).reduce(0, +)
        case let .accordion(panels):
            return 1 + panels.flatMap(\.content).map(summary(of:)).reduce(0, +)
        case let .table(headers, rows):
            let headerCount = (headers ?? [])
                .flatMap { $0 }.map(summary(of:)).reduce(0, +)
            let rowCount = rows.flatMap { $0 }
                .flatMap { $0 }.map(summary(of:)).reduce(0, +)
            return 1 + headerCount + rowCount
        case let .tabSet(tabs, _):
            return 1 + tabs.flatMap(\.content).map(summary(of:)).reduce(0, +)
        case let .carousel(pages, _, _):
            return 1 + pages.flatMap(\.content).map(summary(of:)).reduce(0, +)
        case let .list(_, items):
            return 1 + items.map(summary(of:)).reduce(0, +)
        default:
            return 1
        }
    }

    #if canImport(JavaScriptKit)
    /// When the host page provides a `<div id="ac-card-mount">`, render
    /// the parsed `card` IR into it via `AdaptiveCardsWebUI.DOMRenderer`.
    /// Wired with the default `WebActionRouter` so `Action.OpenUrl` goes
    /// through `window.open` and `Action.Submit` lands in DevTools as a
    /// `console.warn("ac:submit", …)` record.
    private static func mountInBrowserIfPossible(card: RenderingNode) {
        let documentValue = JSObject.global.document
        guard let document = documentValue.object else { return }
        let mountValue = document.getElementById!("ac-card-mount")
        guard let mount = mountValue.object else {
            // No mount point: the WASI smoke path above already printed
            // the per-card summary, so this is a silent no-op rather
            // than an error.
            return
        }
        let router = WebActionRouter()
        let renderer = DOMRenderer(document: document, dispatcher: router)
        renderer.render(card, into: mount)
    }
    #endif
}
