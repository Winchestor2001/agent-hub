import XCTest
@testable import ClaudeSessions

final class LocalizationTests: XCTestCase {
    private static let sources: [(name: String, text: String)] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return files.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (url.lastPathComponent, $0) }
        }
    }()

    /// Unescaped contents of every `"…"` literal that follows `prefix` in the sources.
    private func literals(after prefix: String, in text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let range = rest.range(of: prefix + "\"") {
            var value = ""
            var index = range.upperBound
            while index < rest.endIndex, rest[index] != "\"" {
                if rest[index] == "\\", rest.index(after: index) < rest.endIndex {
                    index = rest.index(after: index)
                    switch rest[index] {
                    case "n": value.append("\n")
                    case "t": value.append("\t")
                    case "(": value.append("\\(")
                    default: value.append(rest[index])
                    }
                } else {
                    value.append(rest[index])
                }
                index = rest.index(after: index)
            }
            found.append(value)
            rest = index < rest.endIndex ? rest[rest.index(after: index)...] : rest[rest.endIndex...]
        }
        return found
    }

    private func placeholders(_ text: String) -> Int {
        text.components(separatedBy: "%@").count - 1
            + (try! NSRegularExpression(pattern: "%[0-9]+\\$@"))
                .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func testFormatSubstitutesArgumentsInOrderAndByPosition() {
        XCTAssertEqual(Localization.format("%@ of %@", ["1", "3"]), "1 of 3")
        XCTAssertEqual(Localization.format("%2$@ dan %1$@", ["1", "3"]), "3 dan 1")
        XCTAssertEqual(Localization.format("%@% used", ["42"]), "42% used")
        XCTAssertEqual(Localization.format("100%", []), "100%")
        XCTAssertEqual(Localization.format("%@ and %@", ["a"]), "a and ")
    }

    func testMissingTranslationFallsBackToEnglish() {
        XCTAssertEqual(tr("No such interface text %@", 7), "No such interface text 7")
        XCTAssertEqual(tr("Settings"), "Settings")  // The interface is English.
        XCTAssertEqual(Localization.uzbek["Settings"], "Sozlamalar")
    }

    func testEveryInterfaceStringHasATranslation() {
        var keys: [String] = []
        for (name, text) in Self.sources where name != "Localization.swift" {
            for key in literals(after: "tr(", in: text) {
                XCTAssertFalse(key.contains("\\("), "\(name): interpolation inside tr(\"\(key)\")")
                keys.append(key)
            }
        }
        XCTAssertGreaterThan(keys.count, 250)
        for key in keys {
            XCTAssertNotNil(Localization.uzbek[key], "Missing Uzbek text for \"\(key)\"")
        }
    }

    func testTranslatedValuesFromDataHaveTranslations() {
        for error in SessionError.allCases {
            XCTAssertNotNil(Localization.uzbek[error.rawValue], "Missing Uzbek text for \(error)")
            XCTAssertEqual(error.message, tr(error.rawValue))
        }
        // Readiness names and statuses, and history event kinds, are stored in English.
        var stored: [String] = ["Project skills", "Agents", "Project config", "Project MCP declarations"]
        for (_, text) in Self.sources {
            for line in text.components(separatedBy: "\n") where line.contains("Readiness(name") {
                stored += literals(after: "", in: line).filter { !$0.contains("\\(") && !["✓ Connected", "disableAllHooks"].contains($0) }
            }
            stored += literals(after: "event(", in: text) + literals(after: "? ", in: text).filter { $0.hasPrefix("session ") }
        }
        XCTAssertGreaterThan(stored.count, 30)
        for value in stored {
            XCTAssertNotNil(Localization.uzbek[value], "Missing Uzbek text for \"\(value)\"")
        }
    }

    func testEveryTranslationIsUsedAndKeepsItsPlaceholders() {
        let code = Self.sources.filter { $0.name != "Localization.swift" }.map(\.text).joined(separator: "\n")
        for (key, value) in Localization.uzbek {
            let literal = key.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
            XCTAssertTrue(code.contains("\"\(literal)\""), "Unused translation key \"\(key)\"")
            XCTAssertEqual(placeholders(key), placeholders(value), "Placeholder count differs for \"\(key)\"")
        }
    }

    func testUzbekTextUsesProperApostrophes() throws {
        let wrongTurnedComma = try NSRegularExpression(pattern: "[oOgG]['’‘`]")
        let wrongModifier = try NSRegularExpression(pattern: "\\p{L}['’`]\\p{L}")
        for value in Localization.uzbek.values {
            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNil(wrongTurnedComma.firstMatch(in: value, range: range), "Use ʻ after o/g in \"\(value)\"")
            XCTAssertNil(wrongModifier.firstMatch(in: value, range: range), "Use ʼ as apostrophe in \"\(value)\"")
        }
    }
}
