//
//  SampleCardParsingTests.swift
//  AdaptiveCardsCrossUITests — windows-port
//
//  Validates the imperative loop's data half: every JSON in
//  shared/test-cards/ parses cleanly via ACCore and produces a non-nil
//  rendering tree. Runs entirely headless — no swift-cross-ui involved.
//

import XCTest
import ACCore
@testable import AdaptiveCardsCrossUI

final class SampleCardParsingTests: XCTestCase {

    func testReferenceSamplesAllParse() throws {
        let pairs = try SampleCardLibrary.loadReferenceSet()
        XCTAssertEqual(pairs.count, SampleCardLibrary.referenceSampleFilenames.count)
        for (name, card) in pairs {
            XCTAssertFalse(card.version.isEmpty, "\(name) parsed but has empty version")
        }
    }

    func testReferenceSamplesEachProduceANonEmptyRenderingTree() throws {
        // edge-empty-card.json deliberately has no body/actions — exclude it
        // from the non-empty assertion but assert it still parses.
        let renderer = Renderer()
        for (name, card) in try SampleCardLibrary.loadReferenceSet() {
            let tree = renderer.render(card: card)
            switch tree {
            case .verticalStack(_, let children):
                if name == "edge-empty-card.json" {
                    XCTAssertTrue(children.isEmpty, "edge-empty-card should produce empty children")
                } else {
                    XCTAssertFalse(children.isEmpty, "\(name) rendered to empty tree")
                }
            default:
                XCTFail("\(name) top-level must be a verticalStack, got \(tree)")
            }
        }
    }

    func testAllTopLevelCardsParse() throws {
        // Broad parser coverage: every *.json directly under
        // shared/test-cards/ must round-trip through CardParser without
        // throwing. Subdirectories (official-samples, teams-*, etc.) are
        // deliberately out of scope to keep the loop fast. Templating
        // samples are pre-expansion (`${var}` placeholders in typed slots)
        // and require ACTemplating to materialize before parsing — that
        // module is Apple-only today, so we skip them in v1.
        let templatingSkiplist: Set<String> = [
            "templating-basic.json",
            "templating-conditional.json",
            "templating-expressions.json",
            "templating-iteration.json",
            "templating-nested.json",
        ]
        let names = try SampleCardLibrary.allTopLevelCardFilenames()
            .filter { !templatingSkiplist.contains($0) }
        XCTAssertGreaterThan(names.count, 20, "expected many sample cards")

        var failures: [String] = []
        for name in names {
            do {
                _ = try SampleCardLibrary.load(filename: name)
            } catch {
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "Some sample cards failed to parse:\n" + failures.joined(separator: "\n")
        )
    }
}
