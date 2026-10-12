import XCTest
@testable import ClaudeSessions

final class SkillTreeTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/home/.claude/skills")

    private func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    private func relative(_ file: URL) -> String { String(file.path.dropFirst(root.path.count + 1)) }

    private lazy var tree = SkillTree(files: [
        "video/SKILL.md", "video/references/gsap.md", "video/scripts/render.sh",
        "backend/SKILL.md", "backend/references/algorithms.md",
        "video/nested/SKILL.md", "video/nested/notes.md",
        "synced/org/pdf/SKILL.md", "synced/org/pdf/forms.md",
        "README.md", "synced/.bucket",
    ].map(url))

    private func rows(expanded: [String] = [], query: String = "") -> [String] {
        tree.rows(expanded: Set(expanded.map { url($0).path }), query: query, path: relative).map { row in
            switch row.kind {
            case .skill(let expanded, let count): "\(expanded ? "v" : ">") \(relative(row.file)) (\(count))"
            case .attached: "  \(relative(row.file))"
            case .file: relative(row.file)
            }
        }
    }

    func testFilesAreGroupedUnderTheDeepestSkillFolder() {
        XCTAssertEqual(tree.skills.map(\.name), ["backend", "pdf", "video", "nested"])
        XCTAssertEqual(tree.skills.first { $0.name == "video" }?.files.map(relative), ["video/references/gsap.md", "video/scripts/render.sh"])
        XCTAssertEqual(tree.skills.first { $0.name == "nested" }?.files.map(relative), ["video/nested/notes.md"])
        XCTAssertEqual(tree.looseFiles.map(relative), ["README.md", "synced/.bucket"])
        XCTAssertEqual(tree.fileCount, 11)
        XCTAssertEqual(tree.skill(containing: url("video/nested/notes.md"))?.name, "nested")
        XCTAssertNil(tree.skill(containing: url("README.md")))
    }

    func testCollapsedListShowsOneRowPerSkill() {
        XCTAssertEqual(rows(), [
            "> backend/SKILL.md (2)", "> synced/org/pdf/SKILL.md (2)", "> video/SKILL.md (3)", "> video/nested/SKILL.md (2)",
            "README.md", "synced/.bucket",
        ])
    }

    func testExpandedSkillListsItsFilesBelowIt() {
        XCTAssertEqual(rows(expanded: ["video"]).prefix(5), [
            "> backend/SKILL.md (2)", "> synced/org/pdf/SKILL.md (2)",
            "v video/SKILL.md (3)", "  video/references/gsap.md", "  video/scripts/render.sh",
        ])
        // A skill with no other files has nothing to expand.
        let lone = SkillTree(files: [url("solo/SKILL.md")])
        XCTAssertEqual(lone.rows(expanded: [url("solo").path], query: "", path: relative).map(\.kind), [.skill(expanded: false, fileCount: 1)])
    }

    func testSearchOpensSkillsWithMatchingFilesOnly() {
        XCTAssertEqual(rows(query: "GSAP"), ["v video/SKILL.md (3)", "  video/references/gsap.md"])
        XCTAssertEqual(rows(query: "backend"), ["v backend/SKILL.md (2)", "  backend/references/algorithms.md"])
        XCTAssertEqual(rows(query: "pdf/SKILL"), ["> synced/org/pdf/SKILL.md (2)"])
        XCTAssertEqual(rows(query: "readme"), ["README.md"])
        XCTAssertEqual(rows(expanded: ["video"], query: "nothing-matches"), [])
    }

    func testNewItemPathCreatesASkillFolderForABareName() {
        XCTAssertEqual(SkillTree.newItemPath("backend-style"), "backend-style/SKILL.md")
        XCTAssertEqual(SkillTree.newItemPath("  backend-style \n"), "backend-style/SKILL.md")
        XCTAssertEqual(SkillTree.newItemPath("backend-style/references/algorithms.md"), "backend-style/references/algorithms.md")
        XCTAssertEqual(SkillTree.newItemPath("notes.md"), "notes.md")
        for invalid in ["", "Backend", "-x/../y", "../escape.md", "a/./b.md", "/etc/passwd", "a//b.md", "a/b c.md", "skill/", String(repeating: "a", count: 65)] {
            XCTAssertNil(SkillTree.newItemPath(invalid), invalid)
        }
    }

    func testTemplateStartsWithFrontmatterNamingTheSkill() {
        let text = SkillTree.template(name: "backend-style")
        XCTAssertTrue(text.hasPrefix("---\nname: backend-style\ndescription: "))
        XCTAssertTrue(text.contains("\n---\n\n# backend-style\n"))
    }
}
