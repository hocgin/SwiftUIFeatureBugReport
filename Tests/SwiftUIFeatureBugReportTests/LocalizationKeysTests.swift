//
//  LocalizationKeysTests.swift
//  SwiftUIFeatureBugReportTests
//
//  Guards the key-based catalogue: every `L10n.t("…")` call site must resolve to exactly one
//  entry in Resources/en.lproj, every catalogue entry must still be referenced by code, and
//  zh-Hans must cover the same key set. Without this, a renamed key or a deleted call site
//  would surface at runtime as a raw key on screen.
//

import Foundation
import Testing

@testable import SwiftUIFeatureBugReport

@Suite("Key-based localisation catalogue")
struct LocalizationKeysTests {

    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // …/Tests/SwiftUIFeatureBugReportTests
        .deletingLastPathComponent()  // …/Tests
        .deletingLastPathComponent()  // package root

    /// Keys defined in Resources/en.lproj — `.strings` plus the plural keys in `.stringsdict`.
    private static func catalogueKeys(language: String) throws -> Set<String> {

        let lproj = packageRoot
            .appendingPathComponent("Sources/SwiftUIFeatureBugReport/Resources/\(language).lproj")

        var keys = Set(try plistKeys(at: lproj.appendingPathComponent("Localizable.strings")))

        let dictURL = lproj.appendingPathComponent("Localizable.stringsdict")
        if FileManager.default.fileExists(atPath: dictURL.path) {
            keys.formUnion(try plistKeys(at: dictURL))
        }

        return keys
    }

    private static func plistKeys(at url: URL) throws -> Set<String> {

        guard let data = try? Data(contentsOf: url),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {

            Issue.record("Unreadable localisation file: \(url.path)")
            return []
        }

        return Set(plist.keys)
    }

    /// The dotted key prefix of every `L10n.t("…")` call site, comments excluded. Interpolated
    /// call sites contribute their base; the format-spec suffix is checked separately.
    private static func callSiteBases() throws -> Set<String> {

        let sources = packageRoot.appendingPathComponent("Sources/SwiftUIFeatureBugReport")
        let urls = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
            .map { sources.appendingPathComponent($0) }

        let pattern = try NSRegularExpression(pattern: #"L10n\.t\("([a-z][a-zA-Z0-9.]*)"#)

        var bases = Set<String>()

        for url in urls {

            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)

            for line in lines where !line.hasPrefix("//") && !line.hasPrefix(" *") {

                let ns = NSRange(line.startIndex..., in: line)

                for match in pattern.matches(in: String(line), range: ns) {

                    if let range = Range(match.range(at: 1), in: line) {
                        bases.insert(String(line[range]))
                    }
                }
            }
        }

        return bases
    }

    @Test("Every call site resolves to exactly one catalogue entry")
    func callSitesResolve() throws {

        let keys = try Self.catalogueKeys(language: "en")
        let bases = try Self.callSiteBases()

        #expect(!bases.isEmpty, "no L10n.t call sites found - the scan is broken, not the code")

        for base in bases {

            let exact = keys.contains(base)
            let formatted = keys.filter { $0.hasPrefix(base + " ") }

            #expect(exact || formatted.count == 1,
                    "\(base) must be a catalogue key, or exactly one key must extend it with format arguments")
        }
    }

    @Test("Every catalogue entry is still referenced by code")
    func noDeadKeys() throws {

        let keys = try Self.catalogueKeys(language: "en")
        let bases = try Self.callSiteBases()

        for key in keys {

            // "feedback.common.voteCount %lld" is referenced as the base "feedback.common.voteCount".
            let base = key.components(separatedBy: " %").first ?? key

            #expect(bases.contains(base), "\(key) is defined but no call site uses it")
        }
    }

    @Test("zh-Hans covers exactly the en key set")
    func languagesStayInSync() throws {

        let en = try Self.catalogueKeys(language: "en")
        let zh = try Self.catalogueKeys(language: "zh-Hans")

        #expect(en.subtracting(zh).isEmpty, "missing zh-Hans entries: \(en.subtracting(zh).sorted())")
        #expect(zh.subtracting(en).isEmpty, "zh-Hans entries with no en counterpart: \(zh.subtracting(en).sorted())")
    }

    @Test("Lookups resolve against the package bundle, not the raw key")
    func bundleResolves() {

        // A missing table or a broken Bundle.module would return the key itself.
        #expect(L10n.t("feedback.common.cancel") == "Cancel")
        #expect(L10n.t("feedback.type.feature") == "Feature")
    }
}
