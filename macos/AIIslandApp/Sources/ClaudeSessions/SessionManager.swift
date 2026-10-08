import Foundation
import Darwin

public final class FileLock {
    private var fd: Int32 = -1
    public init(_ path: URL) throws {
        fd = open(path.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            if fd >= 0 { close(fd); fd = -1 }; throw SessionError.locked
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
}
public final class SessionManager {
    public let store: SessionStore
    public let adapter: LocalClaudeCodeAdapter
    public let runnerExecutable: String
    public init(store: SessionStore, adapter: LocalClaudeCodeAdapter = LocalClaudeCodeAdapter(), runnerExecutable: String = CommandLine.arguments[0]) {
        self.store = store; self.adapter = adapter; self.runnerExecutable = URL(fileURLWithPath: runnerExecutable).standardizedFileURL.path
    }
    private func requireReady(_ accountID: String, project: String, otherAccount: String? = nil) throws -> Account {
        let a = try store.account(accountID)
        let checks = try adapter.readiness(a, project: project, store: store)
        guard checks.first?.ready == true else { throw SessionError.authentication }
        let current = try store.account(accountID)
        guard ["pro", "max"].contains(current.subscription.lowercased()), !current.identity.isEmpty else { throw SessionError.authentication }
        if let otherAccount, otherAccount != accountID {
            let source = try store.account(otherAccount)
            guard source.identity.isEmpty || current.identity != source.identity else { throw SessionError.sameAccount }
        }
        guard checks.allSatisfy(\.ready) else { throw SessionError.mcp }
        if let usage = try store.usage(accountID), !usage.stale, usage.percent >= 100,
           (usage.resetAt ?? .greatestFiniteMagnitude) > Date().timeIntervalSince1970 { throw SessionError.limitReached }
        return current
    }
    public func createSession(name: String, project: String, account: String) throws -> String {
        let path = URL(fileURLWithPath: project).standardizedFileURL.resolvingSymlinksInPath().path
        _ = try requireReady(account, project: path)
        let logical = UUID().uuidString.lowercased()
        let projectID = try store.rows("SELECT id FROM projects WHERE path=?", [path]).first?["id"] ?? UUID().uuidString.lowercased()
        try store.transaction {
            try store.execute("INSERT OR IGNORE INTO projects(id,path) VALUES(?,?)", [projectID, path])
            try store.execute("INSERT INTO logical_sessions(id,project_id,name,created_at,updated_at,status) VALUES(?,?,?,?,?,'stopped')", [logical, projectID, String(name.prefix(120)), store.now, store.now])
        }
        let physical: String
        do { physical = try reserve(logical: logical, account: account, parent: nil, snapshot: nil) }
        catch { try? store.execute("DELETE FROM logical_sessions WHERE id=? AND active_physical_id IS NULL", [logical]); throw error }
        try store.event("session created", logical: logical, physical: physical, account: account)
        return try commandFile(physical: physical).path
    }
    public func continueSession(logical: String, account: String) throws -> String {
        let operationLock = try FileLock(store.root.appendingPathComponent("locks/handoff-\(logical).lock"))
        defer { withExtendedLifetime(operationLock) {} }
        guard let session = try store.sessions().first(where: { $0.id == logical }), let fromID = session.physicalID, let fromAccount = session.accountID else { throw SessionError.sessionMissing }
        _ = try requireReady(account, project: session.project, otherAccount: fromAccount == account ? nil : fromAccount)
        let handoff = UUID().uuidString.lowercased()
        try store.execute("INSERT INTO handoffs(id,logical_id,from_id,from_account,to_account,created_at,status) VALUES(?,?,?,?,?,?,'started')", [handoff, logical, fromID, fromAccount, account, store.now])
        try store.event("handoff started", logical: logical, physical: fromID, account: account)
        do {
            let before = try adapter.gitState(session.project)
            try adapter.stopProcess(fromID, store: store)
            _ = try adapter.getCurrentSession(fromID, store: store)
            let state = try adapter.gitState(session.project)
            guard before.branch == state.branch && before.head == state.head else { throw SessionError.gitChanged }
            try store.execute("UPDATE physical_sessions SET branch=?,head=?,git_status=? WHERE id=?", [state.branch, state.head, state.status, fromID])
            let snapshot = try adapter.snapshot(physical: fromID, store: store)
            let to = try reserve(logical: logical, account: account, parent: fromID, snapshot: snapshot)
            try store.execute("UPDATE handoffs SET to_id=?,status='launching' WHERE id=?", [to, handoff])
            do { return try commandFile(physical: to).path }
            catch { try cancelLaunch(to); throw error }
        } catch {
            try store.execute("UPDATE handoffs SET status='failed',error=? WHERE id=?", [(error as? SessionError)?.rawValue ?? SessionError.launchFailed.rawValue, handoff])
            try store.event("handoff failed", logical: logical, physical: fromID, account: account)
            throw error
        }
    }
    private func reserve(logical: String, account: String, parent: String?, snapshot: URL?) throws -> String {
        let physical = UUID().uuidString.lowercased(), claude = UUID().uuidString.lowercased()
        return try store.transaction {
            guard let l = try store.rows("SELECT * FROM logical_sessions WHERE id=?", [logical]).first,
                  let project = try store.rows("SELECT path FROM projects WHERE id=?", [l["project_id"]]).first?["path"] else { throw SessionError.sessionMissing }
            guard try store.rows("SELECT * FROM session_locks WHERE logical_id=? OR project_id=?", [logical, l["project_id"]]).isEmpty else { throw SessionError.locked }
            let git = try adapter.gitState(project)
            try store.execute("INSERT INTO physical_sessions(id,logical_id,account_id,claude_id,parent_id,started_at,status,resume_path,branch,head,git_status) VALUES(?,?,?,?,?,?,'pending',?,?,?,?)", [physical, logical, account, claude, parent, store.now, snapshot?.path, git.branch, git.head, git.status])
            try store.execute("INSERT INTO session_locks(logical_id,physical_id,project_id,owner_account,locked_at) VALUES(?,?,?,?,?)", [logical, physical, l["project_id"], account, store.now])
            if parent == nil { try store.execute("UPDATE logical_sessions SET active_physical_id=?,status='starting',updated_at=? WHERE id=?", [physical, store.now, logical]) }
            try store.event("lock acquired", logical: logical, physical: physical, account: account)
            return physical
        }
    }
    public func cancelLaunch(_ physical: String) throws {
        try store.transaction {
            let row = try store.physical(physical)
            guard row["status"] == "pending", row["runner_pid"] == nil else { throw SessionError.running }
            try store.execute("UPDATE physical_sessions SET status='failed',ended_at=? WHERE id=?", [store.now, physical])
            try store.execute("DELETE FROM session_locks WHERE physical_id=?", [physical])
            try store.execute("UPDATE logical_sessions SET status='failed',updated_at=? WHERE active_physical_id=?", [store.now, physical])
            try store.execute("UPDATE handoffs SET status='failed',error=? WHERE to_id=?", [SessionError.launchFailed.rawValue, physical])
            try store.event("lock released", logical: row["logical_id"], physical: physical, account: row["account_id"])
        }
    }
    public func recoverStoppedSession(_ physical: String) throws {
        let gate = try FileLock(store.root.appendingPathComponent("locks/physical-\(physical).lock"))
        defer { withExtendedLifetime(gate) {} }
        let row = try store.physical(physical)
        guard let pid = row["pid"].flatMap(Int32.init), kill(pid, 0) != 0, kill(-pid, 0) != 0 else { throw SessionError.running }
        if let runner = row["runner_pid"].flatMap(Int32.init), kill(runner, 0) == 0 { throw SessionError.running }
        guard row["last_hook"] != "Session ID changed", row["transcript"] != nil else { throw SessionError.sessionMissing }
        try finish(physical, success: true)
        try store.event("stopped session recovered", logical: row["logical_id"], physical: physical, account: row["account_id"])
    }

    public func commandFile(physical: String) throws -> URL {
        let path = store.root.appendingPathComponent("state/\(physical).command")
        let command = "#!/bin/sh\nexec " + [runnerExecutable, "--claude-run", store.root.path, physical].map(shellQuote).joined(separator: " ") + "\n"
        try Data(command.utf8).write(to: path, options: .atomic); chmod(path.path, 0o700)
        return path
    }
    /// Moves a removed account's folder aside; tests replace it to keep the user's Trash clean.
    public var discardDirectory: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    /// Removes an account that no session ever used. Its Claude login is signed out
    /// through the CLI (best effort) and its private config folder goes to the Trash.
    public func removeAccount(_ id: String) throws {
        let loginLock = try FileLock(store.root.appendingPathComponent("locks/login-\(id).lock"))
        defer { withExtendedLifetime(loginLock) {} }
        let account = try store.account(id)
        let used = try store.rows("SELECT 1 FROM physical_sessions WHERE account_id=? UNION ALL SELECT 1 FROM session_locks WHERE owner_account=? LIMIT 1", [id, id])
        guard used.isEmpty else { throw SessionError.accountInUse }
        func normalized(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
        let folder = URL(fileURLWithPath: account.configDir).deletingLastPathComponent()
        guard normalized(folder) == normalized(store.root.appendingPathComponent("accounts/\(id)")) else { throw SessionError.unsafePath }
        if FileManager.default.isExecutableFile(atPath: adapter.executable) {
            _ = try? adapter.command(adapter.executable, ["auth", "logout"], account: account, cwd: account.configDir)
        }
        try store.transaction {
            for table in ["usage_snapshots", "mcp_readiness"] { try store.execute("DELETE FROM \(table) WHERE account_id=?", [id]) }
            try store.execute("DELETE FROM accounts WHERE id=?", [id])
            try store.event("account removed", account: id)
        }
        if FileManager.default.fileExists(atPath: folder.path) { try discardDirectory(folder) }
    }
    public func loginCommand(_ account: Account) throws -> URL {
        let path = store.root.appendingPathComponent("state/login-\(account.id).command")
        let command = "#!/bin/sh\nexec " + [runnerExecutable, "--claude-login", store.root.path, account.id].map(shellQuote).joined(separator: " ") + "\n"
        try Data(command.utf8).write(to: path, options: .atomic); chmod(path.path, 0o700)
        return path
    }
    public func settings(physical: String) throws -> URL {
        let command = [runnerExecutable, "--claude-event", store.root.path, physical].map(shellQuote).joined(separator: " ")
        var hooks: [String: Any] = [:]
        for event in ["SessionStart", "Stop", "SessionEnd", "PostToolUse", "PostCompact", "StopFailure"] {
            hooks[event] = [["hooks": [["type": "command", "command": command + " " + shellQuote(event), "timeout": 10]]]]
        }
        let status = [runnerExecutable, "--claude-event", store.root.path, physical, "StatusLine"].map(shellQuote).joined(separator: " ")
        let json: [String: Any] = ["hooks": hooks, "statusLine": ["type": "command", "command": status]]
        let path = store.root.appendingPathComponent("state/hooks-\(physical).json")
        try JSONSerialization.data(withJSONObject: json).write(to: path, options: .atomic); chmod(path.path, 0o600)
        return path
    }
    public func run(physical: String) throws {
        let lock = try FileLock(store.root.appendingPathComponent("locks/physical-\(physical).lock"))
        defer { withExtendedLifetime(lock) {} }
        let row = try store.physical(physical)
        guard row["status"] == "pending" else { throw SessionError.locked }
        let logical = row["logical_id"]!, accountID = row["account_id"]!
        guard let session = try store.sessions().first(where: { $0.id == logical }) else { throw SessionError.sessionMissing }
        do {
            let account = try requireReady(accountID, project: session.project, otherAccount: row["parent_id"].flatMap { try? store.physical($0)["account_id"] })
            let git = try adapter.gitState(session.project)
            guard git.branch == row["branch"], git.head == row["head"] else { throw SessionError.gitChanged }
            try store.transaction {
                guard try store.physical(physical)["status"] == "pending" else { throw SessionError.locked }
                try store.execute("UPDATE physical_sessions SET runner_pid=?,status='starting' WHERE id=?", [String(getpid()), physical])
            }
            var arguments = ["--session-id", row["claude_id"]!]
            if let snapshot = row["resume_path"] {
                guard URL(fileURLWithPath: snapshot).resolvingSymlinksInPath().path.hasPrefix(store.root.appendingPathComponent("sessions").path + "/") else { throw SessionError.unsafePath }
                arguments = adapter.forkSession(snapshot: URL(fileURLWithPath: snapshot), sessionID: row["claude_id"]!)
            }
            arguments += ["--settings", try settings(physical: physical).path]
            let status = try adapter.startProcess(arguments: arguments, account: account, project: session.project) { pid in
                try store.execute("UPDATE physical_sessions SET pid=?,process_identity=? WHERE id=?", [String(pid), try adapter.identity(pid), physical])
                try store.execute("UPDATE session_locks SET pid=? WHERE physical_id=?", [String(pid), physical])
                try store.event("Claude process started", logical: logical, physical: physical, account: accountID)
            }
            let final = try store.physical(physical)
            if let pid = final["pid"].flatMap(Int32.init), kill(-pid, 0) == 0 { throw SessionError.running }
            let started = final["last_hook"] != nil && final["last_hook"] != "Session ID changed" && final["transcript"] != nil
            try finish(physical, success: started && (status == 0 || final["stop_requested"] == "1"))
        } catch {
            // Retain locks if a process or descendant could still be writing.
            let current = try store.physical(physical)
            if let pid = current["pid"].flatMap(Int32.init), kill(-pid, 0) == 0 { throw error }
            try finish(physical, success: false)
            throw error
        }
    }
    private func finish(_ physical: String, success: Bool) throws {
        try store.transaction {
            let row = try store.physical(physical)
            try store.execute("UPDATE physical_sessions SET status=?,ended_at=? WHERE id=?", [success ? "stopped" : "failed", store.now, physical])
            try store.execute("UPDATE logical_sessions SET status=?,updated_at=? WHERE active_physical_id=?", [success ? "stopped" : "failed", store.now, physical])
            try store.execute("DELETE FROM session_locks WHERE physical_id=?", [physical])
            if !success {
                try store.execute("UPDATE handoffs SET status='failed',error=? WHERE to_id=?", [SessionError.launchFailed.rawValue, physical])
                if let parent = row["parent_id"] {
                    try store.execute("UPDATE logical_sessions SET active_physical_id=?,status='stopped',updated_at=? WHERE active_physical_id=?", [parent, store.now, physical])
                }
                try store.event("handoff failed", logical: row["logical_id"], physical: physical, account: row["account_id"])
            }
            try store.event("Claude process stopped", logical: row["logical_id"], physical: physical, account: row["account_id"])
            try store.event("lock released", logical: row["logical_id"], physical: physical, account: row["account_id"])
        }
    }
    public func receiveEvent(physical: String, event: String, data: Data) throws {
        guard data.count <= 4_000_000, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sid = json["session_id"] as? String, UUID(uuidString: sid) != nil else { throw SessionError.sessionMissing }
        let row = try store.physical(physical)
        // Reject subagent events and /clear or /resume ID drift. A physical row
        // represents exactly one CLI session. Never silently relabel it.
        guard json["agent_id"] == nil else { return }
        if sid.lowercased() != row["claude_id"]?.lowercased() {
            if event == "SessionStart", ["starting", "active"].contains(row["status"] ?? "") {
                try store.execute("UPDATE physical_sessions SET last_hook='Session ID changed' WHERE id=?", [physical])
                try store.execute("UPDATE logical_sessions SET status='attention' WHERE active_physical_id=?", [physical])
                try store.event("session identity changed", logical: row["logical_id"], physical: physical, account: row["account_id"])
            }
            return
        }
        guard row["last_hook"] != "Session ID changed" else { return }
        guard ["starting", "active"].contains(row["status"] ?? "") else { return }
        let logical = row["logical_id"]!, account = row["account_id"]!
        let session = try store.sessions().first(where: { $0.id == logical })
        if event == "StatusLine" {
            if try recordUsage(account: account, physical: physical, json: json) { try store.event("usage limit reached", logical: logical, physical: physical, account: account) }
            return
        }
        guard ["SessionStart", "Stop", "SessionEnd", "PostToolUse", "PostCompact", "StopFailure"].contains(event),
              let path = json["transcript_path"] as? String else { throw SessionError.sessionMissing }
        let config = URL(fileURLWithPath: try store.account(account).configDir).resolvingSymlinksInPath().path
        let transcript = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard transcript.path.hasPrefix(config + "/"), transcript.pathExtension == "jsonl",
              transcript.deletingPathExtension().lastPathComponent.lowercased() == sid.lowercased() else { throw SessionError.unsafePath }
        let git = try adapter.gitState(session?.project ?? "")
        try store.transaction {
            try store.execute("UPDATE physical_sessions SET transcript=?,last_hook=?,last_activity=?,branch=?,head=?,git_status=? WHERE id=?", [transcript.path, event, store.now, git.branch, git.head, git.status, physical])
            if event == "SessionStart" {
                try store.execute("UPDATE physical_sessions SET status='active' WHERE id=?", [physical])
                try store.execute("UPDATE logical_sessions SET active_physical_id=?,status='active',updated_at=? WHERE id=?", [physical, store.now, logical])
                try store.execute("UPDATE handoffs SET status='completed' WHERE to_id=? AND status='launching'", [physical])
                try store.event(row["parent_id"] == nil ? "session started" : "session forked", logical: logical, physical: physical, account: account)
                if row["parent_id"] != nil { try store.event("handoff completed", logical: logical, physical: physical, account: account) }
            }
        }
    }
    /// Stores the statusline's rate limits for an account; true when a window is at 100%.
    @discardableResult
    public func recordUsage(account: String, physical: String?, json: [String: Any]) throws -> Bool {
        guard let rates = json["rate_limits"] as? [String: Any] else { return false }
        var windows: [(String, Double, Double?)] = []
        for name in ["five_hour", "seven_day"] {
            if let r = rates[name] as? [String: Any], let used = (r["used_percentage"] as? NSNumber)?.doubleValue, used.isFinite, (0...100).contains(used) {
                windows.append((name, used, (r["resets_at"] as? NSNumber)?.doubleValue))
            }
        }
        guard let max = windows.max(by: { $0.1 < $1.1 }) else { return false }
        try store.execute("INSERT INTO usage_snapshots(account_id,physical_id,percent,reset_at,checked_at,window) VALUES(?,?,?,?,?,?)", [account, physical, String(max.1), max.2.map { String($0) }, store.now, max.0])
        return max.1 >= 100
    }
    // Called before AppKit starts, so hooks and Terminal runners are headless.
    public static func handleCommandLine() -> Bool {
        let args = CommandLine.arguments
        if args.count >= 2, args[1] == "--cca" { exit(AccountCLI.main(Array(args.dropFirst(2)))) }
        if args.count == 4, args[1] == "--cca-statusline" {
            // A statusline must never break Claude's prompt: errors print nothing.
            let input = FileHandle.standardInput.readDataToEndOfFile()
            if let store = try? SessionStore(root: URL(fileURLWithPath: args[2])),
               let line = try? AccountCLI(manager: SessionManager(store: store)).statusLine(account: args[3], input: input) { print(line) }
            return true
        }
        guard args.count >= 4, ["--claude-run", "--claude-event", "--claude-login"].contains(args[1]) else { return false }
        do {
            let store = try SessionStore(root: URL(fileURLWithPath: args[2]))
            let manager = SessionManager(store: store)
            switch args[1] {
            case "--claude-run": try manager.run(physical: args[3])
            case "--claude-login":
                let loginLock = try FileLock(store.root.appendingPathComponent("locks/login-\(args[3]).lock"))
                defer { withExtendedLifetime(loginLock) {} }
                guard try store.rows("SELECT * FROM session_locks WHERE owner_account=?", [args[3]]).isEmpty else { throw SessionError.locked }
                let account = try store.account(args[3])
                _ = try manager.adapter.getVersion()
                print("Sign in to \(account.name). This account uses its own Claude configuration and Keychain identity.")
                _ = try manager.adapter.startProcess(arguments: ["auth", "login", "--claudeai"], account: account, project: account.configDir) { _ in }
                _ = try manager.adapter.checkAuthentication(account, store: store)
            default:
                guard args.count == 5 else { throw SessionError.sessionMissing }
                let data = FileHandle.standardInput.readDataToEndOfFile()
                try manager.receiveEvent(physical: args[3], event: args[4], data: data)
                if args[4] == "StatusLine", let row = try? store.physical(args[3]), let account = row["account_id"], let usage = try? store.usage(account) { print("Claude · \(Int(usage.percent))%") }
            }
        } catch {
            // Never print raw errors originating from JSON, URLs or subprocesses.
            let safe = (error as? SessionError)?.rawValue ?? SessionError.launchFailed.rawValue
            FileHandle.standardError.write(Data((safe + "\n").utf8))
            exit(1)
        }
        return true
    }
}
