import Foundation

/// A syntax problem at a 1-based line and column of a configuration file.
public struct ConfigurationSyntaxError: Error, Sendable, Equatable, CustomStringConvertible {
    public let line: Int
    public let column: Int
    public let message: String
    /// UTF-16 offset of the problem, for selecting it in a text view.
    public let offset: Int

    public var description: String { "line \(line), column \(column): \(message)" }
}

/// Syntax checks run before AI Island writes `settings.json`, `.claude.json`
/// or `config.toml`. JSON is checked strictly. TOML gets a structural check
/// (keys, tables, strings, numbers, dates, arrays, inline tables, duplicates)
/// that is not a full TOML 1.0 implementation, so callers may let the user
/// override a TOML warning.
public enum ConfigurationSyntax {
    public static func validate(_ text: String, pathExtension: String) -> ConfigurationSyntaxError? {
        switch pathExtension.lowercased() {
        case "json": return validateJSON(text)
        case "toml": return validateTOML(text)
        default: return nil
        }
    }

    public static func validateJSON(_ text: String) -> ConfigurationSyntaxError? {
        var parser = Parser(text)
        do {
            parser.skipJSONWhitespace()
            try parser.jsonValue(depth: 0)
            parser.skipJSONWhitespace()
            if !parser.atEnd { throw parser.error("Unexpected \(parser.describeCurrent()) after the JSON value") }
            return nil
        } catch let error as ConfigurationSyntaxError {
            return error
        } catch {
            return nil
        }
    }

    public static func validateTOML(_ text: String) -> ConfigurationSyntaxError? {
        var parser = Parser(text)
        do {
            try parser.tomlDocument()
            return nil
        } catch let error as ConfigurationSyntaxError {
            return error
        } catch {
            return nil
        }
    }
}

private struct Parser {
    let scalars: [Unicode.Scalar]
    var index = 0
    var tomlTable: [String] = []
    var tomlKeys = Set<String>()
    var tomlTables = Set<String>()

    init(_ text: String) { scalars = Array(text.unicodeScalars) }

    var atEnd: Bool { index >= scalars.count }
    var current: Unicode.Scalar? { atEnd ? nil : scalars[index] }

    func peek(_ offset: Int) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    func describeCurrent() -> String {
        guard let current else { return "end of file" }
        switch current {
        case "\n": return "line break"
        case "\t": return "tab"
        default: return "'\(Character(current))'"
        }
    }

    func error(_ message: String, at position: Int? = nil) -> ConfigurationSyntaxError {
        let target = min(position ?? index, scalars.count)
        var line = 1, column = 1, offset = 0
        for scalar in scalars[..<target] {
            offset += scalar.utf16.count
            if scalar == "\n" { line += 1; column = 1 } else { column += 1 }
        }
        return ConfigurationSyntaxError(line: line, column: column, message: message, offset: offset)
    }

    mutating func expect(_ literal: String, _ message: String) throws {
        for scalar in literal.unicodeScalars {
            guard current == scalar else { throw error(message) }
            index += 1
        }
    }

    func starts(with literal: String) -> Bool {
        for (offset, scalar) in literal.unicodeScalars.enumerated() where peek(offset) != scalar { return false }
        return true
    }

    // MARK: JSON

    mutating func skipJSONWhitespace() {
        while let current, [" ", "\t", "\n", "\r"].contains(current) { index += 1 }
    }

    mutating func jsonValue(depth: Int) throws {
        guard depth < 512 else { throw error("JSON is nested too deeply") }
        guard let current else { throw error("Expected a value, found end of file") }
        switch current {
        case "{":
            index += 1
            skipJSONWhitespace()
            if self.current == "}" { index += 1; return }
            while true {
                guard self.current == "\"" else {
                    throw error("Expected a quoted property name, found \(describeCurrent())")
                }
                try jsonString()
                skipJSONWhitespace()
                try expect(":", "Expected ':' after the property name, found \(describeCurrent())")
                skipJSONWhitespace()
                try jsonValue(depth: depth + 1)
                skipJSONWhitespace()
                if self.current == "," {
                    index += 1
                    skipJSONWhitespace()
                    if self.current == "}" { throw error("Trailing comma before '}' is not allowed in JSON") }
                    continue
                }
                try expect("}", "Expected ',' or '}' in the object, found \(describeCurrent())")
                return
            }
        case "[":
            index += 1
            skipJSONWhitespace()
            if self.current == "]" { index += 1; return }
            while true {
                try jsonValue(depth: depth + 1)
                skipJSONWhitespace()
                if self.current == "," {
                    index += 1
                    skipJSONWhitespace()
                    if self.current == "]" { throw error("Trailing comma before ']' is not allowed in JSON") }
                    continue
                }
                try expect("]", "Expected ',' or ']' in the array, found \(describeCurrent())")
                return
            }
        case "\"":
            try jsonString()
        case "t":
            try expect("true", "Expected a value, found \(describeCurrent())")
        case "f":
            try expect("false", "Expected a value, found \(describeCurrent())")
        case "n":
            try expect("null", "Expected a value, found \(describeCurrent())")
        case "-", "0"..."9":
            try jsonNumber()
        default:
            throw error("Expected a value, found \(describeCurrent())")
        }
    }

    mutating func jsonString() throws {
        let start = index
        index += 1
        while let current {
            switch current {
            case "\"":
                index += 1
                return
            case "\\":
                index += 1
                guard let escape = self.current else { break }
                if escape == "u" {
                    for offset in 1...4 where !(peek(offset)?.properties.isASCIIHexDigit ?? false) {
                        throw error("Invalid \\u escape; expected four hex digits")
                    }
                    index += 5
                } else if "\"\\/bfnrt".unicodeScalars.contains(escape) {
                    index += 1
                } else {
                    throw error("Invalid escape '\\\(Character(escape))' in string")
                }
            case "\n", "\r":
                throw error("Line break inside a string; use \\n instead")
            default:
                if current.value < 0x20 { throw error("Control character inside a string") }
                index += 1
            }
        }
        throw error("Unterminated string", at: start)
    }

    mutating func jsonNumber() throws {
        if current == "-" { index += 1 }
        guard let first = current, ("0"..."9").contains(first) else { throw error("Expected a digit in the number") }
        if first == "0" {
            index += 1
            if let next = current, ("0"..."9").contains(next) { throw error("Numbers cannot have leading zeros") }
        } else {
            while let digit = current, ("0"..."9").contains(digit) { index += 1 }
        }
        if current == "." {
            index += 1
            guard let digit = current, ("0"..."9").contains(digit) else { throw error("Expected a digit after the decimal point") }
            while let digit = current, ("0"..."9").contains(digit) { index += 1 }
        }
        if current == "e" || current == "E" {
            index += 1
            if current == "+" || current == "-" { index += 1 }
            guard let digit = current, ("0"..."9").contains(digit) else { throw error("Expected a digit in the exponent") }
            while let digit = current, ("0"..."9").contains(digit) { index += 1 }
        }
    }

    // MARK: TOML

    mutating func skipTOMLSpaces() {
        while current == " " || current == "\t" { index += 1 }
    }

    mutating func skipTOMLComment() throws {
        guard current == "#" else { return }
        while let current, current != "\n" {
            if current != "\t", current.value < 0x20 || current.value == 0x7F, current != "\r" {
                throw error("Control character inside a comment")
            }
            index += 1
        }
    }

    /// Whitespace, comments and line breaks between array items.
    mutating func skipTOMLBlank() throws {
        while true {
            skipTOMLSpaces()
            try skipTOMLComment()
            if current == "\n" || current == "\r" { index += 1 } else { return }
        }
    }

    mutating func expectTOMLLineEnd() throws {
        skipTOMLSpaces()
        try skipTOMLComment()
        if current == "\r" { index += 1 }
        guard atEnd || current == "\n" else {
            throw error("Expected the end of the line, found \(describeCurrent())")
        }
    }

    mutating func tomlDocument() throws {
        while true {
            try skipTOMLBlank()
            guard let current else { return }
            if current == "[" {
                try tomlTableHeader()
            } else {
                let start = index
                let key = try tomlKey()
                skipTOMLSpaces()
                try expect("=", "Expected '=' after the key, found \(describeCurrent())")
                skipTOMLSpaces()
                try tomlValue()
                let path = (tomlTable + key).joined(separator: "\u{1F}")
                guard tomlKeys.insert(path).inserted else {
                    throw error("Duplicate key '\(key.joined(separator: "."))'", at: start)
                }
            }
            try expectTOMLLineEnd()
        }
    }

    mutating func tomlTableHeader() throws {
        let start = index
        let isArray = starts(with: "[[")
        index += isArray ? 2 : 1
        skipTOMLSpaces()
        let key = try tomlKey()
        skipTOMLSpaces()
        try expect(isArray ? "]]" : "]", "Expected '\(isArray ? "]]" : "]")' to close the table header, found \(describeCurrent())")
        let path = key.joined(separator: "\u{1F}")
        if isArray {
            // Each [[array]] element starts a fresh table.
            tomlKeys = tomlKeys.filter { !$0.hasPrefix(path + "\u{1F}") }
            tomlTables = tomlTables.filter { !$0.hasPrefix(path + "\u{1F}") }
        } else {
            guard tomlTables.insert(path).inserted, !tomlKeys.contains(path) else {
                throw error("Table [\(key.joined(separator: "."))] is defined more than once", at: start)
            }
        }
        tomlTable = key
    }

    mutating func tomlKey() throws -> [String] {
        var parts: [String] = []
        while true {
            guard let current else { throw error("Expected a key, found end of file") }
            if current == "\"" {
                parts.append(try tomlBasicString())
            } else if current == "'" {
                parts.append(try tomlLiteralString())
            } else {
                var bare = ""
                while let scalar = self.current,
                      ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
                        || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-" {
                    bare.unicodeScalars.append(scalar)
                    index += 1
                }
                guard !bare.isEmpty else { throw error("Expected a key, found \(describeCurrent())") }
                parts.append(bare)
            }
            skipTOMLSpaces()
            guard self.current == "." else { return parts }
            index += 1
            skipTOMLSpaces()
        }
    }

    mutating func tomlValue() throws {
        guard let current else { throw error("Expected a value, found end of file") }
        switch current {
        case "\"":
            if starts(with: "\"\"\"") { try tomlMultilineString(quote: "\"") } else { _ = try tomlBasicString() }
        case "'":
            if starts(with: "'''") { try tomlMultilineString(quote: "'") } else { _ = try tomlLiteralString() }
        case "[":
            index += 1
            try skipTOMLBlank()
            while self.current != "]" {
                try tomlValue()
                try skipTOMLBlank()
                if self.current == "," {
                    index += 1
                    try skipTOMLBlank()
                } else if self.current != "]" {
                    throw error("Expected ',' or ']' in the array, found \(describeCurrent())")
                }
            }
            index += 1
        case "{":
            index += 1
            skipTOMLSpaces()
            if self.current == "}" { index += 1; return }
            var keys = Set<String>()
            while true {
                let start = index
                let key = try tomlKey()
                skipTOMLSpaces()
                try expect("=", "Expected '=' after the key, found \(describeCurrent())")
                skipTOMLSpaces()
                try tomlValue()
                guard keys.insert(key.joined(separator: "\u{1F}")).inserted else {
                    throw error("Duplicate key '\(key.joined(separator: "."))'", at: start)
                }
                skipTOMLSpaces()
                if self.current == "," {
                    index += 1
                    skipTOMLSpaces()
                    continue
                }
                try expect("}", "Expected ',' or '}' in the inline table, found \(describeCurrent())")
                return
            }
        default:
            try tomlScalar()
        }
    }

    mutating func tomlScalar() throws {
        let start = index
        var token = ""
        func isTokenScalar(_ scalar: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
                || "_+-.:".unicodeScalars.contains(scalar)
        }
        while let scalar = current, isTokenScalar(scalar) {
            token.unicodeScalars.append(scalar)
            index += 1
        }
        // A space may separate the date and time of an offset/local date-time.
        if token.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
           current == " ", let next = peek(1), ("0"..."9").contains(next) {
            token.unicodeScalars.append(" ")
            index += 1
            while let scalar = current, isTokenScalar(scalar) {
                token.unicodeScalars.append(scalar)
                index += 1
            }
        }
        guard !token.isEmpty else {
            throw error("Expected a value, found \(describeCurrent())")
        }
        let patterns = [
            #"^(true|false)$"#,
            #"^[+-]?(0|[1-9](_?\d)*)$"#,
            #"^0x[0-9A-Fa-f](_?[0-9A-Fa-f])*$"#,
            #"^0o[0-7](_?[0-7])*$"#,
            #"^0b[01](_?[01])*$"#,
            #"^[+-]?(0|[1-9](_?\d)*)(\.\d(_?\d)*([eE][+-]?\d(_?\d)*)?|[eE][+-]?\d(_?\d)*)$"#,
            #"^[+-]?(inf|nan)$"#,
            #"^\d{4}-\d{2}-\d{2}([Tt ]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})?)?$"#,
            #"^\d{2}:\d{2}:\d{2}(\.\d+)?$"#,
        ]
        guard patterns.contains(where: { token.range(of: $0, options: .regularExpression) != nil }) else {
            let hint = token.first?.isLetter == true ? " (strings must be quoted)" : ""
            throw error("Invalid value '\(token)'\(hint)", at: start)
        }
    }

    mutating func tomlBasicString() throws -> String {
        let start = index
        index += 1
        var value = ""
        while let current {
            switch current {
            case "\"":
                index += 1
                return value
            case "\\":
                try tomlEscape()
            case "\n", "\r":
                throw error("Line break inside a string; use \"\"\" for multi-line strings")
            default:
                if current != "\t", current.value < 0x20 || current.value == 0x7F { throw error("Control character inside a string") }
                value.unicodeScalars.append(current)
                index += 1
            }
        }
        throw error("Unterminated string", at: start)
    }

    mutating func tomlEscape() throws {
        index += 1
        guard let escape = current else { throw error("Unterminated escape sequence") }
        let hexCount = escape == "u" ? 4 : escape == "U" ? 8 : 0
        if hexCount > 0 {
            for offset in 1...hexCount where !(peek(offset)?.properties.isASCIIHexDigit ?? false) {
                throw error("Invalid \\\(Character(escape)) escape; expected \(hexCount) hex digits")
            }
            index += hexCount + 1
        } else if "btnfr\"\\e".unicodeScalars.contains(escape) {
            index += 1
        } else {
            throw error("Invalid escape '\\\(Character(escape))' in string")
        }
    }

    mutating func tomlLiteralString() throws -> String {
        let start = index
        index += 1
        var value = ""
        while let current {
            if current == "'" { index += 1; return value }
            if current == "\n" || current == "\r" { throw error("Line break inside a literal string; use ''' for multi-line strings") }
            value.unicodeScalars.append(current)
            index += 1
        }
        throw error("Unterminated string", at: start)
    }

    mutating func tomlMultilineString(quote: Unicode.Scalar) throws {
        let start = index
        let delimiter = String(repeating: Character(quote), count: 3)
        index += 3
        while !atEnd {
            if starts(with: delimiter) {
                index += 3
                // Up to two extra quotes may close the string ("""a""""" is valid).
                var extra = 0
                while current == quote, extra < 2 { index += 1; extra += 1 }
                return
            }
            if quote == "\"", current == "\\" {
                // A backslash at the end of a line trims the line break.
                var probe = index + 1
                while probe < scalars.count, scalars[probe] == " " || scalars[probe] == "\t" { probe += 1 }
                if probe < scalars.count, scalars[probe] == "\n" || scalars[probe] == "\r" {
                    index = probe + 1
                    continue
                }
                try tomlEscape()
                continue
            }
            index += 1
        }
        throw error("Unterminated multi-line string", at: start)
    }
}
