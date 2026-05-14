//
//  main.swift
//  AdaptiveCardsValidate — windows-port headless validation harness
//
//  Runs the same assertions as `AdaptiveCardsCrossUITests` but as a plain
//  executable so the validation loop works on every platform that
//  compiles `AdaptiveCardsCrossUI`. On Windows, `swift test` insists on
//  building every Apple-only sibling target (ACFluentUI etc.) which fails
//  to import SwiftUI — this binary side-steps that entirely.
//
//  Usage:
//      swift run AdaptiveCardsValidate              (default reference set)
//      swift run AdaptiveCardsValidate --all        (every JSON in shared/test-cards)
//
//  Exit code 0 on success, 1 on any failure. One line of output per
//  check; final summary count at the end.
//

import Foundation
import ACCore
import AdaptiveCardsCrossUI
import AdaptiveCardsWindowsEmbedded
import AdaptiveCardsCABI

// MARK: - Minimal test runner

final class Runner {
    var passed = 0
    var failed = 0
    var failures: [String] = []

    func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if condition {
            passed += 1
            print("  ok   \(message())")
        } else {
            failed += 1
            failures.append(message())
            print("  FAIL \(message())")
        }
    }

    func equal<T: Equatable>(_ lhs: T, _ rhs: T, _ context: String) {
        check(lhs == rhs, "\(context): expected \(rhs), got \(lhs)")
    }

    func section(_ title: String) {
        print("\n[\(title)]")
    }

    func summary() -> Int32 {
        print("\n== Summary ==")
        print("  passed: \(passed)")
        print("  failed: \(failed)")
        if !failures.isEmpty {
            print("\nFailures:")
            for f in failures { print("  - \(f)") }
        }
        return failed == 0 ? 0 : 1
    }
}

// MARK: - Test suites

func runRendererUnitChecks(_ r: Runner) {
    r.section("Renderer unit checks")
    let renderer = Renderer()

    // TextBlock
    let tb1 = TextBlock(text: "Hello")
    r.equal(
        renderer.render(element: .textBlock(tb1)),
        .text("Hello", size: .default, weight: .default, wrap: false, isSubtle: false),
        "TextBlock basic"
    )
    let tb2 = TextBlock(text: "Big", size: .large, weight: .bolder, wrap: true)
    r.equal(
        renderer.render(element: .textBlock(tb2)),
        .text("Big", size: .large, weight: .bolder, wrap: true, isSubtle: false),
        "TextBlock large+bolder+wrap"
    )

    // Image
    let img = Image(url: "https://example.com/x.png", altText: "Example", size: .small)
    r.equal(
        renderer.render(element: .image(img)),
        .image(url: "https://example.com/x.png", alt: "Example", displayHint: .small),
        "Image url+alt+size"
    )

    // Container
    let inner = Container(items: [.textBlock(TextBlock(text: "inside"))])
    if case let .verticalStack(_, children) = renderer.render(element: .container(inner)) {
        r.equal(children.count, 1, "Container child count")
        r.equal(children.first, .text("inside", size: .default, weight: .default, wrap: false, isSubtle: false), "Container child text")
    } else {
        r.check(false, "Container should render to verticalStack")
    }

    // ColumnSet
    let cs = ColumnSet(columns: [
        Column(items: [.textBlock(TextBlock(text: "A"))]),
        Column(items: [.textBlock(TextBlock(text: "B"))]),
    ])
    if case let .horizontalStack(_, cols) = renderer.render(element: .columnSet(cs)) {
        r.equal(cols.count, 2, "ColumnSet column count")
    } else {
        r.check(false, "ColumnSet should render to horizontalStack")
    }

    // FactSet
    let fs = FactSet(facts: [
        .init(title: "Owner", value: "Hugo"),
        .init(title: "Version", value: "1.6"),
    ])
    if case let .facts(pairs) = renderer.render(element: .factSet(fs)) {
        r.equal(pairs.count, 2, "FactSet pair count")
        r.equal(pairs[0].title, "Owner", "FactSet first title")
    } else {
        r.check(false, "FactSet should render to facts")
    }

    // Actions
    let submit = SubmitAction(title: "Send")
    if case let .button(title, kind) = renderer.render(action: .submit(submit)) {
        r.equal(title, "Send", "Submit button title")
        if case .submit = kind { r.check(true, "Submit kind") }
        else { r.check(false, "Submit kind should be .submit") }
    } else {
        r.check(false, "Submit should render as button")
    }
    r.equal(
        renderer.render(action: .openUrl(OpenUrlAction(title: "Open", url: "https://example.com"))),
        .button(title: "Open", kind: .openUrl("https://example.com")),
        "OpenUrl maps to button"
    )

    // Unsupported placeholders (elements we haven't wired)
    r.equal(
        renderer.render(element: .unknown(type: "Carousel.Future")),
        .unsupported(typeString: "Carousel.Future"),
        "Unknown maps to unsupported"
    )
    // Inputs map to interactive IR nodes — the demo wires them to live
    // swift-cross-ui widgets, but headlessly we just assert IR shape.
    if case let .textField(id, _, _, _, _, _) = renderer.render(element: .textInput(TextInput(id: "name"))) {
        r.equal(id, "name", "Input.Text -> textField id")
    } else {
        r.check(false, "Input.Text should map to .textField")
    }

    // Toggle should preserve valueOn / valueOff for the submit payload.
    let toggle = ToggleInput(id: "sub", title: "Subscribe", value: "yes", valueOn: "yes", valueOff: "no")
    if case let .toggleField(_, _, _, value, on, off, _) = renderer.render(element: .toggleInput(toggle)) {
        r.check(value, "Toggle current-value should resolve to .on")
        r.equal(on, "yes", "Toggle valueOn preserved")
        r.equal(off, "no", "Toggle valueOff preserved")
    } else {
        r.check(false, "Input.Toggle should map to .toggleField")
    }

    // ChoiceSet should carry title+value pairs.
    let choice = ChoiceSetInput(
        id: "color",
        choices: [.init(title: "Red", value: "r"), .init(title: "Blue", value: "b")],
        value: "b"
    )
    if case let .choiceField(_, _, opts, selected, _, _) = renderer.render(element: .choiceSetInput(choice)) {
        r.equal(opts.map(\.value), ["r", "b"], "ChoiceSet wire values")
        r.equal(selected, "b", "ChoiceSet selected value")
    } else {
        r.check(false, "Input.ChoiceSet should map to .choiceField")
    }

    // New display elements: ProgressBar, Spinner, Accordion.
    r.equal(
        renderer.render(element: .progressBar(ProgressBar(value: 0.42, label: "Loading"))),
        .progressBar(value: 0.42, label: "Loading"),
        "ProgressBar"
    )
    r.equal(
        renderer.render(element: .spinner(Spinner(label: "Working"))),
        .spinner(label: "Working"),
        "Spinner"
    )
    let accordion = Accordion(panels: [
        AccordionPanel(title: "P1", content: [.textBlock(TextBlock(text: "inside"))], isExpanded: true),
        AccordionPanel(title: "P2", content: [], isExpanded: false),
    ])
    if case let .accordion(panels) = renderer.render(element: .accordion(accordion)) {
        r.equal(panels.count, 2, "Accordion panel count")
        r.check(panels[0].isExpanded, "Panel 0 expanded")
        r.equal(panels[0].title, "P1", "Panel 0 title")
    } else {
        r.check(false, "Accordion should map to .accordion")
    }

    // Out-of-range progress is clamped.
    r.equal(
        renderer.render(element: .progressBar(ProgressBar(value: 1.5))),
        .progressBar(value: 1.0, label: nil),
        "ProgressBar clamps >1 to 1"
    )
    r.equal(
        renderer.render(element: .progressBar(ProgressBar(value: -0.5))),
        .progressBar(value: 0.0, label: nil),
        "ProgressBar clamps <0 to 0"
    )

    // Table renderer: first row -> headers when firstRowAsHeaders is true (default).
    let table = Table(
        rows: [
            TableRow(cells: [
                TableCell(items: [.textBlock(TextBlock(text: "H1"))]),
                TableCell(items: [.textBlock(TextBlock(text: "H2"))]),
            ]),
            TableRow(cells: [
                TableCell(items: [.textBlock(TextBlock(text: "A1"))]),
                TableCell(items: [.textBlock(TextBlock(text: "A2"))]),
            ]),
        ]
    )
    if case let .table(headers, rows) = renderer.render(element: .table(table)) {
        r.check(headers != nil, "Table headers extracted when firstRowAsHeaders defaults to true")
        r.equal(rows.count, 1, "Table body row count after header split")
        r.equal(headers?.count ?? 0, 2, "Table header cell count")
    } else {
        r.check(false, "Table should map to .table")
    }

    // firstRowAsHeaders explicitly false -> headers is nil, all rows are body.
    let noHeader = Table(
        rows: [
            TableRow(cells: [TableCell(items: [.textBlock(TextBlock(text: "R1"))])]),
            TableRow(cells: [TableCell(items: [.textBlock(TextBlock(text: "R2"))])]),
        ],
        firstRowAsHeaders: false
    )
    if case let .table(headers, rows) = renderer.render(element: .table(noHeader)) {
        r.check(headers == nil, "Table headers nil when firstRowAsHeaders=false")
        r.equal(rows.count, 2, "All rows are body when no header")
    } else {
        r.check(false, "Table (no-header) should map to .table")
    }

    // Rating display.
    r.equal(
        renderer.render(element: .ratingDisplay(RatingDisplay(value: 4.5, count: 128, max: 5))),
        .rating(value: 4.5, max: 5, count: 128),
        "RatingDisplay propagates value/max/count"
    )
    r.equal(
        renderer.render(element: .ratingDisplay(RatingDisplay(value: 3))),
        .rating(value: 3, max: 5, count: nil),
        "RatingDisplay defaults max to 5"
    )

    // DateInput / TimeInput map to read-only fields.
    if case let .dateField(id, label, _, value, req) = renderer.render(element: .dateInput(DateInput(id: "d", isRequired: true, label: "Date", value: "2025-01-01"))) {
        r.equal(id, "d", "DateInput id")
        r.equal(label, "Date", "DateInput label")
        r.equal(value, "2025-01-01", "DateInput value")
        r.check(req, "DateInput required")
    } else {
        r.check(false, "Input.Date should map to .dateField")
    }
    if case let .timeField(id, _, placeholder, _, _) = renderer.render(element: .timeInput(TimeInput(id: "t", placeholder: "HH:MM"))) {
        r.equal(id, "t", "TimeInput id")
        r.equal(placeholder, "HH:MM", "TimeInput placeholder")
    } else {
        r.check(false, "Input.Time should map to .timeField")
    }

    // Card-level
    let card = AdaptiveCard(
        body: [.textBlock(TextBlock(text: "hi"))],
        actions: [.submit(SubmitAction(title: "Go"))]
    )
    if case let .verticalStack(_, children) = renderer.render(card: card) {
        r.equal(children.count, 2, "Card top-level children = body + actions row")
    } else {
        r.check(false, "Card top-level should be verticalStack")
    }
}

func runSubmitPayloadChecks(_ r: Runner) {
    r.section("Action.Submit payload merge")

    // Empty merge — nothing to add — should pass static JSON through.
    r.equal(
        SubmitPayload.merge(staticJSON: nil),
        nil,
        "nil + empty state -> nil"
    )
    r.equal(
        SubmitPayload.merge(staticJSON: #"{"k":"v"}"#),
        #"{"k":"v"}"#,
        "static-only passes through unchanged"
    )

    // Form state alone (no static data).
    r.equal(
        SubmitPayload.merge(
            staticJSON: nil,
            textValues: ["name": "Alice", "age": "30"]
        ),
        #"{"age":"30","name":"Alice"}"#,
        "text-only merge with sorted keys"
    )

    // Merge order: form values override static data on the same key.
    r.equal(
        SubmitPayload.merge(
            staticJSON: #"{"name":"placeholder","tag":"x"}"#,
            textValues: ["name": "Bob"]
        ),
        #"{"name":"Bob","tag":"x"}"#,
        "form values override static data on shared keys"
    )

    // Toggle resolution: caller is responsible for converting Bool -> string.
    r.equal(
        SubmitPayload.merge(
            staticJSON: nil,
            toggleValues: ["subscribe": "yes"]
        ),
        #"{"subscribe":"yes"}"#,
        "toggle merged as caller-resolved string"
    )

    // Choice merge with nil-valued entries dropped.
    r.equal(
        SubmitPayload.merge(
            staticJSON: nil,
            choiceValues: ["color": "blue", "shape": nil]
        ),
        #"{"color":"blue"}"#,
        "choiceValues with nil are dropped"
    )

    // Combined merge mimicking a full input-form submit.
    r.equal(
        SubmitPayload.merge(
            staticJSON: #"{"verb":"submit"}"#,
            textValues: ["name": "Alice", "age": "30"],
            toggleValues: ["subscribe": "yes"],
            choiceValues: ["color": "blue"]
        ),
        #"{"age":"30","color":"blue","name":"Alice","subscribe":"yes","verb":"submit"}"#,
        "combined merge with all input types"
    )

    // Date / time round-trip via the SubmitPayload formatters. These
    // strings are the Adaptive Cards spec wire format for Input.Date
    // and Input.Time and need to be bit-stable across platforms.
    if let d = SubmitPayload.parseDate("2025-01-15") {
        r.equal(SubmitPayload.iso8601DateString(from: d), "2025-01-15", "Date round-trip")
    } else {
        r.check(false, "Date parse failed")
    }
    if let t = SubmitPayload.parseTime("13:45") {
        r.equal(SubmitPayload.iso8601TimeString(from: t), "13:45", "Time round-trip")
    } else {
        r.check(false, "Time parse failed")
    }
    r.check(SubmitPayload.parseDate("not-a-date") == nil, "parseDate rejects garbage")
    r.check(SubmitPayload.parseDate(nil) == nil, "parseDate rejects nil")
    r.check(SubmitPayload.parseDate("") == nil, "parseDate rejects empty")
}

func runReferenceSampleChecks(_ r: Runner) {
    r.section("Reference sample-card validation (parse + render)")
    do {
        let pairs = try SampleCardLibrary.loadReferenceSet()
        r.equal(pairs.count, SampleCardLibrary.referenceSampleFilenames.count, "Reference sample count")
        let renderer = Renderer()
        for (name, card) in pairs {
            let tree = renderer.render(card: card)
            switch tree {
            case let .verticalStack(_, children):
                if name == "edge-empty-card.json" {
                    r.check(children.isEmpty, "\(name) renders to empty tree (expected)")
                } else {
                    r.check(!children.isEmpty, "\(name) renders to non-empty tree")
                }
            default:
                r.check(false, "\(name) top-level must be verticalStack")
            }
        }
    } catch {
        r.check(false, "Reference sample load: \(error)")
    }
}

func runBroadParseChecks(_ r: Runner) {
    r.section("Broad parse coverage (every *.json in shared/test-cards/)")

    // Templating samples are pre-expansion templates with `${var}` placeholders
    // in spec-typed slots like `color`. They require ACTemplating to materialize
    // before CardParser can decode them — that module is Apple-only today, so
    // we skip these in the v1 Windows parse loop. When the cross-UI templating
    // engine lands, these files become first-class.
    let templatingSkiplist: Set<String> = [
        "templating-basic.json",
        "templating-conditional.json",
        "templating-expressions.json",
        "templating-iteration.json",
        "templating-nested.json",
    ]

    do {
        let allNames = try SampleCardLibrary.allTopLevelCardFilenames()
        let names = allNames.filter { !templatingSkiplist.contains($0) }
        r.check(names.count > 20, "Static sample set count > 20 (\(names.count))")
        var localPass = 0
        for name in names {
            do {
                _ = try SampleCardLibrary.load(filename: name)
                localPass += 1
            } catch {
                r.check(false, "Parse \(name): \(error.localizedDescription)")
            }
        }
        print("  parsed \(localPass)/\(names.count) static cards; skipped \(templatingSkiplist.count) templating samples")
        r.equal(localPass, names.count, "All static top-level cards parse")
    } catch {
        r.check(false, "Broad parse: \(error)")
    }
}

// MARK: - Entry point

func runAll() -> Int32 {
    let args = CommandLine.arguments.dropFirst()
    let updateSnapshots = args.contains("--update-snapshots")

    let runner = Runner()
    print("AdaptiveCardsValidate · windows-port headless harness")
    print("Sample cards dir: \(SampleCardLibrary.testCardsDirectory.path)")
    print("Snapshot dir:     \(Snapshots.snapshotsDirectory.path)")

    runRendererUnitChecks(runner)
    runSubmitPayloadChecks(runner)
    runReferenceSampleChecks(runner)
    runBroadParseChecks(runner)
    runCABIChecks(runner)
    Snapshots.runSnapshotChecks(runner, updateBaselines: updateSnapshots)
    A11yBaselines.runChecks(runner, updateBaselines: updateSnapshots)

    return runner.summary()
}

exit(runAll())
