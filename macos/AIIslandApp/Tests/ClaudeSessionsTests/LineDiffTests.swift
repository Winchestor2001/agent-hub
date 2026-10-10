import XCTest
@testable import ClaudeSessions

final class LineDiffTests: XCTestCase {
    private let base = (1...10).map { "line \($0)" }.joined(separator: "\n")

    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    func testInsertAtStartCountsOneAddedLine() {
        let diff = LineDiff(old: base, new: "header\n" + base)
        XCTAssertEqual(diff.added, 1)
        XCTAssertEqual(diff.removed, 0)
        XCTAssertEqual(diff.lines.first, LineDiff.Line(kind: .added, text: "header", oldNumber: nil, newNumber: 1))
    }

    func testInsertInMiddle() {
        var middle = lines(base)
        middle.insert("inserted", at: 5)
        let diff = LineDiff(old: base, new: middle.joined(separator: "\n"))
        XCTAssertEqual([diff.added, diff.removed], [1, 0])
        XCTAssertEqual(diff.lines.first { $0.kind == .added }?.newNumber, 6)
    }

    func testInsertAtEnd() {
        let diff = LineDiff(old: base, new: base + "\nfooter")
        XCTAssertEqual([diff.added, diff.removed], [1, 0])
        XCTAssertEqual(diff.lines.last?.text, "footer")
    }

    func testDeleteLine() {
        var removed = lines(base)
        removed.remove(at: 0)
        let diff = LineDiff(old: base, new: removed.joined(separator: "\n"))
        XCTAssertEqual([diff.added, diff.removed], [0, 1])
        XCTAssertEqual(diff.lines.first, LineDiff.Line(kind: .removed, text: "line 1", oldNumber: 1, newNumber: nil))
    }

    func testReplaceLineIsOneRemovalAndOneAddition() {
        let diff = LineDiff(old: base, new: base.replacingOccurrences(of: "line 4", with: "line four"))
        XCTAssertEqual([diff.added, diff.removed], [1, 1])
        let changed = diff.lines.filter { $0.kind != .context }
        XCTAssertEqual(changed.map(\.kind), [.removed, .added])
        XCTAssertEqual(changed.map(\.text), ["line 4", "line four"])
    }

    func testIdenticalTextHasNoHunks() {
        let diff = LineDiff(old: base, new: base)
        XCTAssertTrue(diff.isEmpty)
        XCTAssertEqual(diff.unifiedText(), "")
    }

    func testUnifiedTextShowsMarkersAndContext() {
        let diff = LineDiff(old: base, new: base.replacingOccurrences(of: "line 4", with: "line four"))
        XCTAssertEqual(diff.unifiedText(context: 1), """
        @@ -3,3 +3,3 @@
          line 3
        - line 4
        + line four
          line 5
        """)
    }

    func testDistantChangesFormSeparateHunks() {
        let long = (1...40).map { "line \($0)" }
        var edited = long
        edited[1] = "changed 2"
        edited[35] = "changed 36"
        let diff = LineDiff(old: long.joined(separator: "\n"), new: edited.joined(separator: "\n"))
        let hunks = diff.hunks(context: 3)
        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks.map(\.header), ["@@ -1,5 +1,5 @@", "@@ -33,7 +33,7 @@"])
    }

    func testLongDiffIsTruncatedWithNote() {
        let diff = LineDiff(old: "", new: (1...50).map { "new \($0)" }.joined(separator: "\n"))
        let text = diff.unifiedText(maxLines: 10)
        XCTAssertEqual(text.components(separatedBy: "\n").count, 11)
        XCTAssertTrue(text.hasSuffix("more diff lines not shown"))
    }
}
