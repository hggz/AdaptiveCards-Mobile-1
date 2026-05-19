// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Note: `platforms` only narrows minimum versions for Apple platforms. Linux,
// Windows, Wasm, Android, and any other Swift-supported target build with no
// platform clause -- so we deliberately do NOT restrict to Apple here. The
// browser-DOM renderer lives in `AdaptiveCardsWebUI` (wasm-port branch); the
// swift-cross-ui / WinUI renderer lives in `AdaptiveCardsCrossUI`
// (windows-port branch). Both consume the same `RenderingNode` IR contract.

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
        // wasm-port: browser-DOM renderer scaffold for Swift -> WebAssembly
        // hosts. Parallel sibling to `AdaptiveCardsCrossUI` on the
        // windows-port branch. Both targets walk the same `RenderingNode` IR;
        // only the View layer differs (DOM here, WinUI / SwiftUI there).
        // Apple platforms continue to use the existing native renderers --
        // this target compiles down to an empty module unless
        // `canImport(JavaScriptKit)` is true, which today only happens under
        // the Swift WASM SDK build.
        .library(
            name: "AdaptiveCardsWebUI",
            targets: ["AdaptiveCardsWebUI"]),
    ],
    dependencies: [
        // wasm-port: thin Swift binding around the JS DOM. Provides
        // `JSObject`, `JSValue`, the `document` global, etc. Compiles only
        // against the WASM SDK target; absent on Apple / Linux native
        // builds, which is exactly why every use site is gated behind
        // `#if canImport(JavaScriptKit)`.
        .package(
            url: "https://github.com/swiftwasm/JavaScriptKit.git",
            from: "0.20.0"),
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
        .target(
            name: "ACCopilotExtensions",
            dependencies: ["ACCore"]),
        .target(
            name: "ACTeams",
            dependencies: ["ACCore", "ACRendering"]),
        // wasm-port: browser-DOM renderer target. JavaScriptKit is only
        // injected when the Swift WASM SDK is selected, so Apple / Linux
        // native builds compile this as an empty module via the
        // `#if canImport(JavaScriptKit)` gate in the source files.
        .target(
            name: "AdaptiveCardsWebUI",
            dependencies: [
                "ACCore",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ]),
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
