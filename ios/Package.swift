// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Note: `platforms` only narrows minimum versions for Apple platforms. Linux,
// Windows, Android, and any other Swift-supported target build with no platform
// clause — so we deliberately do NOT restrict to Apple here. The cross-platform
// renderer lives in `AdaptiveCardsCrossUI` (windows-port branch).

import PackageDescription

let package = Package(
    name: "AdaptiveCards",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ACCore",
            targets: ["ACCore"]),
        .library(
            name: "ACRendering",
            targets: ["ACRendering"]),
        .library(
            name: "ACInputs",
            targets: ["ACInputs"]),
        .library(
            name: "ACActions",
            targets: ["ACActions"]),
        .library(
            name: "ACAccessibility",
            targets: ["ACAccessibility"]),
        .library(
            name: "ACTemplating",
            targets: ["ACTemplating"]),
        .library(
            name: "ACMarkdown",
            targets: ["ACMarkdown"]),
        .library(
            name: "ACCharts",
            targets: ["ACCharts"]),
        .library(
            name: "ACFluentUI",
            targets: ["ACFluentUI"]),
        .library(
            name: "ACCopilotExtensions",
            targets: ["ACCopilotExtensions"]),
        .library(
            name: "ACTeams",
            targets: ["ACTeams"]),
        // windows-port: cross-platform renderer built on swift-cross-ui.
        // Active on Windows (WinUI backend) and any future non-Apple desktop
        // target. Apple platforms keep the existing SwiftUI renderer.
        .library(
            name: "AdaptiveCardsCrossUI",
            targets: ["AdaptiveCardsCrossUI"]),
        // windows-port: stable embedding facade for hosts that don't want
        // to depend on swift-cross-ui directly. Pure-data API: parse JSON
        // -> AdaptiveCard model -> RenderingNode tree (or JSON). The host
        // is responsible for placing the rendering into its own widget
        // tree; the swift-cross-ui implementation lives in
        // AdaptiveCardsCrossUI for hosts that want it.
        .library(
            name: "AdaptiveCardsWindowsEmbedded",
            type: .static,
            targets: ["AdaptiveCardsWindowsEmbedded"]),
        // windows-port: C-callable surface that wraps
        // AdaptiveCardsWindowsEmbedded with `@_cdecl` exports. Hosts
        // written in C / C++ / any-language-with-C-FFI link this .lib
        // alongside the Swift runtime to consume Adaptive Cards
        // headlessly. See examples/embed-windows/c_abi/adaptive_cards.h
        // for the host-facing header.
        .library(
            name: "AdaptiveCardsCABI",
            type: .static,
            targets: ["AdaptiveCardsCABI"]),
    ],
    dependencies: [
        // windows-port: SwiftUI-like cross-platform UI substrate. Used only by
        // the AdaptiveCardsCrossUI target on non-Apple platforms. iOS / macOS
        // continue to render via the existing native SwiftUI path in
        // ACRendering and friends.
        .package(url: "https://github.com/stackotter/swift-cross-ui.git", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "ACCore",
            dependencies: []),
        .target(
            name: "ACAccessibility",
            dependencies: ["ACCore"]),
        .target(
            name: "ACTemplating",
            dependencies: ["ACCore"]),
        .target(
            name: "ACMarkdown",
            dependencies: []),
        .target(
            name: "ACCharts",
            dependencies: ["ACCore", "ACFluentUI"]),
        .target(
            name: "ACFluentUI",
            dependencies: []),
        .target(
            name: "ACInputs",
            dependencies: ["ACCore", "ACAccessibility"]),
        .target(
            name: "ACActions",
            dependencies: ["ACCore", "ACAccessibility"]),
        .target(
            name: "ACRendering",
            dependencies: ["ACCore", "ACInputs", "ACActions", "ACAccessibility", "ACMarkdown", "ACCharts", "ACFluentUI"]),
        // windows-port: cross-platform renderer scaffold. Pure Foundation +
        // swift-cross-ui. Depends on ACCore for the AdaptiveCard ObjectModel
        // and parsing pipeline (Foundation-only, portable).
        .target(
            name: "AdaptiveCardsCrossUI",
            dependencies: [
                "ACCore",
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(
                    name: "WinUIBackend",
                    package: "swift-cross-ui",
                    condition: .when(platforms: [.windows])),
            ]),
        .testTarget(
            name: "AdaptiveCardsCrossUITests",
            dependencies: ["AdaptiveCardsCrossUI"]),
        // windows-port: standalone Windows demo executable. Loads sample
        // cards from `shared/test-cards/` via ACCore and renders them with
        // the AdaptiveCardsCrossUI renderer on top of swift-cross-ui's
        // DefaultBackend (WinUI on Windows). Gated to .windows so we don't
        // try to ship a runnable .exe on platforms where swift-cross-ui
        // doesn't have a working default backend chain wired in this
        // package.
        .executableTarget(
            name: "AdaptiveCardsWindowsDemo",
            dependencies: [
                "AdaptiveCardsCrossUI",
                "ACCore",
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ]),
        // windows-port: headless validation harness. Runs the same
        // assertions as the XCTest suite but as a plain `main()` so it
        // works on any platform that compiles AdaptiveCardsCrossUI,
        // including Windows where `swift test` insists on building every
        // Apple-only sibling target. Exits non-zero on failure.
        //
        // Validation loop:
        //   swift run AdaptiveCardsValidate
        //
        // Output line per check, summary at the end. The Windows CI job
        // calls this binary; macOS / Linux CI may additionally invoke
        // `swift test --filter AdaptiveCardsCrossUITests` for richer XCTest
        // reporting.
        .executableTarget(
            name: "AdaptiveCardsValidate",
            dependencies: [
                "AdaptiveCardsCrossUI",
                "AdaptiveCardsWindowsEmbedded",
                "AdaptiveCardsCABI",
                "ACCore",
            ]),
        // windows-port: stable embedding facade (see library product
        // declaration above for details).
        .target(
            name: "AdaptiveCardsWindowsEmbedded",
            dependencies: ["AdaptiveCardsCrossUI", "ACCore"]),
        // windows-port: C-callable surface (@_cdecl shim) wrapping the
        // embedding facade. Produces a static .lib that non-Swift hosts
        // link alongside the Swift runtime. Header lives at
        // examples/embed-windows/c_abi/adaptive_cards.h.
        .target(
            name: "AdaptiveCardsCABI",
            dependencies: [
                "AdaptiveCardsWindowsEmbedded",
                "AdaptiveCardsCrossUI",
                "ACCore",
            ]),
        .target(
            name: "ACCopilotExtensions",
            dependencies: ["ACCore"]),
        .target(
            name: "ACTeams",
            dependencies: ["ACCore", "ACRendering"]),
        .testTarget(
            name: "ACCoreTests",
            dependencies: ["ACCore"],
            resources: [.copy("Resources")]),
        .testTarget(
            name: "ACRenderingTests",
            dependencies: ["ACRendering"]),
        .testTarget(
            name: "ACInputsTests",
            dependencies: ["ACInputs"]),
        .testTarget(
            name: "ACTemplatingTests",
            dependencies: ["ACTemplating"]),
        .testTarget(
            name: "ACMarkdownTests",
            dependencies: ["ACMarkdown"]),
        .testTarget(
            name: "ACChartsTests",
            dependencies: ["ACCharts"]),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["ACCore"],
            resources: [.copy("Resources")]),
        .testTarget(
            name: "VisualTests",
            dependencies: ["ACCore", "ACRendering", "ACInputs", "ACActions", "ACAccessibility", "ACMarkdown", "ACCharts", "ACFluentUI"]),
    ]
)
