import XCTest
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
/// `Bottom_Sentinel` element becomes unreachable.
///
/// Symptom 2 (z-order overlap): the expanded content overflows its host cell frame
/// and overlaps the next card. That symptom is host-side (the SDK renders into a
/// single card frame) and is covered by the snapshot test + the Glassjar UI test.
///
/// The model-level assertions below run on the SPM macOS CI runner (no UIKit). The
/// UIKit rendering/measurement assertions are platform-guarded and run only when the
/// suite is built for an iOS destination (Xcode), where `UIHostingController` exists.
///
/// EUII-safe: this test only inspects element IDs, accessibility labels, and frame
/// sizes. The repro card contains generic placeholder copy, never customer text.
final class ToggleVisibilityScrollRegionTests: XCTestCase {

    // MARK: - Card Loading

    /// Loads the amplified tall accordion repro card from the test Resources folder.
    /// `ACRenderingTests` does not bundle Resources via SPM, so the JSON is loaded
    /// directly via a `#filePath`-relative path (works locally and in CI).
    func loadReproCardJSON() throws -> String {
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

    // MARK: - Structure Sanity (runs everywhere, incl. SPM CI)

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

        // The body is intentionally tall: enough items to overflow a phone screen.
        XCTAssertGreaterThanOrEqual(tallBody.items?.count ?? 0, 10,
            "Tall_Body must be large enough to force a scroll region on a phone.")
    }

    // MARK: - Symptom 1 at the model level (runs everywhere, incl. SPM CI)

    /// Drives the view model exactly as `Action.ToggleVisibility` would and asserts
    /// that the sentinel-bearing container transitions from hidden to visible. This
    /// is the model-level invariant the renderer and host both depend on: if the
    /// toggle does not flip `Tall_Body` visible, no relayout can occur (symptom 1).
    func testToggleMakesTallBodyAndSentinelVisible() throws {
        let viewModel = CardViewModel()
        viewModel.card = try parseReproCard()
        // Seed initial visibility from the card (mirrors CardViewModel.initializeVisibility).
        viewModel.visibility["Tall_Body"] = false

        // Collapsed: the body is hidden, so its descendants are not in the visible set.
        XCTAssertFalse(viewModel.isElementVisible(elementId: "Tall_Body"),
            "Tall_Body must start collapsed.")
        XCTAssertFalse(visibleAccessibilityOrder(viewModel).contains("Bottom_Sentinel"),
            "Bottom_Sentinel must NOT be reachable while collapsed.")

        // Expand exactly as Action.ToggleVisibility would.
        viewModel.toggleVisibility(elementId: "Tall_Body", isVisible: true)

        XCTAssertTrue(viewModel.isElementVisible(elementId: "Tall_Body"),
            "After toggle, Tall_Body must be visible.")

        let order = visibleAccessibilityOrder(viewModel)
        // Diagnostic logging — EUII-safe (IDs only, no card text).
        print("[ICM-812389686] visibleElementCount=\(order.count) sentinelReachable=\(order.contains("Bottom_Sentinel"))")

        XCTAssertTrue(order.contains("Bottom_Sentinel"),
            "After expand, Bottom_Sentinel must be reachable in the visible element order (regression makes it unreachable).")
        XCTAssertEqual(order.last, "Bottom_Sentinel",
            "Bottom_Sentinel must be the LAST reachable element after expand (it marks the bottom that gets clipped).")
    }

    // MARK: - Helpers (UIKit-free)

    /// Walks the parsed card honoring the view model's current visibility state and
    /// returns the ordered list of element IDs that a screen reader would traverse.
    /// This models VoiceOver's reading order at the data level, independent of the
    /// rendering platform, so it runs on the SPM macOS CI runner.
    func visibleAccessibilityOrder(_ viewModel: CardViewModel) -> [String] {
        var ids: [String] = []
        for element in viewModel.card?.body ?? [] {
            appendVisible(element, viewModel: viewModel, into: &ids)
        }
        return ids
    }

    private func appendVisible(_ element: CardElement, viewModel: CardViewModel, into ids: inout [String]) {
        // An element is reachable only if it and its ancestors are visible.
        guard viewModel.isElementVisible(elementId: element.elementId) else { return }
        if let id = element.elementId { ids.append(id) }

        switch element {
        case .container(let container):
            for item in container.items ?? [] {
                appendVisible(item, viewModel: viewModel, into: &ids)
            }
        case .columnSet(let columnSet):
            for column in columnSet.columns {
                for item in column.items ?? [] {
                    appendVisible(item, viewModel: viewModel, into: &ids)
                }
            }
        default:
            break
        }
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

/// UIKit-dependent rendering/measurement assertions for ICM 812389686.
///
/// These run only when the suite is built for an iOS destination (Xcode / simulator),
/// where `UIHostingController` and `UIWindow` exist. On the SPM macOS CI runner UIKit
/// is unavailable, so this section compiles out and the model-level assertions above
/// provide the CI coverage.
extension ToggleVisibilityScrollRegionTests {

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

    @MainActor
    private func reproViewModel() throws -> CardViewModel {
        let vm = CardViewModel()
        vm.card = try CardParser().parse(loadReproCardJSON())
        vm.visibility["Tall_Body"] = false
        return vm
    }

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

    /// Renders the card collapsed, then expands `Tall_Body`, and asserts the
    /// rendered fitting height grows substantially. A regression that fails to
    /// re-measure the content on toggle would NOT grow the height here.
    @MainActor
    func testExpandGrowsRenderedHeight() throws {
        let viewModel = try reproViewModel()
        let width: CGFloat = 393 // iPhone 15 Pro logical width

        let collapsedHeight = fittingHeight(for: viewModel, width: width)
        viewModel.toggleVisibility(elementId: "Tall_Body", isVisible: true)
        let expandedHeight = fittingHeight(for: viewModel, width: width)

        // EUII-safe diagnostic (sizes only).
        print("[ICM-812389686] collapsedHeight=\(Int(collapsedHeight)) expandedHeight=\(Int(expandedHeight)) width=\(Int(width))")

        XCTAssertGreaterThan(expandedHeight, collapsedHeight,
            "Expanded accordion must grow the rendered content height; if not, the toggle did not trigger a relayout (symptom 1 regression).")
        XCTAssertGreaterThan(expandedHeight, 852,
            "Expanded content should exceed an iPhone 15 Pro screen height so a scroll region is required.")
    }

    /// Renders the card and collects accessibility labels from the rendered view
    /// tree. Asserts `Bottom_Sentinel` is reachable only after expand, and stays
    /// reachable even when the host frame is constrained (SDK root ScrollView).
    @MainActor
    func testRenderedSentinelReachableAfterExpand() throws {
        let viewModel = try reproViewModel()

        let collapsedLabels = renderedAccessibilityLabels(for: viewModel, size: CGSize(width: 393, height: 852))
        XCTAssertFalse(collapsedLabels.contains { $0.contains("Bottom sentinel") },
            "Bottom_Sentinel must be hidden while the accordion is collapsed.")

        viewModel.toggleVisibility(elementId: "Tall_Body", isVisible: true)
        let expandedLabels = renderedAccessibilityLabels(for: viewModel, size: CGSize(width: 393, height: 852), fixedFrame: true)

        print("[ICM-812389686] renderedA11yCount collapsed=\(collapsedLabels.count) expanded=\(expandedLabels.count)")

        XCTAssertTrue(expandedLabels.contains { $0.contains("Bottom sentinel") },
            "With the SDK's root ScrollView, the sentinel stays inside the scrollable content even when the frame is constrained — confirms SDK layout is not the clip site (defect is the Teams host cell sizing).")
    }

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

    private func collectAccessibilityLabels(from view: UIView, into labels: inout [String]) {
        if view.isAccessibilityElement, let label = view.accessibilityLabel {
            labels.append(label)
        }
        if let elements = view.accessibilityElements {
            for case let element as NSObject in elements where element.accessibilityLabel != nil {
                labels.append(element.accessibilityLabel!)
            }
        }
        for subview in view.subviews {
            collectAccessibilityLabels(from: subview, into: &labels)
        }
    }
}
#endif
