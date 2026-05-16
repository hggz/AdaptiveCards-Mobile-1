//
//  SampleCardLibrary.swift
//  AdaptiveCardsCrossUI — windows-port
//
//  Locates and loads the Adaptive Card JSON samples that live under
//  `shared/test-cards/` in this repository. The validation loop reuses
//  the *exact* same files iOS / Android consume — there is no duplicated
//  JSON anywhere in this target.
//
//  The repo root is resolved relative to `#filePath` so this works for
//  both `swift test` and `swift run` invocations from the package root.
//  For shipping binaries the host application is responsible for pointing
//  the demo at the cards via `AdaptiveCardsTestCardsPath` env var.
//

import Foundation
import ACCore

public enum SampleCardLibrary {

    /// Override used by CI and shipping binaries to point at a cards
    /// directory other than the source-tree-relative default.
    private static let envVar = "AdaptiveCardsTestCardsPath"

    /// Resolves the directory that contains the Adaptive Card sample
    /// JSON files. In priority order:
    ///   1. `AdaptiveCardsTestCardsPath` env var.
    ///   2. `<repo-root>/shared/test-cards/` resolved relative to this
    ///      source file via `#filePath`.
    public static let testCardsDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment[envVar],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        // <repo>/ios/Sources/AdaptiveCardsCrossUI/SampleCardLibrary.swift
        // four directory hops back: SampleCardLibrary.swift -> AdaptiveCardsCrossUI
        // -> Sources -> ios -> <repo>
        let here = URL(fileURLWithPath: #filePath)
        let repoRoot = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot
            .appendingPathComponent("shared", isDirectory: true)
            .appendingPathComponent("test-cards", isDirectory: true)
    }()

    /// The curated reference set used for the v1 Windows demo. Each entry
    /// is selected to exercise a different facet of the renderer.
    public static let referenceSampleFilenames: [String] = [
        "simple-text.json",
        "containers.json",
        "input-form.json",
        "all-actions.json",
        "table.json",
        "rating.json",
        "edge-empty-card.json",
        // Phase 17: covers Chart (donut + bar), TabSet (multi-tab with
        // mixed body content), and CompoundButton (Submit + OpenUrl) so
        // the snapshot + a11y baselines exercise the Phase 16 renderer
        // additions.
        "windows-extras.json",
    ]

    public struct LoadError: Error, LocalizedError {
        public let filename: String
        public let reason: String
        public var errorDescription: String? {
            "Failed to load \(filename): \(reason)"
        }
    }

    /// Loads a single sample by filename (e.g. `"simple-text.json"`)
    /// from `testCardsDirectory` and parses it via `CardParser`.
    public static func load(filename: String) throws -> AdaptiveCard {
        let url = testCardsDirectory.appendingPathComponent(filename)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError(filename: filename, reason: "\(error.localizedDescription) (looked under \(url.path))")
        }
        guard let str = String(data: data, encoding: .utf8) else {
            throw LoadError(filename: filename, reason: "non-UTF8 bytes")
        }
        do {
            return try CardParser().parse(str)
        } catch {
            throw LoadError(filename: filename, reason: error.localizedDescription)
        }
    }

    /// Loads every reference sample and returns parsed `(filename, card)`
    /// pairs. Throws on the first failure.
    public static func loadReferenceSet() throws -> [(String, AdaptiveCard)] {
        try referenceSampleFilenames.map { name in
            (name, try load(filename: name))
        }
    }

    /// Lists every `*.json` file directly in `testCardsDirectory`
    /// (non-recursive). Used by tests that want broad parser coverage.
    public static func allTopLevelCardFilenames() throws -> [String] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: testCardsDirectory.path)
        return contents
            .filter { $0.hasSuffix(".json") }
            .sorted()
    }
}
