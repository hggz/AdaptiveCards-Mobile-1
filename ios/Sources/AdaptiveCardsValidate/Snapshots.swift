//
//  Snapshots.swift
//  AdaptiveCardsValidate — windows-port
//
//  RenderingNode snapshot baselines. For every reference sample card we
//  encode the renderer's output as canonical JSON and diff against a
//  committed baseline file under `Snapshots/`. This is the cheap,
//  pixel-free regression net — when the renderer changes shape, this
//  fires loudly across every platform.
//
//  Run with --update-snapshots to (re)generate baselines on disk.
//

import Foundation
import ACCore
import AdaptiveCardsCrossUI

enum Snapshots {

    /// Directory that holds the committed `*.json` baselines. Resolved
    /// relative to this source file so both `swift run` and direct .exe
    /// launches find them.
    static let snapshotsDirectory: URL = {
        // <repo>/ios/Sources/AdaptiveCardsValidate/Snapshots.swift
        let here = URL(fileURLWithPath: #filePath)
        return here.deletingLastPathComponent()
            .appendingPathComponent("Snapshots", isDirectory: true)
    }()

    static func baselinePath(for filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        return snapshotsDirectory
            .appendingPathComponent(base + ".rendertree.json", isDirectory: false)
    }

    /// Render every reference sample, compute its snapshot JSON, and
    /// either compare against the on-disk baseline or rewrite it.
    static func runSnapshotChecks(_ r: Runner, updateBaselines: Bool) {
        r.section("RenderingNode snapshot baselines"
                  + (updateBaselines ? " (UPDATE MODE)" : ""))

        let pairs: [(String, AdaptiveCard)]
        do { pairs = try SampleCardLibrary.loadReferenceSet() }
        catch {
            r.check(false, "load reference set: \(error)")
            return
        }

        try? FileManager.default.createDirectory(
            at: snapshotsDirectory,
            withIntermediateDirectories: true
        )

        let renderer = Renderer()
        for (name, card) in pairs {
            let tree = renderer.render(card: card)
            let json: String
            do { json = try tree.snapshotJSON() }
            catch {
                r.check(false, "encode snapshot for \(name): \(error)")
                continue
            }

            let path = baselinePath(for: name)
            if updateBaselines {
                do {
                    try (json + "\n").write(to: path, atomically: true, encoding: .utf8)
                    print("  wrote \(path.lastPathComponent)")
                    r.check(true, "\(name) baseline written")
                } catch {
                    r.check(false, "write \(name) baseline: \(error)")
                }
                continue
            }

            // Diff mode (the default — CI uses this).
            guard FileManager.default.fileExists(atPath: path.path) else {
                r.check(
                    false,
                    "\(name) baseline missing at \(path.path) — run with --update-snapshots to bootstrap"
                )
                continue
            }
            let onDisk: String
            do { onDisk = try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .newlines) }
            catch {
                r.check(false, "read \(name) baseline: \(error)")
                continue
            }
            let current = json.trimmingCharacters(in: .newlines)
            if current == onDisk {
                r.check(true, "\(name) snapshot matches baseline")
            } else {
                r.check(
                    false,
                    "\(name) snapshot DRIFTED — first diff line: \(firstDiffLine(current, onDisk))"
                )
            }
        }
    }

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
