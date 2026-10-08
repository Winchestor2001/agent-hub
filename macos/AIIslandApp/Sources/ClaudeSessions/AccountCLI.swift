import Foundation
import Darwin

/// One Claude transcript found in a config directory (global ~/.claude or an account).
public struct CCATranscript: Sendable {
    public let id: String
    public let url: URL
    public let source: String
    public let modified: Date
}

/// What `cca` is about to run. Tests inspect it instead of exec'ing Claude.
public struct CCALaunch: Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let directory: String
    /// Session id being continued, nil for a new session.
    public let session: String?
}

public enum CCAError: Error, CustomStringConvertible {
    case usage(String), message(String)
    public var description: String { switch self { case .usage(let s), .message(let s): return s } }
}

/// `cca` — terminal front end for the AI Island Claude accounts.
/// Transcripts are copied between config directories so a session keeps its id
/// on every account; ~/.claude is only ever read.
public final class AccountCLI {
    public let manager: SessionManager
    public let globalConfig: URL
    public let environment: [String: String]
    public var now: () -> Double = { Date().timeIntervalSince1970 }
    var store: SessionStore { manager.store }

    public init(manager: SessionManager, globalConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.manager = manager; self.globalConfig = globalConfig; self.environment = environment
    }

    public static let help = """
    cca — Claude accounts from the terminal

      cca ls                     Accounts, usage and sessions in this folder
      cca <N|name>               New Claude session with account N
      cca <N|name> <session-id>  Continue that session (id or prefix) with account N
      cca <N|name> -c            Continue the latest session in this folder with account N
      cca login <N|name>         Sign in to account N here
      Extra arguments after these are passed to claude, e.g. cca 2 -c --model opus
    """

    /// Claude stores a project's transcripts under projects/<cwd with every non-alphanumeric character as '-'>.
    public static func encode(_ path: String) -> String {
        String(path.unicodeScalars.map { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) ? Character($0) : "-" })
    }

    // MARK: Accounts

    public func account(_ key: String) throws -> Account {
        let accounts = try store.accounts()
        if let n = Int(key) {
            guard n >= 1, n <= accounts.count else {
                throw CCAError.message("No account \(n). Run `cca ls` to see accounts (add them in AI Island).")
            }
            return accounts[n - 1]
        }
        guard let match = accounts.first(where: { $0.name.lowercased() == key.lowercased() }) else {
            throw CCAError.message("No account named \(key). Run `cca ls` to see accounts.")
        }
        return match
    }

    var sources: [(name: String, config: URL)] {
        [("global", globalConfig)] + ((try? store.accounts()) ?? []).map { ($0.name, URL(fileURLWithPath: $0.configDir)) }
    }

    // MARK: Transcripts

    func transcripts(in folders: [String]? = nil) -> [CCATranscript] {
        var found: [CCATranscript] = []
        let fm = FileManager.default
        for source in sources {
            let projects = source.config.appendingPathComponent("projects")
            let dirs = folders ?? ((try? fm.contentsOfDirectory(atPath: projects.path)) ?? [])
            for dir in dirs {
                let folder = projects.appendingPathComponent(dir)
                for file in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where file.hasSuffix(".jsonl") {
                    let id = String(file.dropLast(6))
                    guard UUID(uuidString: id) != nil else { continue }
                    let url = folder.appendingPathComponent(file)
                    let modified = ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
                    found.append(CCATranscript(id: id.lowercased(), url: url, source: source.name, modified: modified))
                }
            }
        }
        return found
    }

    func folderKeys(_ cwd: String) -> [String] {
        let resolved = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path
        return Array(Set([Self.encode(cwd), Self.encode(resolved)]))
    }

    /// Latest copy of each session in this folder, newest first.
    public func sessions(cwd: String) -> [CCATranscript] {
        let all = transcripts(in: folderKeys(cwd))
        return Dictionary(grouping: all, by: \.id).values.compactMap { $0.max { $0.modified < $1.modified } }
            .sorted { $0.modified > $1.modified }
    }

    /// Newest copy of the session whose id starts with `prefix`.
    public func find(_ prefix: String) throws -> CCATranscript {
        let key = prefix.lowercased()
        guard key.count >= 4 else { throw CCAError.message("Give at least 4 characters of the session id.") }
        let matches = transcripts().filter { $0.id.hasPrefix(key) }
        let ids = Set(matches.map(\.id))
        guard !ids.isEmpty else { throw CCAError.message("No Claude session starts with \(prefix).") }
        guard ids.count == 1 else {
            throw CCAError.message("\(prefix) matches several sessions: \(ids.sorted().map { String($0.prefix(12)) }.joined(separator: ", ")). Use more characters.")
        }
        return matches.max { $0.modified < $1.modified }!
    }

    /// Source name of a live Claude process that has this session open, if any.
    public func openIn(_ id: String) -> String? {
        for source in sources {
            let dir = source.config.appendingPathComponent("sessions")
            for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasSuffix(".json") {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)), data.count < 100_000,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (json["sessionId"] as? String)?.lowercased() == id,
                      let pid = (json["pid"] as? NSNumber)?.int32Value, pid > 0 else { continue }
                if kill(pid, 0) == 0 || errno == EPERM { return source.name }
            }
        }
        return nil
    }

    func lines(_ url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
    }

    public func info(_ t: CCATranscript) -> (title: String, cwd: String?) {
        let entries = lines(t.url)
        let cwd = entries.lazy.compactMap { $0["cwd"] as? String }.first
        if let named = entries.last(where: { $0["customTitle"] != nil || $0["aiTitle"] != nil }) {
            return (((named["customTitle"] ?? named["aiTitle"]) as? String) ?? "", cwd)
        }
        let first = entries.lazy.compactMap { entry -> String? in
            guard entry["type"] as? String == "user", entry["isMeta"] as? Bool != true,
                  let message = entry["message"] as? [String: Any] else { return nil }
            let text = message["content"] as? String ?? (message["content"] as? [[String: Any]])?.lazy.compactMap { $0["text"] as? String }.first
            // Skip command wrappers and caveats Claude injects as user turns.
            return text.flatMap { $0.hasPrefix("<") ? nil : $0 }
        }.first
        return (first.map { $0.split(whereSeparator: \.isNewline).first.map(String.init) ?? "" } ?? "", cwd)
    }

    // MARK: Commands

    public func list(cwd: String) -> String {
        var out = ["Accounts:"]
        let accounts = (try? store.accounts()) ?? []
        if accounts.isEmpty { out.append("  none — add one in AI Island → Claude Accounts") }
        let width = max(accounts.map(\.name.count).max() ?? 0, 6)
        for (i, a) in accounts.enumerated() {
            var line = "  \(i + 1)  \(a.name.padding(toLength: width, withPad: " ", startingAt: 0))  "
            line += (a.status == "ready" ? "Ready" : a.status == "signed out" ? "Signed out" : "Not checked").padding(toLength: 12, withPad: " ", startingAt: 0)
            if a.subscription != "unknown" { line += a.subscription.capitalized + "  " }
            if let u = try? store.usage(a.id) {
                line += "\(Int(u.percent))% (\(u.window == "seven_day" ? "7d" : "5h"))"
                if let reset = u.resetAt, reset > now() { line += " · resets \(Self.time(reset))" }
                if u.stale { line += " · as of \(Self.time(u.checkedAt))" }
            }
            out.append(line)
        }
        let sessions = sessions(cwd: cwd)
        out.append("")
        out.append(sessions.isEmpty ? "No Claude sessions in this folder yet." : "Sessions in \(cwd):")
        let sourceWidth = max(sessions.prefix(10).map(\.source.count).max() ?? 0, 6)
        for s in sessions.prefix(10) {
            let title = info(s).title.isEmpty ? "(untitled)" : info(s).title
            var line = "  \(s.id.prefix(8))  \(String(title.prefix(40)).padding(toLength: 40, withPad: " ", startingAt: 0))  \(s.source.padding(toLength: sourceWidth, withPad: " ", startingAt: 0))  \(Self.time(s.modified.timeIntervalSince1970))"
            if let open = openIn(s.id) { line += "  open in \(open)" }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    static func time(_ epoch: Double) -> String {
        let date = Date(timeIntervalSince1970: epoch), f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM HH:mm"
        return f.string(from: date)
    }

    /// Resolves `cca <account> [id|-c] [claude args…]` into a launch, copying the transcript when needed.
    public func plan(_ args: [String], cwd: String, checkAuth: Bool = true) throws -> CCALaunch {
        guard let key = args.first else { throw CCAError.usage(Self.help) }
        let account = try account(key)
        var rest = Array(args.dropFirst())
        var session: CCATranscript?
        if let next = rest.first, next == "-c" || next == "--continue" || next == "last" {
            rest.removeFirst()
            guard let latest = sessions(cwd: cwd).first else { throw CCAError.message("No Claude session in this folder to continue.") }
            session = latest
        } else if let next = rest.first, !next.hasPrefix("-") {
            rest.removeFirst()
            session = try find(next)
        }
        if checkAuth, !(try manager.adapter.checkAuthentication(account, store: store)) {
            let index = (try store.accounts().firstIndex { $0.id == account.id } ?? 0) + 1
            throw CCAError.message("\(account.name) is signed out. Run: cca login \(index)")
        }
        if let u = try store.usage(account.id), !u.stale, u.percent >= 100, (u.resetAt ?? .greatestFiniteMagnitude) > now() {
            throw CCAError.message("\(account.name) reached its limit\(u.resetAt.map { " (resets \(Self.time($0)))" } ?? ""). Use the other account.")
        }
        var directory = cwd
        var claudeArgs: [String] = []
        if let session {
            if let open = openIn(session.id) {
                throw CCAError.message("Session \(session.id.prefix(8)) is still open in \(open). Exit that Claude first (/exit), then run this again.")
            }
            guard let sessionCwd = info(session).cwd, FileManager.default.fileExists(atPath: sessionCwd) else { throw SessionError.projectMissing }
            try copy(session, to: account)
            directory = sessionCwd
            claudeArgs = ["--resume", session.id]
        }
        claudeArgs += ["--settings", try statusSettings(account).path] + rest
        var env = environment
        for k in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK",
                  "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"] { env[k] = nil }
        env["CLAUDE_CONFIG_DIR"] = account.configDir
        env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = account.configDir
        return CCALaunch(executable: manager.adapter.executable, arguments: claudeArgs, environment: env, directory: directory, session: session?.id)
    }

    /// Puts the newest transcript (and its sidecar folder) into the account's config under the same id.
    public func copy(_ t: CCATranscript, to account: Account) throws {
        let fm = FileManager.default
        let folderName = t.url.deletingLastPathComponent().lastPathComponent
        guard !folderName.isEmpty, folderName != "..", !folderName.contains("/") else { throw SessionError.unsafePath }
        let targetDir = URL(fileURLWithPath: account.configDir).appendingPathComponent("projects/\(folderName)")
        let target = targetDir.appendingPathComponent("\(t.id).jsonl")
        guard target.standardizedFileURL.path != t.url.standardizedFileURL.path else { return }
        let data = try Data(contentsOf: t.url)
        guard lines(t.url).contains(where: { ["user", "assistant"].contains($0["type"] as? String ?? "") }) else { throw SessionError.corrupted }
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: target, options: .atomic); chmod(target.path, 0o600)
        try? fm.setAttributes([.modificationDate: t.modified], ofItemAtPath: target.path)
        let sidecar = t.url.deletingPathExtension(), targetSidecar = targetDir.appendingPathComponent(t.id)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: sidecar.path, isDirectory: &isDir), isDir.boolValue {
            if fm.fileExists(atPath: targetSidecar.path) { try fm.removeItem(at: targetSidecar) }
            try fm.copyItem(at: sidecar, to: targetSidecar)
        }
    }

    /// Statusline that records the account's usage for AI Island and `cca ls`.
    func statusSettings(_ account: Account) throws -> URL {
        let command = [manager.runnerExecutable, "--cca-statusline", store.root.path, account.id].map(shellQuote).joined(separator: " ")
        let path = store.root.appendingPathComponent("state/cca-\(account.id).json")
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": command]]).write(to: path, options: .atomic)
        chmod(path.path, 0o600)
        return path
    }

    /// Handles a statusline call: stores rate limits and prints a short status.
    public func statusLine(account id: String, input: Data) throws -> String {
        let account = try store.account(id)
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        try manager.recordUsage(account: id, physical: nil, json: json)
        let model = (json["model"] as? [String: Any])?["display_name"] as? String
        var parts = [model, account.name].compactMap { $0 }
        if let u = try store.usage(id), !u.stale { parts.append("\(u.window == "seven_day" ? "7d" : "5h") \(Int(u.percent))%") }
        return parts.joined(separator: " · ")
    }

    public func login(_ key: String) throws {
        let account = try account(key)
        let lock = try FileLock(store.root.appendingPathComponent("locks/login-\(account.id).lock"))
        defer { withExtendedLifetime(lock) {} }
        _ = try manager.adapter.getVersion()
        print("Sign in to \(account.name). Use the Claude subscription meant for this account.")
        _ = try manager.adapter.startProcess(arguments: ["auth", "login", "--claudeai"], account: account, project: account.configDir) { _ in }
        print(try manager.adapter.checkAuthentication(account, store: store) ? "\(account.name) is ready." : "\(account.name) is still signed out.")
    }

    /// Entry point for `AIIsland --cca …`. Only returns on errors; a launch replaces this process with Claude.
    public static func main(_ args: [String]) -> Int32 {
        do {
            let cli = AccountCLI(manager: SessionManager(store: try SessionStore()))
            let cwd = FileManager.default.currentDirectoryPath
            switch args.first {
            case nil, "ls", "list": print(cli.list(cwd: cwd)); return 0
            case "help", "-h", "--help": print(help); return 0
            case "login":
                guard args.count == 2 else { throw CCAError.usage(help) }
                try cli.login(args[1]); return 0
            default:
                let launch = try cli.plan(args, cwd: cwd)
                if let session = launch.session {
                    FileHandle.standardError.write(Data("Continuing \(session.prefix(8)) with \(try cli.account(args[0]).name) in \(launch.directory)\n".utf8))
                }
                guard chdir(launch.directory) == 0 else { throw SessionError.projectMissing }
                let argv = ([launch.executable] + launch.arguments).map { strdup($0) } + [nil]
                let envp = launch.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
                execve(launch.executable, argv, envp)
                throw SessionError.cliMissing
            }
        } catch {
            let text = (error as? CCAError)?.description ?? (error as? SessionError)?.rawValue ?? "cca failed."
            FileHandle.standardError.write(Data((text + "\n").utf8))
            return 1
        }
    }
}
