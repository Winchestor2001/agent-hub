import Foundation
import CryptoKit
import Darwin

public struct CommandResult { public let status: Int32; public let output: Data }
public struct GitState: Equatable, Sendable {
    public let branch: String
    public let head: String
    public let status: String
}
public struct Readiness: Sendable {
    public let name: String
    public let status: String
    public var ready: Bool { status == "OK" }
}
public protocol ClaudeCodeAdapter {
    func getVersion() throws -> String
    func checkAuthentication(_ account: Account, store: SessionStore) throws -> Bool
    func readiness(_ account: Account, project: String, store: SessionStore) throws -> [Readiness]
    func gitState(_ project: String) throws -> GitState
    func getCurrentSession(_ physical: String, store: SessionStore) throws -> String
    func listSessions(_ project: String, store: SessionStore) throws -> [ManagedSession]
    func getUsage(_ account: String, store: SessionStore) throws -> UsageSnapshot?
    func forkSession(snapshot: URL, sessionID: String) -> [String]
    func resumeSession(sessionID: String) -> [String]
    func startProcess(arguments: [String], account: Account, project: String, launched: (Int32) throws -> Void) throws -> Int32
    func stopProcess(_ physical: String, store: SessionStore) throws
}
public final class LocalClaudeCodeAdapter: ClaudeCodeAdapter {
    public let executable: String
    public init(executable: String? = nil) {
        let paths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path]
        self.executable = executable ?? paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? paths[0]
    }
    public func environment(_ account: Account) -> [String: String] {
        // Do not inherit API keys, OAuth overrides, alternate providers, storage
        // overrides, plugins or injected Claude settings from the launching shell.
        let inherited = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "TERM", "LANG", "LC_ALL", "SHELL"] { env[key] = inherited[key] }
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["CLAUDE_CONFIG_DIR"] = account.configDir
        env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = account.configDir
        return env
    }
    public func command(_ executable: String, _ args: [String], account: Account? = nil, cwd: String? = nil, timeout: Double = 20) throws -> CommandResult {
        // Files avoid pipe-buffer deadlocks. Stderr is discarded, never persisted.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close(); try? FileManager.default.removeItem(at: url) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
        p.standardOutput = file; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        if let account { p.environment = environment(account) }
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        try p.run()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); Thread.sleep(forTimeInterval: 0.3); if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        p.waitUntilExit()
        return CommandResult(status: p.terminationStatus, output: try Data(contentsOf: url))
    }
    public func getVersion() throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw SessionError.cliMissing }
        let result = try command(executable, ["--version"])
        let version = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = version.split(separator: " ").first?.split(separator: ".").compactMap { Int($0) } ?? []
        let help = String(decoding: try command(executable, ["--help"]).output, as: UTF8.self)
        guard digits.count == 3, digits.lexicographicallyPrecedes([2, 1, 251]) == false,
              ["--resume", "--fork-session", "--session-id", "--settings"].allSatisfy(help.contains) else { throw SessionError.unsupported }
        return String(version.prefix(80))
    }
    public func checkAuthentication(_ account: Account, store: SessionStore) throws -> Bool {
        let r = try command(executable, ["auth", "status", "--json"], account: account, cwd: account.configDir)
        let json = (try? JSONSerialization.jsonObject(with: r.output)) as? [String: Any] ?? [:]
        let method = json["authMethod"] as? String ?? "none"
        let subscription = json["subscriptionType"] as? String ?? "unknown"
        let loggedIn = r.status == 0 && json["loggedIn"] as? Bool == true && method == "claude.ai"
        let identitySource = json["email"] as? String ?? json["accountId"] as? String ?? ""
        let identity = identitySource.isEmpty ? "" : SHA256.hash(data: Data(identitySource.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        try store.execute("UPDATE accounts SET status=?,subscription=?,checked_at=?,identity=? WHERE id=?",
                          [loggedIn ? "ready" : "signed out", subscription, store.now, identity, account.id])
        return loggedIn
    }
    public func readiness(_ account: Account, project: String, store: SessionStore) throws -> [Readiness] {
        _ = try getVersion()
        let auth = try checkAuthentication(account, store: store)
        var checks = [Readiness(name: "Claude subscription auth", status: auth ? "OK" : "Sign in required")]
        _ = try gitState(project)
        for (name, path) in [("Project skills", ".claude/skills"), ("Agents", ".claude/agents"), ("Project config", ".claude/settings.json"), ("Project MCP declarations", ".mcp.json")] {
            let url = URL(fileURLWithPath: project).appendingPathComponent(path)
            let exists = FileManager.default.fileExists(atPath: url.path)
            var ok = !exists || FileManager.default.isReadableFile(atPath: url.path)
            if exists && path.hasSuffix(".json") { ok = ok && ((try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) != nil) }
            checks.append(Readiness(name: name, status: ok ? "OK" : "Unreadable or invalid"))
        }
        let protected = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CONFIG_DIR", "CLAUDE_SECURESTORAGE_CONFIG_DIR", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"]
        var scope = URL(fileURLWithPath: project)
        var settingFiles = [URL(fileURLWithPath: account.configDir).appendingPathComponent("settings.json")]
        while scope.path != "/" {
            settingFiles += [scope.appendingPathComponent(".claude/settings.json"), scope.appendingPathComponent(".claude/settings.local.json")]
            scope.deleteLastPathComponent()
        }
        for file in settingFiles where FileManager.default.fileExists(atPath: file.path) {
            guard let settings = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any] else {
                checks.append(Readiness(name: "Settings validation", status: "Invalid settings JSON")); continue
            }
            let env = settings["env"] as? [String: Any] ?? [:]
            if protected.contains(where: { env[$0] != nil }) || settings["apiKeyHelper"] != nil || settings["forceLoginMethod"] as? String == "console" {
                checks.append(Readiness(name: "Account isolation", status: "Settings override subscription authentication; review settings before launch"))
            }
            if settings["disableAllHooks"] as? Bool == true { checks.append(Readiness(name: "Session hooks", status: "Hooks disabled in settings")) }
        }
        if auth {
            let r = try command(executable, ["mcp", "list"], account: account, cwd: project, timeout: 35)
            let output = String(decoding: r.output, as: UTF8.self)
            // Never display/store MCP URLs, commands, headers or raw CLI output.
            let lines = output.components(separatedBy: .newlines).filter { $0.contains(":") }
            var count = 0
            for line in lines {
                guard !line.hasPrefix("Checking"), let colon = line.firstIndex(of: ":") else { continue }
                let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name.count < 100, name.allSatisfy({ $0.isLetter || $0.isNumber || "-_ .".contains($0) }) else { continue }
                count += 1
                checks.append(Readiness(name: "MCP: \(name)", status: line.contains("✓ Connected") ? "OK" : "Authentication, approval or connection required"))
            }
            if r.status != 0 || (count == 0 && !output.contains("No MCP servers configured")) {
                checks.append(Readiness(name: "MCP discovery", status: "Unknown — open account terminal and run claude mcp list"))
            }
        }
        try store.transaction {
            try store.execute("DELETE FROM mcp_readiness WHERE account_id=? AND project_path=?", [account.id, project])
            for check in checks { try store.execute("INSERT INTO mcp_readiness(account_id,project_path,name,status,checked_at) VALUES(?,?,?,?,?)", [account.id, project, check.name, check.status, store.now]) }
        }
        return checks
    }
    public func gitState(_ project: String) throws -> GitState {
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project, isDirectory: &dir), dir.boolValue else { throw SessionError.projectMissing }
        func git(_ args: [String]) throws -> String {
            let result = try command("/usr/bin/git", args, cwd: project)
            guard result.status == 0 else { throw SessionError.gitMissing }
            return String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .newlines)
        }
        return try GitState(branch: git(["branch", "--show-current"]), head: git(["rev-parse", "HEAD"]), status: git(["status", "--porcelain"]))
    }
    public func getCurrentSession(_ physical: String, store: SessionStore) throws -> String {
        let row = try store.physical(physical)
        guard row["last_hook"] != "Session ID changed" else { throw SessionError.sessionChanged }
        guard let id = row["claude_id"], UUID(uuidString: id) != nil else { throw SessionError.sessionMissing }; return id
    }
    public func listSessions(_ project: String, store: SessionStore) throws -> [ManagedSession] { try store.sessions().filter { $0.project == project } }
    public func getUsage(_ account: String, store: SessionStore) throws -> UsageSnapshot? { try store.usage(account) }
    public func resumeSession(sessionID: String) -> [String] { ["--resume", sessionID] }
    public func forkSession(snapshot: URL, sessionID: String) -> [String] { ["--resume", snapshot.path, "--fork-session", "--session-id", sessionID] }
    public func identity(_ pid: Int32) throws -> String {
        // PID + start time (µs) detects PID reuse. The command name is excluded:
        // it changes on exec (script shims, version launchers) for the same process.
        guard pid > 1, kill(pid, 0) == 0 else { return "" }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return "" }
        return "\(pid):\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
    }
    public func stopProcess(_ physical: String, store: SessionStore) throws {
        let row = try store.physical(physical)
        guard let pid = row["pid"].flatMap(Int32.init) else {
            if ["stopped", "failed"].contains(row["status"] ?? "") { return }; throw SessionError.running
        }
        if kill(pid, 0) == 0 {
            guard let expected = row["process_identity"], !expected.isEmpty, try identity(pid) == expected else { throw SessionError.running }
            // Runner creates a process group containing Claude and its tools.
            guard getpgid(pid) == pid else { throw SessionError.running }
            try store.execute("UPDATE physical_sessions SET stop_requested=1 WHERE id=?", [physical])
            guard kill(-pid, SIGTERM) == 0 else { throw SessionError.running }
        }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let state = try store.physical(physical)
            if kill(-pid, 0) != 0 && ["stopped", "failed"].contains(state["status"] ?? "") { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw SessionError.running // No SIGKILL: don't risk an unflushed transcript.
    }
    public func startProcess(arguments: [String], account: Account, project: String, launched: (Int32) throws -> Void) throws -> Int32 {
        // posix_spawn sets the process group before exec, avoiding a setpgid race.
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr); defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_addchdir_np(&actions, project) == 0 else { throw SessionError.projectMissing }
        let args = ([executable] + arguments).map { strdup($0) } + [nil]
        let env = environment(account).map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { args.forEach { free($0) }; env.forEach { free($0) } }
        var pid: pid_t = 0
        let code = args.withUnsafeBufferPointer { argv in env.withUnsafeBufferPointer { envp in
            posix_spawn(&pid, executable, &actions, &attr, argv.baseAddress!, envp.baseAddress!)
        } }
        guard code == 0 else { throw SessionError.launchFailed }
        // Keep the CLI in the foreground of Terminal's TTY; ignore SIGTTOU
        // while the runner reclaims it after Claude exits.
        let previousSignal = signal(SIGTTOU, SIG_IGN)
        defer { signal(SIGTTOU, previousSignal) }
        let oldGroup = tcgetpgrp(STDIN_FILENO)
        _ = tcsetpgrp(STDIN_FILENO, pid)
        do { try launched(pid) }
        catch { kill(-pid, SIGTERM); var s: Int32 = 0; waitpid(pid, &s, 0); throw error }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 { if errno != EINTR { throw SessionError.running } }
        if oldGroup > 0 { _ = tcsetpgrp(STDIN_FILENO, oldGroup) }
        return status
    }
    public func snapshot(physical: String, store: SessionStore) throws -> URL {
        let row = try store.physical(physical)
        guard ["stopped", "failed"].contains(row["status"] ?? ""), let path = row["transcript"], let sid = row["claude_id"] else { throw SessionError.sessionMissing }
        let account = try store.account(row["account_id"]!)
        let source = URL(fileURLWithPath: path).standardizedFileURL
        let config = URL(fileURLWithPath: account.configDir).resolvingSymlinksInPath()
        guard source.resolvingSymlinksInPath().path.hasPrefix(config.path + "/"), source.pathExtension == "jsonl",
              source.deletingPathExtension().lastPathComponent.lowercased() == sid.lowercased() else { throw SessionError.unsafePath }
        guard FileManager.default.fileExists(atPath: source.path) else { throw SessionError.sessionMissing }
        // Confirm stability after runner reaped the entire process group.
        let first = try Data(contentsOf: source)
        Thread.sleep(forTimeInterval: 0.25)
        guard first == (try Data(contentsOf: source)) else { throw SessionError.running }
        try validateTranscript(first, sessionID: sid)
        let dir = store.root.appendingPathComponent("sessions/\(row["logical_id"]!)/\(physical)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = dir.appendingPathComponent("\(UUID().uuidString).jsonl")
        try first.write(to: target, options: .atomic); chmod(target.path, 0o600)
        return target
    }
    public func validateTranscript(_ data: Data, sessionID: String) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw SessionError.corrupted }
        var conversation = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let row = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { throw SessionError.corrupted }
            if ["user", "assistant"].contains(row["type"] as? String ?? "") {
                guard row["sessionId"] as? String == sessionID, row["message"] is [String: Any] else { throw SessionError.corrupted }
                conversation = true
            }
        }
        guard conversation else { throw SessionError.corrupted }
    }
}
