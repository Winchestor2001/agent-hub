import XCTest
@testable import ClaudeSessions

final class ConfigurationSyntaxTests: XCTestCase {
    private func assertError(_ error: ConfigurationSyntaxError?, line: Int, column: Int, contains text: String,
                             file: StaticString = #filePath, lineNumber: UInt = #line) {
        guard let error else { return XCTFail("Expected a syntax error", file: file, line: lineNumber) }
        XCTAssertEqual([error.line, error.column], [line, column], error.description, file: file, line: lineNumber)
        XCTAssertTrue(error.message.contains(text), error.message, file: file, line: lineNumber)
    }

    // MARK: JSON

    func testValidJSON() {
        let settings = """
        {
          "model": "opus",
          "permissions": { "allow": ["Bash(git status)", "Read"], "deny": [] },
          "cleanupPeriodDays": 30,
          "ratio": -1.5e3,
          "enabled": true,
          "statusLine": null,
          "escaped": "a\\"b\\\\c\\u00e9"
        }

        """
        XCTAssertNil(ConfigurationSyntax.validate(settings, pathExtension: "json"))
        XCTAssertNil(ConfigurationSyntax.validateJSON("[]"))
    }

    func testJSONTrailingComma() {
        assertError(ConfigurationSyntax.validateJSON("{\n  \"a\": 1,\n}"), line: 3, column: 1, contains: "Trailing comma")
    }

    func testJSONMissingComma() {
        assertError(ConfigurationSyntax.validateJSON("{\n  \"a\": 1\n  \"b\": 2\n}"), line: 3, column: 3, contains: "Expected ',' or '}'")
    }

    func testJSONUnquotedKeyAndComment() {
        assertError(ConfigurationSyntax.validateJSON("{ model: 1 }"), line: 1, column: 3, contains: "quoted property name")
        assertError(ConfigurationSyntax.validateJSON("{\n// note\n}"), line: 2, column: 1, contains: "quoted property name")
    }

    func testJSONUnterminatedStringAndTrailingText() {
        assertError(ConfigurationSyntax.validateJSON("{\"a\": \"b}"), line: 1, column: 7, contains: "Unterminated string")
        assertError(ConfigurationSyntax.validateJSON("{}\nRegression draft"), line: 2, column: 1, contains: "after the JSON value")
        assertError(ConfigurationSyntax.validateJSON(""), line: 1, column: 1, contains: "end of file")
        assertError(ConfigurationSyntax.validateJSON("{\"a\": 01}"), line: 1, column: 8, contains: "leading zeros")
    }

    // MARK: TOML

    func testValidTOML() {
        let config = #"""
        # Codex configuration
        model = "gpt-5.5"
        model_reasoning_effort = 'high'
        approval_policy = "on-request"
        max_tokens = 1_000
        temperature = 0.2
        hex = 0xDEAD_beef
        enabled = true
        created = 1979-05-27 07:32:00Z
        "quoted key" = """
        multi
        line \
          trimmed"""
        paths = [
          "~/a", # trailing comment
          '~/b',
        ]
        inline = { name = "x", nested = { on = false } }

        [mcp_servers.docs]
        command = "npx"
        args = ["-y", "docs-mcp"]
        env = { TOKEN = "x" }

        [projects."/Users/me/repo"]
        trust_level = "trusted"

        [[profiles]]
        name = "a"
        [[profiles]]
        name = "b"
        """#
        XCTAssertNil(ConfigurationSyntax.validate(config, pathExtension: "toml"))
    }

    func testTOMLUnquotedString() {
        assertError(ConfigurationSyntax.validateTOML("model = gpt-5\n"), line: 1, column: 9, contains: "strings must be quoted")
    }

    func testTOMLMissingEqualsAndUnclosedHeader() {
        assertError(ConfigurationSyntax.validateTOML("a = 1\nmodel \"x\""), line: 2, column: 7, contains: "Expected '='")
        assertError(ConfigurationSyntax.validateTOML("[mcp_servers.docs\ncommand = \"npx\""), line: 1, column: 18, contains: "to close the table header")
    }

    func testTOMLUnterminatedStringsAndArrays() {
        assertError(ConfigurationSyntax.validateTOML("a = \"open\nb = 1"), line: 1, column: 10, contains: "Line break inside a string")
        assertError(ConfigurationSyntax.validateTOML("a = \"\"\"never closed"), line: 1, column: 5, contains: "Unterminated multi-line string")
        assertError(ConfigurationSyntax.validateTOML("a = [1, 2\nb = 3"), line: 2, column: 1, contains: "Expected ',' or ']'")
    }

    func testTOMLDuplicates() {
        assertError(ConfigurationSyntax.validateTOML("a = 1\na = 2"), line: 2, column: 1, contains: "Duplicate key 'a'")
        assertError(ConfigurationSyntax.validateTOML("[x]\na = 1\n[x]\nb = 2"), line: 3, column: 1, contains: "defined more than once")
        XCTAssertNil(ConfigurationSyntax.validateTOML("[x]\na = 1\n[y]\na = 2"))
    }

    func testTOMLTextAfterValue() {
        assertError(ConfigurationSyntax.validateTOML("a = 1 2"), line: 1, column: 7, contains: "Expected the end of the line")
    }

    func testOtherExtensionsAreNotChecked() {
        XCTAssertNil(ConfigurationSyntax.validate("{ not json", pathExtension: "md"))
    }

    func testErrorOffsetIsUTF16() {
        let error = ConfigurationSyntax.validateJSON("{\"é😀\": }")
        XCTAssertEqual(error?.offset, ("{\"é😀\": " as NSString).length)
    }
}
