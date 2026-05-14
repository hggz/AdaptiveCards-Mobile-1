//
//  A11yBaselines.swift
//  AdaptiveCardsValidate — windows-port
//
//  Walks the same 7 reference cards `Snapshots` does, but emits an
//  IR-level a11y dump per card (via `A11yDump`) and diffs against a
//  committed baseline under
//  `Sources/AdaptiveCardsValidate/A11yBaselines/<card>.a11y.txt`.
//
//  Rationale: live UI Automation walking against WinUI 3 surfaces is
//  fragile in headless CI (System.Windows.Automation returns
//  E_UNEXPECTED, the CUIAutomation ProgID is not registered on the
//  windows-2022 runner). The IR walk produces the same review signal
//  — role + accessible name + flags — without depending on a running
//  GUI or the Windows-only UIA stack. It also runs on macOS / Linux,
//  so the a11y gate is part of every job, not just Windows.
//

import Foundation
import ACCore
import AdaptiveCardsCrossUI

enum A11yBaselines {

    static let baselineDirectory: URL = {
        // Sources/AdaptiveCardsValidate/A11yBaselines.swift  =>
        // Sources/AdaptiveCardsValidate/A11yBaselines/
        let here = URL(fileURLWithPath: #filePath)
        return here.deletingLastPathComponent()
            .appendingPathComponent("A11yBaselines", isDirectory: true)
    }()

    static func baselinePath(for filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        return baselineDirectory
            .appendingPathComponent(base + ".a11y.txt", isDirectory: false)
    }

    static func runChecks(_ r: Runner, updateBaselines: Bool) {
        r.section(
            "A11y IR baselines (role + accessible name + flags)"
            + (updateBaselines ? " (UPDATE MODE)" : "")
        )

        let pairs: [(String, AdaptiveCard)]
        do { pairs = try SampleCardLibrary.loadReferenceSet() }
        catch {
            r.check(false, "load reference set: \(error)")
            return
        }

        try? FileManager.default.createDirectory(
            at: baselineDirectory,
            withIntermediateDirectories: true
        )

        let renderer = Renderer()
        for (name, card) in pairs {
            let tree = renderer.render(card: card)
            let dump = A11yDump.dump(tree)

            let path = baselinePath(for: name)
            if updateBaselines {
                do {
                    try dump.write(to: path, atomically: true, encoding: .utf8)
                    print("  wrote \(path.lastPathComponent)")
                    r.check(true, "\(name) a11y baseline written")
                } catch {
                    r.check(false, "write \(name) a11y baseline: \(error)")
                }
                continue
            }

            // Diff mode (CI default).
            guard FileManager.default.fileExists(atPath: path.path) else {
                r.check(
                    false,
                    "\(name) a11y baseline missing at \(path.path) — run with --update-snapshots to bootstrap"
                )
                continue
            }
            let onDisk: String
            do {
                onDisk = try String(contentsOf: path, encoding: .utf8)
            } catch {
                r.check(false, "read \(name) a11y baseline: \(error)")
                continue
            }
            if dump == onDisk {
                r.check(true, "\(name) a11y baseline matches")
            } else {
                r.check(
                    false,
                    "\(name) a11y baseline DRIFT — first diff: \(firstDiffLine(dump, onDisk))"
                )
            }
        }

        // Statistical summary: count violations across all reference
        // cards. A "violation" is a marker token in the dump like
        // MISSING_LABEL / MISSING_ALT / UNRENDERED. These don't fail
        // the run by themselves (the baseline diff does), but the
        // count is logged for reviewer visibility.
        var missingLabels = 0
        var missingAlts = 0
        var unrendered = 0
        for (_, card) in pairs {
            let dump = A11yDump.dump(renderer.render(card: card))
            missingLabels += occurrences(of: "MISSING_LABEL", in: dump)
            missingAlts += occurrences(of: "MISSING_ALT", in: dump)
            unrendered += occurrences(of: "UNRENDERED", in: dump)
        }
        print("  a11y violation totals across reference set:")
        print("    MISSING_LABEL: \(missingLabels)")
        print("    MISSING_ALT:   \(missingAlts)")
        print("    UNRENDERED:    \(unrendered)")
    }

    private static func firstDiffLine(_ a: String, _ b: String) -> String {
        let la = a.split(separator: "\n", omittingEmptySubsequences: false)
        let lb = b.split(separator: "\n", omittingEmptySubsequences: false)
        for i in 0..<max(la.count, lb.count) {
            let s1 = i < la.count ? String(la[i]) : "<missing>"
            let s2 = i < lb.count ? String(lb[i]) : "<missing>"
            if s1 != s2 {
                return "L\(i+1): fresh=\(s1.prefix(80))  baseline=\(s2.prefix(80))"
            }
        }
        return "(no line diff)"
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var remaining = haystack[...]
        while let r = remaining.range(of: needle) {
            count += 1
            remaining = remaining[r.upperBound...]
        }
        return count
    }
}
