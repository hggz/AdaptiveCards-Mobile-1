//
//  main.swift
//  AdaptiveCardsWindowsDemo — windows-port
//
//  Standalone executable that proves the Windows rendering path end-to-end.
//
//  Usage from the dev shell:
//      swift run AdaptiveCardsWindowsDemo
//
//  Behaviour:
//    * Loads the curated reference sample set via `SampleCardLibrary`.
//    * Opens a single window containing a card-picker `Picker` and a
//      `ScrollView` that renders the currently-selected card with
//      `AdaptiveCardView`.
//    * On every `Action.Submit` / `Action.OpenUrl` press, the title and
//      kind are appended to a transcript in the window — the imperative
//      validation loop the user can run with their eyes.
//
//  No HTTP fetching, no image decoding for remote URLs — those land in
//  subsequent steps. The point of v1 is to confirm: parse with ACCore,
//  render with AdaptiveCardsCrossUI, draw with swift-cross-ui's WinUI
//  backend, route actions through `onAction`.
//

import Foundation
import DefaultBackend
import SwiftCrossUI
import ACCore
import AdaptiveCardsCrossUI

@main
struct AdaptiveCardsWindowsDemo: App {
    typealias Backend = DefaultBackend

    @State var selected: String? = {
        // Allow CI / dev to preselect a sample for screenshot capture by
        // setting the AC_DEFAULT_SAMPLE env var.
        if let preselect = ProcessInfo.processInfo.environment["AC_DEFAULT_SAMPLE"],
           SampleCardLibrary.referenceSampleFilenames.contains(preselect) {
            return preselect
        }
        return SampleCardLibrary.referenceSampleFilenames.first
    }()
    @State var transcript: [String] = []
    @State var loadError: String? = nil

    var availableFilenames: [String] {
        SampleCardLibrary.referenceSampleFilenames
    }

    var body: some Scene {
        WindowGroup("Adaptive Cards · Windows") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Adaptive Cards · Windows port demo")

                HStack(spacing: 8) {
                    Text("Sample:")
                    Picker(of: availableFilenames, selection: $selected)
                }

                Divider()

                if let name = selected {
                    cardView(for: name)
                } else {
                    Text("Pick a card above to render it.")
                }

                Divider()

                Text("Action transcript")
                if transcript.isEmpty {
                    Text("(no actions yet — submit or open-url from the card above)")
                } else {
                    ForEach(Array(transcript.suffix(8).enumerated()), id: \.offset) { _, line in
                        Text("• " + line)
                    }
                }
            }
            .padding(16)
        }
        .defaultSize(width: 820, height: 720)
    }

    @ViewBuilder
    private func cardView(for filename: String) -> some View {
        if let err = loadError {
            Text("Load error: \(err)")
        }
        let result = loadSafely(filename)
        switch result {
        case .success(let card):
            AdaptiveCardView(card: card) { action in
                transcript.append("\(filename) -> \(describe(action))")
            }
        case .failure(let err):
            Text("Failed to load \(filename): \(err.localizedDescription)")
        }
    }

    private func loadSafely(_ filename: String) -> Result<AdaptiveCard, Error> {
        do { return .success(try SampleCardLibrary.load(filename: filename)) }
        catch { return .failure(error) }
    }

    private func describe(_ action: RenderingNode.ActionKind) -> String {
        switch action {
        case .submit(let data): return "Action.Submit data=\(data ?? "nil")"
        case .openUrl(let url): return "Action.OpenUrl \(url)"
        case .showCard: return "Action.ShowCard"
        case .execute: return "Action.Execute"
        case .toggleVisibility: return "Action.ToggleVisibility"
        case .popover: return "Action.Popover"
        case .runCommands: return "Action.RunCommands"
        case .openUrlDialog: return "Action.OpenUrlDialog"
        case .unknown(let s): return "unknown(\(s))"
        }
    }
}
