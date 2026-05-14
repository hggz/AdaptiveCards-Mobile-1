//
//  AdaptiveCardHost.swift
//  AdaptiveCardsWindowsEmbedded — windows-port
//
//  Stable embedding facade. A host application (Win32, WinUI, or any
//  future swift-cross-ui-based desktop app) links against
//  `AdaptiveCardsWindowsEmbedded`, instantiates `AdaptiveCardHost`, and:
//
//    1. Parses card JSON via `host.parse(json:)`.
//    2. Either consumes the resulting `RenderingNode` tree directly
//       (for non-swift-cross-ui hosts) OR places a SwiftCrossUI view
//       returned by the `AdaptiveCardsCrossUI` library's `AdaptiveCardView`
//       wrapper into its own layout.
//    3. Receives action callbacks via `host.onAction`.
//
//  This module deliberately does NOT depend on swift-cross-ui — it is the
//  pure-data half of the embedding API so it works for any host language
//  through a future C-ABI shim. The view-construction half stays in
//  `AdaptiveCardsCrossUI`.
//
//  The C-ABI shim (planned, not implemented in v1) will sit underneath
//  this facade as `examples/embed-windows/c_abi/`. See
//  `docs/windows-port.md` for the sketched header layout.
//

import Foundation
import ACCore
import AdaptiveCardsCrossUI

/// Embedding facade for non-Swift hosts (and Swift hosts that prefer a
/// stable, non-generic API).
public final class AdaptiveCardHost {

    /// JSON for the Adaptive Cards HostConfig. The shipped renderer
    /// ignores most fields today; full HostConfig honoring lands in v2.
    public let hostConfigJSON: String

    /// Callback invoked when any rendered action fires. The callback's
    /// argument is the `RenderingNode.ActionKind` tag so the host can
    /// dispatch on `.submit` vs `.openUrl` vs `.execute` etc. without
    /// importing the full ACCore action model.
    public var onAction: ((RenderingNode.ActionKind) -> Void)?

    public init(hostConfigJSON: String = "{}") {
        self.hostConfigJSON = hostConfigJSON
    }

    /// Parse Adaptive Card JSON into the canonical `AdaptiveCard` model.
    public func parse(json: String) throws -> AdaptiveCard {
        try CardParser().parse(json)
    }

    /// One-shot: parse JSON and produce a renderer tree ready for
    /// either headless inspection or `AdaptiveCardView` consumption.
    public func renderTree(json: String) throws -> RenderingNode {
        let card = try parse(json: json)
        return Renderer().render(card: card)
    }

    /// Convenience: render an already-parsed card directly.
    public func renderTree(card: AdaptiveCard) -> RenderingNode {
        Renderer().render(card: card)
    }

    /// Serialise a `RenderingNode` tree as canonical JSON. Useful for
    /// non-Swift hosts that prefer to consume the rendering plan over
    /// the wire rather than walk a Swift-only enum.
    public func renderJSON(json: String) throws -> String {
        let tree = try renderTree(json: json)
        return try tree.snapshotJSON()
    }

    /// Surface useful identifiers about the active embed for logging.
    public var backendIdentifier: String { WindowsCardHost.backendIdentifier }
}
