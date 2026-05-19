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
        // wasm-port: shared, platform-agnostic Rendering IR. Pure Foundation
        // + ACCore. Hosts the `RenderingNode` tree types, the `Renderer`,
        // the `A11yDump` walker, the `SubmitPayload` encoder, and the
        // `SampleCardLibrary` reference-card index. Cherry-picked from the
        // windows-port branch (AdaptiveCardsCrossUI/Rendering/*) so that
        // wasm-port can sit on the same IR contract as windows-port without
        // pulling in the swift-cross-ui / WinUI View layer. Both branches
        // are intended to track this code byte-for-byte until it can be
        // promoted to `main` as the canonical IR target.
        .library(
            name: "AdaptiveCardsRenderingIR",
            targets: ["AdaptiveCardsRenderingIR"]),
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
        // wasm-port: shared Rendering IR target. Pure Foundation + ACCore.
        // Mirrored from windows-port's AdaptiveCardsCrossUI/Rendering/* set;
        // see the library product comment above for the rationale on why
        // this lives as its own target rather than being copy/pasted into
        // AdaptiveCardsWebUI.
        .target(
            name: "AdaptiveCardsRenderingIR",
            dependencies: ["ACCore"]),
        // wasm-port: browser-DOM renderer target. JavaScriptKit is only
        // injected when the Swift WASM SDK is selected, so Apple / Linux
        // native builds compile this as an empty module via the
        // `#if canImport(JavaScriptKit)` gate in the source files.
        .target(
            name: "AdaptiveCardsWebUI",
            dependencies: [
                "ACCore",
                "AdaptiveCardsRenderingIR",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ]),
        // wasm-port: standalone demo executable. Compiled for the Swift
        // WASM SDK, the resulting `.wasm` is loaded by the W10 vanilla
        // example page. Under WASI without a DOM (i.e. local `swift run`
        // via wasmkit) it prints a one-line IR summary per reference
        // card and exits — that's the local "is the pipeline working?"
        // smoke check.
        .executableTarget(
            name: "AdaptiveCardsWebDemo",
            dependencies: [
                "ACCore",
                "AdaptiveCardsRenderingIR",
                "AdaptiveCardsWebUI",
            ]),
        // wasm-port: C-ABI WASM module for non-Swift web hosts. Compiles
        // to a `.wasm` whose exports (ac_alloc / ac_free /
        // ac_host_render_json / ac_last_error / ac_version) are callable
        // from vanilla JS, TypeScript, React, etc. without any
        // JavaScriptKit shim. Returns RenderingNode IR as JSON; hosts
        // walk it into their own widget tree (vanilla DOM in W10, React
        // VDOM in W11). Analogous to windows-port's `AdaptiveCardsCABI`.
        .executableTarget(
            name: "AdaptiveCardsWasmCABI",
            dependencies: [
                "ACCore",
                "AdaptiveCardsRenderingIR",
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
