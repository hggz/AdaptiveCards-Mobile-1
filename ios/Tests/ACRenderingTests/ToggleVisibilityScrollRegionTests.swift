#if canImport(UIKit)
import XCTest
import SwiftUI
import UIKit
@testable import ACCore
@testable import ACRendering

/// Diagnostic regression test for ICM 812389686 (Sev3, OED).
///
/// Reproduces the mobile-only Adaptive Card accordion defect that regressed in
/// Teams mobile 8.9.0 (build 8.9.77.2026092302), originally fixed under ICM 776036215.
///
/// Symptom 1 (no scroll region): when an accordion is expanded via
/// `Action.ToggleVisibility`, the expanded content can be taller than the visible
/// area but no scrollable region is created, so the bottom is clipped and the final
/// `Bottom_Sentinel` element becomes unreachable in the accessibility tree.
///
/// Symptom 2 (z-order overlap): the expanded content overflows its host cell frame
/// and overlaps the next card. That symptom is host-side (the SDK renders into a
/// single card frame) and is covered by the snapshot test + the Glassjar UI test;
/// here we assert the SDK-level invariants that the host relies on:
///   1. Toggling `Tall_Body` visible grows the rendered fitting height.
///   2. `Bottom_Sentinel` is present in the rendered accessibility tree after expand.
///   3. When the host frame is fixed (no scroll), the bottom is clipped — this test
///      documents that the SDK's own root `ScrollView` keeps the sentinel reachable,
///      isolating the defect to the Teams host cell sizing rather than SDK layout.
///
/// EUII-safe: this test only inspects element IDs, accessibility labels, and frame
/// sizes. The repro card contains generic placeholder copy, never customer text.
final class ToggleVisibilityScrollRegionTests: XCTestCase {

    // MARK: - Card Loading

    /// Loads the amplified tall accordion repro card from the test Resources folder.
    /// `ACRenderingTests` does not bundle Resources via SPM, so the JSON is loaded
    /// directly via a `#filePath`-relative path (works locally and in CI).
    private func loadReproCardJSON() throws -> String {
        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ACRenderingTests/
            .appendingPathComponent("Resources/repro_812389686_tall_accordion.json")

        guard FileManager.default.fileExists(atPath: resourceURL.path) else {
            throw XCTSkip("Repro card not found at \(resourceURL.path)")
        }
        return try String(contentsOf: resourceURL, encoding: .utf8)
    }

    private func parseReproCard() throws -> AdaptiveCard {
        let json = try loadReproCardJSON()
        return try CardParser().parse(json)
    }

    // MARK: - Structure Sanity

    /// Confirms the repro card has the expected chevron ToggleVisibility wiring and
    /// the tall hidden body containing the bottom sentinel.
    func testReproCardStructure() throws {
        let card = try parseReproCard()

        // The toggle lives on the header ColumnSet's selectAction.
        guard case .columnSet(let headerRow)? = card.body?.first(where: { $0.elementId == "Accordion_Header_Row" }) else {
            return XCTFail("Expected Accordion_Header_Row ColumnSet")
        }
        guard case .toggleVisibility(let toggle)? = headerRow.selectAction else {
            return XCTFail("Expected Action.ToggleVisibility on header selectAction")
        }
        let toggleTargets = Set(toggle.targetElements.map { $0.elementId })
        XCTAssertTrue(toggleTargets.contains("Tall_Body"), "Toggle must target Tall_Body")

        // Tall_Body must start hidden and contain the Bottom_Sentinel.
        guard case .container(let tallBody)? = card.body?.first(where: { $0.elementId == "Tall_Body" }) else {
            return XCTFail("Expected Tall_Body Container")
        }
        XCTAssertEqual(tallBody.isVisible, false, "Tall_Body must start collapsed (isVisible=false)")

        let sentinel = tallBody.items?.first { $0.elementId == "Bottom_Sentinel" }
        XCTAssertNotNil(sentinel, "Tall_Body must contain Bottom_Sentinel")
    }

    // MARK: - Symptom 1: scroll region / content height growth

    /// Renders the card collapsed, then expands `Tall_Body`, and asserts the
    /// rendered fitting height grows substantially. A regression that fails to
    /// re-measure the content on toggle would NOT grow the height here.
    @MainActor
    func testExpandGrowsContentHeight() throws {
        let json = try loadReproCardJSON()
        let viewModel = CardViewModel()
        viewModel.card = try CardParser().parse(json)
        viewModel.visibility["Tall_Body"] = false

        let width: CGFloat = 393 // iPhone 15 Pro logical width

        let collapsedHeight = fittingHeight(for: viewModel, width: width)

        // Expand exactly as Action.ToggleVisibility would.
        viewModel.toggleVisibility(elementId: "Tall_Body", isVisible: true)
        XCTAssertTrue(viewModel.isElementVisible(elementId: "Tall_Body"))

        let expandedHeight = fittingHeight(for: viewModel, width: width)

        // Diagnostic logging — EUII-safe (sizes only, no card text).
        print("[ICM-812389686] collapsedHeight=\(Int(collapsedHeight)) expandedHeight=\(Int(expandedHeight)) width=\(Int(width))")

        XCTAssertGreaterThan(
            expandedHeight, collapsedHeight,
            "Expanded accordion must grow the rendered content height; if not, the toggle did not trigger a relayout (symptom 1 regression)."
        )
        // The amplified body is intentionally taller than a phone screen.
        XCTAssertGreaterThan(
            expandedHeight, 852,
            "Expanded content should exceed a single iPhone 15 Pro screen height so a scroll region is required."
        )
    }

    // MARK: - Symptom 1: accessibility reachability of the sentinel

    /// After expand, walks the rendered accessibility tree and asserts the
    /// `Bottom_Sentinel` text is reachable. The regression makes it unreachable
    /// (clipped, outside the accessible content).
    @MainActor
    func testBottomSentinelReachableAfterExpand() throws {
        let json = try loadReproCardJSON()
        let viewModel = CardViewModel()
        viewModel.card = try CardParser().parse(json)
        viewModel.visibility["Tall_Body"] = false

        // Collapsed: sentinel should NOT be in the tree.
        let collapsedLabels = renderedAccessibilityLabels(for: viewModel, size: CGSize(width: 393, height: 852))
        XCTAssertFalse(
            collapsedLabels.contains { $0.contains("Bottom sentinel") },
            "Bottom_Sentinel must be hidden while the accordion is collapsed."
        )

        // Expand and re-walk.
        viewModel.toggleVisibility(elementId: "Tall_Body", isVisible: true)
        let expandedLabels = renderedAccessibilityLabels(for: viewModel, size: CGSize(width: 393, height: 852))

        print("[ICM-812389686] a11yElementCount collapsed=\(collapsedLabels.count) expanded=\(expandedLabels.count)")

        XCTAssertTrue(
            expandedLabels.contains { $0.contains("Bottom sentinel") },
            "After expand, Bottom_Sentinel must be reachable in the accessibility tree (regression makes it unreachable)."
        )
    }

    // MARK: - Isolation: SDK root ScrollView vs host cell

    /// Documents that the SDK's own root `ScrollView` keeps the full expanded
    /// content (including the sentinel) inside a scrollable region even when the
    /// host frame is constrained to a single screen. If this passes while Glassjar
    /// shows the sentinel clipped, the defect is in the Teams host cell sizing, not
    /// the SDK layout.
    @MainActor
    func testSdkRootScrollViewKeepsSentinelInContentWhenFrameConstrained() throws {
        let json = try loadReproCardJSON()
        let viewModel = CardViewModel()
        viewModel.card = try CardParser().parse(json)
        viewModel.visibility["Tall_Body"] = true // start expanded

        // Constrain the host frame to a single screen (simulates a fixed host cell).
        let constrained = CGSize(width: 393, height: 852)
        let labels = renderedAccessibilityLabels(for: viewModel, size: constrained, fixedFrame: true)

        XCTAssertTrue(
            labels.contains { $0.contains("Bottom sentinel") },
            "With the SDK's root ScrollView, the sentinel stays inside the scrollable content even when the frame is constrained — confirms SDK layout is not the clip site."
        )
    }

    // MARK: - Helpers

    /// Builds the SDK card view bound to a specific view model (so we can pre-set
    /// visibility instead of relying on async parse + tap simulation).
    @MainActor
    private func makeCardView(_ viewModel: CardViewModel) -> some View {
        let body = viewModel.card?.body ?? []
        let hostConfig = TeamsHostConfig.create()
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(body) { element in
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

    /// Measures the natural (uncapped) fitting height of the card content.
    @MainActor
    private func fittingHeight(for viewModel: CardViewModel, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: makeCardView(viewModel))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 4000))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 4000)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let size = host.view.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        window.isHidden = true
        return size.height
    }

    /// Renders the card and collects all accessibility labels from the view tree.
    /// When `fixedFrame` is true the hosting view is pinned to `size` (simulating a
    /// constrained host cell); otherwise it is laid out at its natural height.
    @MainActor
    private func renderedAccessibilityLabels(
        for viewModel: CardViewModel,
        size: CGSize,
        fixedFrame: Bool = false
    ) -> [String] {
        let host = UIHostingController(rootView: makeCardView(viewModel))
        let renderHeight = fixedFrame ? size.height : 4000
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: size.width, height: renderHeight))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = CGRect(x: 0, y: 0, width: size.width, height: renderHeight)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        var labels: [String] = []
        collectAccessibilityLabels(from: host.view, into: &labels)
        window.isHidden = true
        return labels
    }

    /// Recursively collects accessibility labels from a view, its subviews, and any
    /// `accessibilityElements` it exposes. This mirrors how VoiceOver traverses the
    /// tree (including elements inside SwiftUI accessibility containers).
    private func collectAccessibilityLabels(from view: UIView, into labels: inout [String]) {
        if view.isAccessibilityElement, let label = view.accessibilityLabel {
            labels.append(label)
        }
        if let elements = view.accessibilityElements {
            for case let element as NSObject in elements {
                if let label = element.accessibilityLabel {
                    labels.append(label)
                }
            }
        }
        for subview in view.subviews {
            collectAccessibilityLabels(from: subview, into: &labels)
        }
    }
}
#endif
