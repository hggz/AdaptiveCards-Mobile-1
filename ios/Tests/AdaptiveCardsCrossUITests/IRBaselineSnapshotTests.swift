//
//  IRBaselineSnapshotTests.swift
//  AdaptiveCardsCrossUITests — windows-port
//
//  Cross-platform IR snapshot gate. Mirrors `AdaptiveCardsValidate`'s
//  `Snapshots` + `A11yBaselines` runners, but expressed as XCTest so
//  the same baseline files are exercised on every platform that runs
//  `swift test --filter AdaptiveCardsCrossUITests`:
//
//    * Windows  — windows-port-ci.yml (in addition to the validator)
//    * macOS    — ios-tests.yml
//    * Linux    — windows-port-ci.yml's linux-build job
//
//  The validator binary already runs the same checks on Windows. This
//  XCTest target is the cross-platform half: it catches IR / a11y-dump
//  drift on macOS and Linux too, without requiring the validator
//  executable to ship for every host.
//
//  The baselines live under
//    Sources/AdaptiveCardsValidate/{Snapshots,A11yBaselines}/
//  so there is ONE source of truth for the IR shape; both the
//  validator and these tests read it.
//

import XCTest
import ACCore
@testable import AdaptiveCardsCrossUI

final class IRBaselineSnapshotTests: XCTestCase {

    // MARK: - Baseline file resolution

    /// Resolve the `Snapshots/` directory by walking up from this test
    /// file. Path shape:
    ///   ios/Tests/AdaptiveCardsCrossUITests/IRBaselineSnapshotTests.swift
    ///   four `deletingLastPathComponent` calls land at <repo>/ios/.
    private static var snapshotsDirectory: URL {
        let here = URL(fileURLWithPath: #filePath)
        let iosRoot = here
            .deletingLastPathComponent()  // AdaptiveCardsCrossUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
        return iosRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("AdaptiveCardsValidate")
            .appendingPathComponent("Snapshots")
    }

    /// Resolve the `A11yBaselines/` directory next to `Snapshots/`.
    private static var a11yBaselinesDirectory: URL {
        snapshotsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("A11yBaselines")
    }

    private static func snapshotPath(for filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        return snapshotsDirectory
            .appendingPathComponent(base + ".rendertree.json")
    }

    private static func a11yPath(for filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        return a11yBaselinesDirectory
            .appendingPathComponent(base + ".a11y.txt")
    }

    // MARK: - Snapshot baselines

    /// Every reference card must produce the same `RenderingNode` tree
    /// (canonical JSON) on every platform. Drift here means the
    /// renderer changed shape; either intentionally (regenerate with
    /// `AdaptiveCardsValidate --update-snapshots`) or accidentally
    /// (this fires to catch the regression).
    func testEveryReferenceCardMatchesItsSnapshotBaseline() throws {
        let renderer = Renderer()
        var failures: [String] = []
        for (name, card) in try SampleCardLibrary.loadReferenceSet() {
            let path = Self.snapshotPath(for: name)
            guard FileManager.default.fileExists(atPath: path.path) else {
                failures.append("\(name): baseline missing at \(path.path)")
                continue
            }
            let baseline: String
            do {
                baseline = try String(contentsOf: path, encoding: .utf8)
                    .trimmingCharacters(in: .newlines)
            } catch {
                failures.append("\(name): cannot read baseline (\(error))")
                continue
            }
            let tree = renderer.render(card: card)
            let actual: String
            do {
                actual = try tree.snapshotJSON()
                    .trimmingCharacters(in: .newlines)
            } catch {
                failures.append("\(name): encode failed (\(error))")
                continue
            }
            if actual != baseline {
                failures.append(
                    "\(name): DRIFTED — first diff line \(Self.firstDiffLine(actual, baseline))"
                )
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "IR snapshot drift:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - A11y baselines

    /// Every reference card must produce the same a11y dump on every
    /// platform. This is the cross-platform sibling of the validator's
    /// `A11yBaselines.runChecks`.
    func testEveryReferenceCardMatchesItsA11yBaseline() throws {
        let renderer = Renderer()
        var failures: [String] = []
        for (name, card) in try SampleCardLibrary.loadReferenceSet() {
            let path = Self.a11yPath(for: name)
            guard FileManager.default.fileExists(atPath: path.path) else {
                failures.append("\(name): baseline missing at \(path.path)")
                continue
            }
            let baseline: String
            do {
                baseline = try String(contentsOf: path, encoding: .utf8)
                    .trimmingCharacters(in: .newlines)
            } catch {
                failures.append("\(name): cannot read baseline (\(error))")
                continue
            }
            let tree = renderer.render(card: card)
            let actual = A11yDump.dump(tree)
                .trimmingCharacters(in: .newlines)
            if actual != baseline {
                failures.append(
                    "\(name): DRIFTED — first diff line \(Self.firstDiffLine(actual, baseline))"
                )
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "A11y baseline drift:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Aggregate violation budget

    /// Pin the reference set's total a11y violation counts so any new
    /// MISSING_LABEL / MISSING_ALT / UNRENDERED introduced by a future
    /// commit lights up immediately. Mirrors the validator's
    /// "violation totals across reference set" log.
    func testAggregateA11yViolationBudget() throws {
        let renderer = Renderer()
        var missingLabel = 0
        var missingAlt = 0
        var unrendered = 0
        for (_, card) in try SampleCardLibrary.loadReferenceSet() {
            let dump = A11yDump.dump(renderer.render(card: card))
            missingLabel += Self.countOccurrences(of: "MISSING_LABEL", in: dump)
            missingAlt += Self.countOccurrences(of: "MISSING_ALT", in: dump)
            unrendered += Self.countOccurrences(of: "UNRENDERED", in: dump)
        }
        // Locked budget as of Phase 24 (renderer-complete). Any change
        // requires an intentional update here AND a commit message that
        // explains why the new tally is correct (e.g. a regenerated
        // reference card that introduces a deliberately-untagged image).
        XCTAssertEqual(missingLabel, 0, "MISSING_LABEL must stay at 0 across the reference set")
        XCTAssertEqual(missingAlt, 1, "MISSING_ALT budget is 1 (cat image in containers.json)")
        XCTAssertEqual(unrendered, 0, "UNRENDERED must stay at 0 (renderer coverage is complete)")
    }

    // MARK: - Helpers

    /// Counts non-overlapping occurrences of `needle` in `haystack`.
    /// Used so we don't pull in `Regex` (Linux/Windows availability
    /// varies between Swift releases).
    private static func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var n = 0
        var search = haystack.startIndex..<haystack.endIndex
        while let r = haystack.range(of: needle, range: search) {
            n += 1
            search = r.upperBound..<haystack.endIndex
        }
        return n
    }

    /// Same first-diff helper the validator uses; pulled inline so the
    /// XCTest target doesn't need to depend on AdaptiveCardsValidate.
    private static func firstDiffLine(_ a: String, _ b: String) -> String {
        let la = a.split(separator: "\n", omittingEmptySubsequences: false)
        let lb = b.split(separator: "\n", omittingEmptySubsequences: false)
        for i in 0..<max(la.count, lb.count) {
            let s1 = i < la.count ? String(la[i]) : "<missing>"
            let s2 = i < lb.count ? String(lb[i]) : "<missing>"
            if s1 != s2 {
                return "L\(i+1): current=\(s1.prefix(80))  baseline=\(s2.prefix(80))"
            }
        }
        return "(no line diff found — trailing whitespace?)"
    }
}
