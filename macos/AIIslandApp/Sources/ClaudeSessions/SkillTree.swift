import Foundation

/// One skill: a folder holding `SKILL.md`, plus every other file inside it
/// (references, scripts, templates) that the skill loads on demand.
public struct SkillGroup: Equatable, Sendable {
    public let folder: URL
    public let main: URL
    /// Other files in the folder, sorted by path. Nested skills keep their own files.
    public let files: [URL]

    public var name: String { folder.lastPathComponent }
    public var fileCount: Int { files.count + 1 }
}

/// A row of the configuration file list. Selecting any row opens `file`.
public struct ConfigurationRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A skill; `file` is its `SKILL.md`.
        case skill(expanded: Bool, fileCount: Int)
        /// A file inside the skill above it.
        case attached
        /// A file that belongs to no skill, or any file outside the Skills category.
        case file
    }

    public let file: URL
    public let kind: Kind
    /// The owning skill folder for skill and attached rows.
    public let skillFolder: URL?

    public init(file: URL, kind: Kind, skillFolder: URL? = nil) {
        self.file = file
        self.kind = kind
        self.skillFolder = skillFolder
    }
}

/// Groups a skills folder's files under the skill that owns them, so a list of
/// hundreds of reference files reads as a few dozen skills.
public struct SkillTree: Equatable, Sendable {
    public static let mainFileName = "SKILL.md"

    public let skills: [SkillGroup]
    /// Files that sit in no skill folder.
    public let looseFiles: [URL]

    public init(files: [URL]) {
        let mains = files.filter { $0.lastPathComponent == Self.mainFileName }
        let folders = mains.map { $0.deletingLastPathComponent().path }
        var owned: [String: [URL]] = [:]
        var loose: [URL] = []
        for file in files where file.lastPathComponent != Self.mainFileName {
            // The deepest skill folder wins, so a nested skill keeps its own files.
            if let owner = folders.filter({ file.path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) {
                owned[owner, default: []].append(file)
            } else {
                loose.append(file)
            }
        }
        let byPath: (URL, URL) -> Bool = { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        skills = mains.map { main in
            let folder = main.deletingLastPathComponent()
            return SkillGroup(folder: folder, main: main, files: (owned[folder.path] ?? []).sorted(by: byPath))
        }.sorted { byPath($0.folder, $1.folder) }
        looseFiles = loose.sorted(by: byPath)
    }

    public var fileCount: Int { skills.reduce(0) { $0 + $1.fileCount } + looseFiles.count }

    public func skill(containing file: URL) -> SkillGroup? {
        skills.filter { file.path.hasPrefix($0.folder.path + "/") }.max { $0.folder.path.count < $1.folder.path.count }
    }

    /// Rows to show. Without a query, a skill lists its files only while expanded. With
    /// one, a skill appears when its path or any of its files match, and lists the matches.
    public func rows(expanded: Set<String>, query: String, path: (URL) -> String) -> [ConfigurationRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ url: URL) -> Bool { path(url).localizedCaseInsensitiveContains(query) }
        var rows: [ConfigurationRow] = []
        for skill in skills {
            let children: [URL]
            if query.isEmpty {
                children = expanded.contains(skill.folder.path) ? skill.files : []
            } else {
                children = skill.files.filter(matches)
                guard !children.isEmpty || matches(skill.main) else { continue }
            }
            rows.append(.init(file: skill.main, kind: .skill(expanded: !children.isEmpty, fileCount: skill.fileCount), skillFolder: skill.folder))
            rows += children.map { .init(file: $0, kind: .attached, skillFolder: skill.folder) }
        }
        rows += looseFiles.filter { query.isEmpty || matches($0) }.map { .init(file: $0, kind: .file) }
        return rows
    }

    /// Validates a name typed for a new item in the Skills folder and returns the path
    /// to create, relative to that folder. A bare skill name such as `backend-style`
    /// becomes `backend-style/SKILL.md`; a path such as `backend-style/references/api.md`
    /// is kept. Returns nil for absolute paths, `.`/`..` segments, or other characters.
    public static func newItemPath(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = text.split(separator: "/", omittingEmptySubsequences: false)
        guard !text.isEmpty, segments.allSatisfy({ segment in
            segment != "." && segment != ".."
                && segment.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        }) else { return nil }
        if segments.count == 1 {
            // A bare name is a new skill; Claude accepts lowercase letters, digits and dashes.
            guard !text.contains(".") else { return text }
            guard text.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil else { return nil }
            return "\(text)/\(mainFileName)"
        }
        return text
    }

    /// Starting text for a new `SKILL.md`. The description is what Claude reads to decide
    /// when to load the skill, so the template asks for exactly that.
    public static func template(name: String) -> String {
        """
        ---
        name: \(name)
        description: What this skill does and when Claude should use it, in one or two sentences (for example, "Use for any backend change: API endpoints, services, database code").
        ---

        # \(name)

        ## When to use
        - ...

        ## Rules
        1. ...

        ## References
        Keep this file short. Put longer material next to it and link it here, for example
        [algorithms](references/algorithms.md); Claude opens a reference only when it needs it.

        """
    }
}
