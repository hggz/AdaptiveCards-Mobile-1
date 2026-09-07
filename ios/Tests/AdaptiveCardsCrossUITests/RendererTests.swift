//
//  RendererTests.swift
//  AdaptiveCardsCrossUITests — windows-port
//
//  Verifies the element-to-`RenderingNode` mapping in `Renderer`.
//  This is the heart of the headless validation loop: the renderer is a
//  pure function from `AdaptiveCard` to `RenderingNode`, so we assert
//  exact shapes for every wired element type.
//

import XCTest
import ACCore
@testable import AdaptiveCardsCrossUI

final class RendererTests: XCTestCase {

    private let renderer = Renderer()

    // MARK: - TextBlock

    func testTextBlockBasic() {
        let tb = TextBlock(text: "Hello")
        let node = renderer.render(element: .textBlock(tb))
        XCTAssertEqual(node, .text("Hello", size: .default, weight: .default, wrap: false, isSubtle: false))
    }

    func testTextBlockLargeBolderWrapped() {
        let tb = TextBlock(text: "Big", size: .large, weight: .bolder, wrap: true)
        let node = renderer.render(element: .textBlock(tb))
        XCTAssertEqual(node, .text("Big", size: .large, weight: .bolder, wrap: true, isSubtle: false))
    }

    func testTextBlockSubtle() {
        let tb = TextBlock(text: "quiet", isSubtle: true)
        guard case let .text(_, _, _, _, isSubtle) = renderer.render(element: .textBlock(tb)) else {
            return XCTFail("expected .text")
        }
        XCTAssertTrue(isSubtle)
    }

    // MARK: - Image

    func testImageMapsUrlAndAlt() {
        let img = Image(url: "https://example.com/x.png", altText: "Example", size: .small)
        let node = renderer.render(element: .image(img))
        XCTAssertEqual(node, .image(url: "https://example.com/x.png", alt: "Example", displayHint: .small))
    }

    func testImageDefaultAltIsEmpty() {
        let img = Image(url: "https://example.com/x.png")
        if case let .image(_, alt, _) = renderer.render(element: .image(img)) {
            XCTAssertEqual(alt, "")
        } else {
            XCTFail("expected .image")
        }
    }

    // MARK: - Container / ColumnSet

    func testContainerWrapsItemsInVerticalStack() {
        let inner = TextBlock(text: "inside")
        let c = Container(items: [.textBlock(inner)])
        let node = renderer.render(element: .container(c))
        guard case let .verticalStack(_, children) = node else {
            return XCTFail("expected verticalStack")
        }
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children.first, .text("inside", size: .default, weight: .default, wrap: false, isSubtle: false))
    }

    func testColumnSetIsHorizontalStackOfVerticalStacks() {
        let col1 = Column(items: [.textBlock(TextBlock(text: "A"))])
        let col2 = Column(items: [.textBlock(TextBlock(text: "B"))])
        let cs = ColumnSet(columns: [col1, col2])
        let node = renderer.render(element: .columnSet(cs))
        guard case let .horizontalStack(_, columns) = node else {
            return XCTFail("expected horizontalStack")
        }
        XCTAssertEqual(columns.count, 2)
        for c in columns {
            guard case .verticalStack = c else {
                return XCTFail("expected each column to be verticalStack")
            }
        }
    }

    // MARK: - FactSet

    func testFactSetProducesPairs() {
        let fs = FactSet(facts: [
            .init(title: "Owner", value: "Hugo"),
            .init(title: "Version", value: "1.6"),
        ])
        let node = renderer.render(element: .factSet(fs))
        guard case let .facts(pairs) = node else { return XCTFail("expected facts") }
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].title, "Owner")
        XCTAssertEqual(pairs[0].value, "Hugo")
    }

    // MARK: - Actions

    func testSubmitActionMapsToSubmitKind() {
        let s = SubmitAction(title: "Send")
        let node = renderer.render(action: .submit(s))
        guard case let .button(title, kind) = node else { return XCTFail("expected button") }
        XCTAssertEqual(title, "Send")
        guard case .submit = kind else { return XCTFail("expected .submit kind") }
    }

    func testOpenUrlActionCapturesURL() {
        let o = OpenUrlAction(title: "Open", url: "https://example.com")
        let node = renderer.render(action: .openUrl(o))
        XCTAssertEqual(node, .button(title: "Open", kind: .openUrl("https://example.com")))
    }

    // MARK: - Card-level

    func testCardLevelTreeHasBodyAndActions() {
        let card = AdaptiveCard(
            body: [.textBlock(TextBlock(text: "hi"))],
            actions: [.submit(SubmitAction(title: "Go"))]
        )
        let tree = renderer.render(card: card)
        guard case let .verticalStack(_, children) = tree else {
            return XCTFail("expected verticalStack")
        }
        XCTAssertEqual(children.count, 2, "one body element + one action row")

        // Last child should be the horizontalStack of action buttons.
        guard case let .horizontalStack(_, buttons) = children.last else {
            return XCTFail("expected actions to render as horizontalStack")
        }
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons.first, .button(title: "Go", kind: .submit(dataJSON: nil)))
    }

    func testInvisibleBodyElementsAreDropped() {
        let visible = TextBlock(text: "v")
        var hidden = TextBlock(text: "h")
        hidden.isVisible = false
        let card = AdaptiveCard(body: [.textBlock(visible), .textBlock(hidden)])
        let tree = renderer.render(card: card)
        guard case let .verticalStack(_, children) = tree else { return XCTFail() }
        XCTAssertEqual(children.count, 1)
    }

    // MARK: - Unsupported

    func testUnknownElementMapsToUnsupported() {
        let node = renderer.render(element: .unknown(type: "Carousel.Future"))
        XCTAssertEqual(node, .unsupported(typeString: "Carousel.Future"))
    }

    func testTextInputMapsToTextField() {
        // Inputs are read-only in v1 — they render as labeled `.textField`
        // nodes. Interactive bindings land in a later phase.
        let ti = TextInput(id: "name", label: "Name", placeholder: "Enter your name")
        let node = renderer.render(element: .textInput(ti))
        XCTAssertEqual(
            node,
            .textField(
                id: "name",
                label: "Name",
                placeholder: "Enter your name",
                value: nil,
                isRequired: false,
                isMultiline: false
            )
        )
    }

    func testToggleInputDefaultIsOff() {
        let t = ToggleInput(id: "sub", title: "Subscribe")
        let node = renderer.render(element: .toggleInput(t))
        XCTAssertEqual(
            node,
            .toggleField(
                id: "sub",
                title: "Subscribe",
                label: nil,
                value: false,
                valueOn: "true",
                valueOff: "false",
                isRequired: false
            )
        )
    }

    func testToggleInputRespectsValueOnAndOff() {
        let t = ToggleInput(id: "sub", title: "X", value: "yes", valueOn: "yes", valueOff: "no")
        guard case let .toggleField(_, _, _, value, on, off, _) = renderer.render(element: .toggleInput(t)) else {
            return XCTFail("expected .toggleField")
        }
        XCTAssertTrue(value)
        XCTAssertEqual(on, "yes")
        XCTAssertEqual(off, "no")
    }

    func testChoiceSetMapsChoicesAsTitleValuePairs() {
        let cs = ChoiceSetInput(
            id: "pick",
            label: "Pick one",
            choices: [.init(title: "A", value: "a"), .init(title: "B", value: "b")],
            value: "b"
        )
        let node = renderer.render(element: .choiceSetInput(cs))
        if case let .choiceField(id, label, choices, selected, multi, req) = node {
            XCTAssertEqual(id, "pick")
            XCTAssertEqual(label, "Pick one")
            XCTAssertEqual(choices.map(\.title), ["A", "B"])
            XCTAssertEqual(choices.map(\.value), ["a", "b"])
            XCTAssertEqual(selected, "b")
            XCTAssertFalse(multi)
            XCTAssertFalse(req)
        } else {
            XCTFail("expected .choiceField")
        }
    }

    func testProgressBarClampsAndCarriesLabel() {
        XCTAssertEqual(
            renderer.render(element: .progressBar(ProgressBar(value: 0.5, label: "L"))),
            .progressBar(value: 0.5, label: "L")
        )
        XCTAssertEqual(
            renderer.render(element: .progressBar(ProgressBar(value: 2.0))),
            .progressBar(value: 1.0, label: nil)
        )
        XCTAssertEqual(
            renderer.render(element: .progressBar(ProgressBar(value: -1))),
            .progressBar(value: 0.0, label: nil)
        )
    }

    func testSpinnerCarriesLabel() {
        XCTAssertEqual(
            renderer.render(element: .spinner(Spinner(label: "Loading"))),
            .spinner(label: "Loading")
        )
    }

    func testAccordionRecursesIntoPanels() {
        let acc = Accordion(panels: [
            AccordionPanel(title: "T", content: [.textBlock(TextBlock(text: "hi"))], isExpanded: true)
        ])
        let node = renderer.render(element: .accordion(acc))
        guard case let .accordion(panels) = node else { return XCTFail("expected .accordion") }
        XCTAssertEqual(panels.count, 1)
        XCTAssertEqual(panels[0].title, "T")
        XCTAssertTrue(panels[0].isExpanded)
        XCTAssertEqual(panels[0].content.count, 1)
    }

    func testRichTextBlockEmitsVerticalStackOfRichRuns() {
        let rtb = RichTextBlock(inlines: [
            TextRun(text: "Hello "),
            TextRun(text: "world", weight: .bolder, italic: true),
        ])
        let node = renderer.render(element: .richTextBlock(rtb))
        guard case let .verticalStack(_, runs) = node else {
            return XCTFail("expected verticalStack of richRuns")
        }
        XCTAssertEqual(runs.count, 2)
    }

    func testCodeBlockProducesCode() {
        let cb = CodeBlock(code: "let x = 1", language: "swift")
        let node = renderer.render(element: .codeBlock(cb))
        XCTAssertEqual(node, .code(text: "let x = 1", language: "swift", wrap: true))
    }
}
