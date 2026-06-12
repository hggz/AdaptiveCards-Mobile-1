#if canImport(UIKit)
import XCTest
import SwiftUI
import UIKit
@testable import ACCore
@testable import ACRendering

/// Collapsed-vs-expanded visual regression for the ICM 812389686 tall accordion.
///
/// Mirrors `CardVisualRegressionTests` but loads the repro card from
/// `ACRenderingTests/Resources/` (it is intentionally not part of the shared
/// `test-cards` catalog because it is a diagnostic, not a feature sample).
///
/// Two snapshots are produced per configuration:
///   * `..._collapsed` — accordion closed (`Tall_Body` hidden)
///   * `..._expanded`  — accordion open (`Tall_Body` visible)
///
/// The expanded snapshot is what reveals symptom 1 (clipped bottom) and symptom 2
/// (overflow past the host frame) when compared against a healthy baseline.
///
/// Baselines are recorded in CI with `RECORD_SNAPSHOTS=1` and uploaded as artifacts;
/// without a baseline these assertions fail gracefully (same as the rest of the
/// visual suite), so they are safe to run on every push.
///
/// EUII-safe: the repro card contains only generic placeholder copy.
final class AccordionScrollRegionVisualTests: CardSnapshotTestCase {

    private func loadReproJSON() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VisualTests/
            .deletingLastPathComponent() // Tests/
            .appendingPathComponent("ACRenderingTests/Resources/repro_812389686_tall_accordion.json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Builds a card view bound to a pre-seeded view model so we can snapshot a
    /// specific visibility state deterministically (no async parse / tap needed).
    @MainActor
    private func reproView(expanded: Bool) throws -> some View {
        let viewModel = CardViewModel()
        viewModel.card = try CardParser().parse(loadReproJSON())
        viewModel.visibility["Tall_Body"] = expanded
        viewModel.visibility["Chevron_Collapsed"] = !expanded
        viewModel.visibility["Chevron_Expanded"] = expanded

        let hostConfig = self.hostConfig
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.card?.body ?? []) { element in
                    if viewModel.isElementVisible(elementId: element.elementId) {
                        ElementView(element: element, hostConfig: hostConfig)
                    }
                }
            }
            .padding(CGFloat(hostConfig.spacing.padding))
        }
        .environmentObject(viewModel)
        .environment(\.hostConfig, hostConfig)
    }

    @MainActor
    func testTallAccordionCollapsed() throws {
        let view = try reproView(expanded: false)
        assertSnapshot(of: view, named: "repro_812389686_tall_accordion_collapsed", configuration: .iPhone15Pro)
    }

    @MainActor
    func testTallAccordionExpanded() throws {
        let view = try reproView(expanded: true)
        assertSnapshot(of: view, named: "repro_812389686_tall_accordion_expanded", configuration: .iPhone15Pro)
    }

    @MainActor
    func testTallAccordionExpanded_smallScreen() throws {
        // iPhone SE is the worst case for the clip: smallest visible height.
        let view = try reproView(expanded: true)
        assertSnapshot(of: view, named: "repro_812389686_tall_accordion_expanded", configuration: .iPhoneSE)
    }
}
#endif
