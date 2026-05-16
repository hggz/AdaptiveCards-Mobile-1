//
//  RenderingTree.swift
//  AdaptiveCardsCrossUI — windows-port
//
//  A pure-Swift, platform-neutral data tree that mirrors what
//  ``AdaptiveCardView`` will render via swift-cross-ui. The tree exists so
//  that:
//
//    1. The element-to-view mapping is unit-testable on any platform Swift
//       supports, including Linux and macOS CI runners that have no display.
//    2. CI smoke jobs can serialise the tree as JSON for snapshot regression
//       without ever spawning a window.
//    3. The Swift-cross-UI rendering layer (`AdaptiveCardView.swift`) does
//       not need any conditional logic for what to draw — it just walks
//       this tree.
//
//  Anything user-visible that the renderer produces MUST flow through this
//  tree. Adding a new element type means: add a `RenderingNode` case here,
//  emit it from `Renderer.render`, and walk it in `AdaptiveCardView`.
//

import Foundation
import ACCore

/// A single option in an `Input.ChoiceSet`.
public struct ChoiceOption: Equatable, Sendable, Codable {
    public var title: String
    public var value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

/// One panel in an `Accordion` element. Content is itself a tree so the
/// renderer can put arbitrary card elements inside a panel body.
public struct AccordionPanel: Equatable, Sendable {
    public var title: String
    public var content: [RenderingNode]
    public var isExpanded: Bool

    public init(title: String, content: [RenderingNode], isExpanded: Bool) {
        self.title = title
        self.content = content
        self.isExpanded = isExpanded
    }
}

/// A single (label, value) pair for any chart kind. Optional color is
/// the spec's `#RRGGBB` token; the View layer may ignore it.
public struct ChartDatum: Equatable, Sendable, Codable {
    public var label: String
    public var value: Double
    public var color: String?

    public init(label: String, value: Double, color: String? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }
}

/// Which chart visualization to apply to the data.
public enum ChartKind: String, Equatable, Sendable, Codable {
    case donut
    case bar
    case line
    case pie
}

/// Marker convention for `List` items. `default` produces no marker
/// (essentially a vertical stack), `bulleted` uses `•`, `numbered`
/// uses `1.`, `2.`, ... Per the AdaptiveCards 1.6 spec.
public enum ListStyle: String, Equatable, Sendable, Codable {
    case `default`
    case bulleted
    case numbered
}

/// One tab in a `TabSet`. Body is rendered when this tab is the
/// selected one; the a11y dump enumerates every tab regardless.
public struct TabItem: Equatable, Sendable {
    public var id: String
    public var title: String
    public var content: [RenderingNode]

    public init(id: String, title: String, content: [RenderingNode]) {
        self.id = id
        self.title = title
        self.content = content
    }
}

/// One slide in a `Carousel`. Body is rendered when this page is the
/// currently-selected one (in v1 that means `selectedPageIndex` from
/// the IR; live page switching is parked alongside TabSet's). The
/// optional `selectAction` is the page-level click target, propagated
/// from `CarouselPage.selectAction` in ACCore.
public struct CarouselPageItem: Equatable, Sendable {
    public var id: String
    public var content: [RenderingNode]
    public var selectAction: RenderingNode.ActionKind?

    public init(
        id: String,
        content: [RenderingNode],
        selectAction: RenderingNode.ActionKind? = nil
    ) {
        self.id = id
        self.content = content
        self.selectAction = selectAction
    }
}

/// A platform-neutral description of what a card or element will draw.
///
/// `RenderingNode` is *not* a `View` — it's the intermediate representation
/// between the Adaptive Cards ObjectModel (`ACCore`) and the
/// swift-cross-ui view graph. Snapshot tests assert on the shape of this
/// tree; the swift-cross-ui rendering is a thin walk.
public indirect enum RenderingNode: Equatable, Sendable {

    /// A run of text.
    case text(
        String,
        size: TextSize = .default,
        weight: TextWeight = .default,
        wrap: Bool = false,
        isSubtle: Bool = false
    )

    /// A rich-text inline run (used by `RichTextBlock`).
    case richRun(
        String,
        size: TextSize = .default,
        weight: TextWeight = .default,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        isSubtle: Bool = false
    )

    /// A bitmap or remote image. `alt` is required for accessibility.
    case image(url: String, alt: String, displayHint: ImageDisplayHint = .medium)

    /// A vertical stack of children. Used for `Container` and the card body.
    case verticalStack(spacing: Int, children: [RenderingNode])

    /// A horizontal stack of children. Used for `ColumnSet`.
    case horizontalStack(spacing: Int, children: [RenderingNode])

    /// A FactSet — pairs of (title, value).
    case facts([(title: String, value: String)])

    /// A pre-formatted code block.
    case code(text: String, language: String?, wrap: Bool)

    /// Interactive `Input.Text` field. Initial value comes from the IR;
    /// the view layer owns the live state and writes back into
    /// `Action.Submit.data` on submit.
    case textField(
        id: String,
        label: String?,
        placeholder: String?,
        value: String?,
        isRequired: Bool,
        isMultiline: Bool
    )

    /// Interactive `Input.Number` field.
    case numberField(
        id: String,
        label: String?,
        placeholder: String?,
        value: Double?,
        isRequired: Bool
    )

    /// Interactive `Input.Toggle`. `valueOn` / `valueOff` are emitted into
    /// the submit payload as the spec requires (strings, not booleans).
    case toggleField(
        id: String,
        title: String,
        label: String?,
        value: Bool,
        valueOn: String,
        valueOff: String,
        isRequired: Bool
    )

    /// Interactive `Input.ChoiceSet`. Choices carry both a display title
    /// and the wire value sent in the submit payload.
    case choiceField(
        id: String,
        label: String?,
        choices: [ChoiceOption],
        selected: String?,
        isMultiSelect: Bool,
        isRequired: Bool
    )

    /// `ProgressBar` element. `value` is in 0...1.
    case progressBar(value: Double, label: String?)

    /// `Spinner` element (indeterminate progress).
    case spinner(label: String?)

    /// `Accordion` element with one or more expandable panels.
    case accordion(panels: [AccordionPanel])

    /// `Table` element. `headers` is `nil` when `firstRowAsHeaders` is
    /// false; otherwise it carries the column header cells.
    case table(headers: [[RenderingNode]]?, rows: [[[RenderingNode]]])

    /// `Rating` display element. `value` is the current score (0...max);
    /// `count` is an optional rating-count number (e.g. "(123)").
    case rating(value: Double, max: Int, count: Int?)

    /// Read-only display of an `Input.Date` field. Interactive date
    /// pickers are a future step.
    case dateField(
        id: String,
        label: String?,
        placeholder: String?,
        value: String?,
        isRequired: Bool
    )

    /// Read-only display of an `Input.Time` field.
    case timeField(
        id: String,
        label: String?,
        placeholder: String?,
        value: String?,
        isRequired: Bool
    )

    /// Chart element. The same IR represents every chart kind
    /// (`Donut`, `Bar`, `Line`, `Pie`); the View layer picks a
    /// visualization per `kind`. The IR keeps the raw data so a11y
    /// dumps can describe label/value pairs verbatim.
    case chart(
        kind: ChartKind,
        title: String?,
        data: [ChartDatum],
        showLegend: Bool
    )

    /// `TabSet` element. The renderer pre-resolves which tab is
    /// initially selected via `selectedTabIndex`; the View renders
    /// that tab's content while showing the full tab strip for
    /// screen-reader / keyboard navigation.
    case tabSet(tabs: [TabItem], selectedTabIndex: Int)

    /// `Carousel` element. The renderer pre-resolves which page is
    /// initially shown via `selectedPageIndex` (clamped against
    /// `pages.count`); the View renders that page's content while
    /// showing a page-position indicator. Live page switching is
    /// parked alongside TabSet's; `autoAdvanceMs` carries the spec's
    /// optional auto-rotate timer through so a future v2 can honour
    /// it without an IR re-shape.
    case carousel(
        pages: [CarouselPageItem],
        selectedPageIndex: Int,
        autoAdvanceMs: Int?
    )

    /// `List` element. A vertical stack of child nodes prefixed with
    /// a marker per `style` (none / `•` / `1.`). Distinct from the
    /// generic `verticalStack` because the marker is part of the
    /// element's accessible semantics: screen readers should announce
    /// "list, N items" before iterating, which the View can layer on
    /// top of the IR.
    case list(style: ListStyle, items: [RenderingNode])

    /// `CompoundButton` element. Renders as a button bearing a title
    /// + subtitle stack; firing the action goes through the standard
    /// `onAction` callback.
    case compoundButton(
        title: String,
        subtitle: String?,
        icon: String?,
        action: ActionKind?
    )

    /// Button row (action set or card-level actions).
    case button(title: String, kind: ActionKind)

    /// Placeholder for elements we haven't wired yet.
    case unsupported(typeString: String)

    public enum TextSize: String, Sendable {
        case small
        case `default`
        case medium
        case large
        case extraLarge
    }

    public enum TextWeight: String, Sendable {
        case lighter
        case `default`
        case bolder
    }

    public enum ImageDisplayHint: String, Sendable {
        case small
        case medium
        case large
        case stretch
    }

    /// The Adaptive Cards action class a button maps to.
    public enum ActionKind: Equatable, Sendable {
        case submit(dataJSON: String?)
        case openUrl(String)
        case showCard
        case execute
        case toggleVisibility
        case popover
        case runCommands
        case openUrlDialog
        case unknown(String)
    }
}

// MARK: - Manual Equatable
//
// Tuples aren't Equatable inside arrays automatically, so the
// synthesised `==` can't be used. We hand-roll the whole thing.
extension RenderingNode {
    public static func == (lhs: RenderingNode, rhs: RenderingNode) -> Bool {
        switch (lhs, rhs) {
        case let (.text(la, ls, lw, lwrap, lsub), .text(ra, rs, rw, rwrap, rsub)):
            return la == ra && ls == rs && lw == rw && lwrap == rwrap && lsub == rsub

        case let (.richRun(la, ls, lw, li, lu, lst, lsub),
                  .richRun(ra, rs, rw, ri, ru, rst, rsub)):
            return la == ra && ls == rs && lw == rw && li == ri
                && lu == ru && lst == rst && lsub == rsub

        case let (.image(lu, lalt, lh), .image(ru, ralt, rh)):
            return lu == ru && lalt == ralt && lh == rh

        case let (.verticalStack(ls, lc), .verticalStack(rs, rc)):
            return ls == rs && lc == rc

        case let (.horizontalStack(ls, lc), .horizontalStack(rs, rc)):
            return ls == rs && lc == rc

        case let (.facts(l), .facts(r)):
            guard l.count == r.count else { return false }
            for i in l.indices where l[i].title != r[i].title || l[i].value != r[i].value {
                return false
            }
            return true

        case let (.code(lt, ll, lw), .code(rt, rl, rw)):
            return lt == rt && ll == rl && lw == rw

        case let (.textField(li, ll, lp, lv, lr, lm),
                  .textField(ri, rl, rp, rv, rr, rm)):
            return li == ri && ll == rl && lp == rp && lv == rv
                && lr == rr && lm == rm

        case let (.numberField(li, ll, lp, lv, lr),
                  .numberField(ri, rl, rp, rv, rr)):
            return li == ri && ll == rl && lp == rp && lv == rv && lr == rr

        case let (.toggleField(li, lt, ll, lv, lon, loff, lr),
                  .toggleField(ri, rt, rl, rv, ron, roff, rr)):
            return li == ri && lt == rt && ll == rl && lv == rv
                && lon == ron && loff == roff && lr == rr

        case let (.choiceField(li, ll, lc, ls, lm, lr),
                  .choiceField(ri, rl, rc, rs, rm, rr)):
            return li == ri && ll == rl && lc == rc && ls == rs
                && lm == rm && lr == rr

        case let (.progressBar(lv, ll), .progressBar(rv, rl)):
            return lv == rv && ll == rl

        case let (.spinner(ll), .spinner(rl)):
            return ll == rl

        case let (.accordion(lp), .accordion(rp)):
            return lp == rp

        case let (.table(lh, lr), .table(rh, rr)):
            return lh == rh && lr == rr

        case let (.rating(lv, lm, lc), .rating(rv, rm, rc)):
            return lv == rv && lm == rm && lc == rc

        case let (.dateField(li, ll, lp, lv, lr),
                  .dateField(ri, rl, rp, rv, rr)):
            return li == ri && ll == rl && lp == rp && lv == rv && lr == rr

        case let (.timeField(li, ll, lp, lv, lr),
                  .timeField(ri, rl, rp, rv, rr)):
            return li == ri && ll == rl && lp == rp && lv == rv && lr == rr

        case let (.chart(lk, lt, ld, lleg), .chart(rk, rt, rd, rleg)):
            return lk == rk && lt == rt && ld == rd && lleg == rleg

        case let (.tabSet(lt, ls), .tabSet(rt, rs)):
            return lt == rt && ls == rs

        case let (.carousel(lp, ls, lt), .carousel(rp, rs, rt)):
            return lp == rp && ls == rs && lt == rt

        case let (.list(ls, li), .list(rs, ri)):
            return ls == rs && li == ri

        case let (.compoundButton(lt, ls, li, la),
                  .compoundButton(rt, rs, ri, ra)):
            return lt == rt && ls == rs && li == ri && la == ra

        case let (.button(lt, lk), .button(rt, rk)):
            return lt == rt && lk == rk

        case let (.unsupported(l), .unsupported(r)):
            return l == r

        default:
            return false
        }
    }
}
