//
//  WindowsCardHost.swift
//  AdaptiveCardsCrossUI — windows-port scaffold
//
//  Placeholder for the Windows-native rendering host. The eventual surface:
//
//      let host = WindowsCardHost(hostConfig: .default)
//      host.onSubmitAction = { action in ... }
//      let window = host.render(card: parsedCard)
//
//  v1 of this target only exists to prove that:
//    1. swift-cross-ui resolves and links on Windows from this package, and
//    2. ACCore (the parser / ObjectModel) is reachable from a non-Apple target.
//
//  The actual renderer is intentionally NOT implemented in this first commit.
//  See docs/windows-port.md (added in a later step) for the full mapping plan.
//

import Foundation
import ACCore

#if canImport(SwiftCrossUI)
import SwiftCrossUI
#endif

/// Placeholder host for rendering Adaptive Cards on platforms backed by
/// `swift-cross-ui` (Windows WinUI, future Linux GTK, etc.).
///
/// This type currently exposes only an initializer so the target compiles
/// end-to-end on every platform Swift supports. Renderer wiring lands in
/// subsequent commits on the `windows-port` branch.
public struct WindowsCardHost: Sendable {

    /// The host config used to render cards. Reused verbatim from `ACCore`,
    /// the same Foundation-only model the SwiftUI renderer consumes.
    public let hostConfigJSON: String

    /// Create a host with the given Adaptive Cards HostConfig JSON payload.
    /// The payload is *not* parsed in v1; the parameter is reserved so the
    /// API shape is stable across the upcoming renderer work.
    public init(hostConfigJSON: String = "{}") {
        self.hostConfigJSON = hostConfigJSON
    }

    /// Identifier describing which cross-UI backend this build is targeting.
    /// Useful for smoke tests and CI artifact labelling.
    public static var backendIdentifier: String {
        #if os(Windows)
        return "winui"
        #elseif os(Linux)
        return "gtk"
        #elseif os(macOS)
        return "appkit"
        #elseif os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
        return "uikit"
        #else
        return "unknown"
        #endif
    }
}
