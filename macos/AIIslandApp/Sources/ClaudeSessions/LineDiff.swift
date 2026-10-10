import Foundation

/// Line-level diff between two texts, used to review configuration edits
/// before they are written. Built on `CollectionDifference` (Myers), so a
/// line inserted at the top counts as +1/−0 instead of shifting every line.
public struct LineDiff: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case context, added, removed }

    public struct Line: Sendable, Equatable {
        public let kind: Kind
        public let text: String
        /// 1-based line numbers; nil on the side the line does not exist.
        public let oldNumber: Int?
        public let newNumber: Int?
    }

    public struct Hunk: Sendable, Equatable {
        public let lines: [Line]
        public var header: String {
            let old = lines.compactMap(\.oldNumber), new = lines.compactMap(\.newNumber)
            return "@@ -\(old.first ?? 0),\(old.count) +\(new.first ?? 0),\(new.count) @@"
        }
    }

    public let lines: [Line]
    public var added: Int { lines.count { $0.kind == .added } }
    public var removed: Int { lines.count { $0.kind == .removed } }
    public var isEmpty: Bool { added == 0 && removed == 0 }

    public init(old: String, new: String) {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        var removedOffsets = Set<Int>(), insertedOffsets = Set<Int>()
        for change in newLines.difference(from: oldLines) {
            switch change {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }
        var result: [Line] = []
        var i = 0, j = 0
        while i < oldLines.count || j < newLines.count {
            if i < oldLines.count, removedOffsets.contains(i) {
                result.append(Line(kind: .removed, text: oldLines[i], oldNumber: i + 1, newNumber: nil))
                i += 1
            } else if j < newLines.count, insertedOffsets.contains(j) {
                result.append(Line(kind: .added, text: newLines[j], oldNumber: nil, newNumber: j + 1))
                j += 1
            } else if i < oldLines.count, j < newLines.count {
                result.append(Line(kind: .context, text: oldLines[i], oldNumber: i + 1, newNumber: j + 1))
                i += 1
                j += 1
            } else {
                break  // Unreachable for a consistent difference; never index out of range.
            }
        }
        lines = result
    }

    /// Changed lines grouped with `context` unchanged lines around them;
    /// nearby changes share one hunk.
    public func hunks(context: Int = 3) -> [Hunk] {
        let changed = lines.indices.filter { lines[$0].kind != .context }
        guard let first = changed.first else { return [] }
        var ranges: [ClosedRange<Int>] = []
        var start = first, end = first
        for index in changed.dropFirst() {
            if index - end > context * 2 + 1 {
                ranges.append(start...end)
                start = index
            }
            end = index
        }
        ranges.append(start...end)
        return ranges.map { range in
            let lower = max(range.lowerBound - context, 0)
            let upper = min(range.upperBound + context, lines.count - 1)
            return Hunk(lines: Array(lines[lower...upper]))
        }
    }

    /// Unified-diff text with +/− markers. Output stops after `maxLines`
    /// lines and says how many diff lines were left out.
    public func unifiedText(context: Int = 3, maxLines: Int = 400) -> String {
        var output: [String] = []
        for hunk in hunks(context: context) {
            output.append(hunk.header)
            for line in hunk.lines {
                let marker = switch line.kind { case .added: "+"; case .removed: "-"; case .context: " " }
                output.append(marker + " " + line.text)
            }
        }
        guard output.count > maxLines else { return output.joined(separator: "\n") }
        return (output.prefix(maxLines) + ["… \(output.count - maxLines) more diff lines not shown"]).joined(separator: "\n")
    }

    public var summary: String {
        (added == 1 ? tr("+%@ line", added) : tr("+%@ lines", added)) + ", "
            + (removed == 1 ? tr("−%@ line", removed) : tr("−%@ lines", removed))
    }
}
