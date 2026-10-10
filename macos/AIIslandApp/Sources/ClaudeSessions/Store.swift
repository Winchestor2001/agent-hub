import Foundation
import CSQLite
import Darwin

public enum SessionError: String, Error, LocalizedError, CaseIterable {
    case cliMissing = "Claude CLI missing. Install Claude Code and refresh."
    case unsupported = "Claude CLI lacks required resume/fork/hooks capabilities."
    case authentication = "Target account is not independently authenticated with a Claude subscription."
    case accountLimit = "MVP supports two accounts."
    case accountInUse = "This account has session history and can't be removed. Continue those sessions with another account instead."
    case accountName = "Account name can't be empty."
    case sameAccount = "Choose a different account."
    case projectMissing = "Project moved or working directory missing."
    case gitMissing = "Git repository missing or unreadable."
    case gitChanged = "Git branch or HEAD changed during handoff. Review the project before retrying."
    case mcp = "MCP readiness incomplete. Authenticate or approve servers in the target account first."
    case locked = "Session/project lock exists. Stop the owning process before continuing."
    case running = "Claude process is still running or its identity cannot be verified."
    case sessionMissing = "Session or transcript not found. Original session preserved."
    case sessionChanged = "Claude session ID changed inside Terminal. Stop and review before continuing; the manager will not fork an outdated transcript."
    case corrupted = "Transcript corrupted or contains no conversation. Original session preserved."
    case unsafePath = "Unsafe or unexpected session storage path."
    case launchFailed = "Resume/fork failed or SessionStart not confirmed. Original session preserved."
    case limitReached = "Target account also reached its limit. Check usage and reset time."
    case storage = "Session database operation failed."
    /// The English raw value is stored in the database; this is what the user reads.
    public var message: String { tr(rawValue) }
    public var errorDescription: String? { message }
}
public struct Account: Sendable {
    public let id: String
    public let name: String
    public let configDir: String
    public let status: String
    public let subscription: String
    public let checkedAt: Double?
    public let identity: String
}
public struct ManagedSession: Sendable {
    public let id: String
    public let name: String
    public let project: String
    public let status: String
    public let physicalID: String?
    public let accountID: String?
    public let claudeID: String?
    public let pid: Int32?
    public let branch: String?
    public let lastHook: String?
}
public struct UsageSnapshot: Sendable {
    public let percent: Double
    public let resetAt: Double?
    public let checkedAt: Double
    public let window: String
    public var stale: Bool { Date().timeIntervalSince1970 - checkedAt > 300 }
}
// Separate connection per process; BEGIN IMMEDIATE serializes reservations.
public final class SessionStore {
    public let root: URL
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public static var defaultRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-manager") }
    public init(root: URL = SessionStore.defaultRoot) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        for folder in ["", "accounts", "sessions", "state", "locks"] {
            let dir = self.root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard chmod(dir.path, 0o700) == 0 else { throw SessionError.storage }
        }
        guard sqlite3_open_v2(self.root.appendingPathComponent("state/sessions.sqlite").path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw SessionError.storage }
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
        try execute("""
        CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, name TEXT NOT NULL, config_dir TEXT NOT NULL UNIQUE,
          status TEXT NOT NULL DEFAULT 'unknown', subscription TEXT NOT NULL DEFAULT 'unknown', checked_at REAL, identity TEXT NOT NULL DEFAULT '');
        CREATE TABLE IF NOT EXISTS projects(id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE);
        CREATE TABLE IF NOT EXISTS logical_sessions(id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id),
          name TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL, status TEXT NOT NULL, active_physical_id TEXT);
        CREATE TABLE IF NOT EXISTS physical_sessions(id TEXT PRIMARY KEY, logical_id TEXT NOT NULL REFERENCES logical_sessions(id),
          account_id TEXT NOT NULL REFERENCES accounts(id), claude_id TEXT, parent_id TEXT REFERENCES physical_sessions(id),
          started_at REAL NOT NULL, ended_at REAL, status TEXT NOT NULL, pid INTEGER, process_identity TEXT, runner_pid INTEGER, stop_requested INTEGER NOT NULL DEFAULT 0,
          transcript TEXT, resume_path TEXT, branch TEXT, head TEXT, git_status TEXT, last_hook TEXT, last_activity REAL);
        CREATE TABLE IF NOT EXISTS handoffs(id TEXT PRIMARY KEY, logical_id TEXT NOT NULL REFERENCES logical_sessions(id),
          from_id TEXT NOT NULL REFERENCES physical_sessions(id), to_id TEXT REFERENCES physical_sessions(id),
          from_account TEXT NOT NULL, to_account TEXT NOT NULL, created_at REAL NOT NULL, status TEXT NOT NULL, error TEXT);
        CREATE TABLE IF NOT EXISTS session_locks(logical_id TEXT PRIMARY KEY REFERENCES logical_sessions(id),
          physical_id TEXT NOT NULL UNIQUE REFERENCES physical_sessions(id), project_id TEXT NOT NULL UNIQUE REFERENCES projects(id),
          owner_account TEXT NOT NULL, pid INTEGER, locked_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS usage_snapshots(id INTEGER PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
          physical_id TEXT, percent REAL NOT NULL, reset_at REAL, checked_at REAL NOT NULL, window TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS mcp_readiness(id INTEGER PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
          project_path TEXT NOT NULL, name TEXT NOT NULL, status TEXT NOT NULL, checked_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY, logical_id TEXT, physical_id TEXT, account_id TEXT,
          kind TEXT NOT NULL, created_at REAL NOT NULL);
        PRAGMA user_version=1;
        """)
        if try !rows("PRAGMA table_info(physical_sessions)").contains(where: { $0["name"] == "stop_requested" }) {
            try execute("ALTER TABLE physical_sessions ADD COLUMN stop_requested INTEGER NOT NULL DEFAULT 0")
        }
        _ = chmod(self.root.appendingPathComponent("state/sessions.sqlite").path, 0o600)
    }
    deinit { sqlite3_close(db) }
    public func execute(_ sql: String, _ values: [String?] = []) throws {
        if values.isEmpty {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw SessionError.storage }; return
        }
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SessionError.storage }
    }
    private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw SessionError.storage }
        for (i, value) in values.enumerated() {
            if let value { sqlite3_bind_text(stmt, Int32(i + 1), value, -1, transient) }
            else { sqlite3_bind_null(stmt, Int32(i + 1)) }
        }
        return stmt
    }
    public func rows(_ sql: String, _ values: [String?] = []) throws -> [[String: String]] {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        var result: [[String: String]] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw SessionError.storage }
            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                if let text = sqlite3_column_text(stmt, i) { row[String(cString: sqlite3_column_name(stmt, i))] = String(cString: text) }
            }
            result.append(row)
        }
    }
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try body(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    public var now: String { String(Date().timeIntervalSince1970) }
    public func account(_ id: String) throws -> Account {
        guard let a = try accounts().first(where: { $0.id == id }) else { throw SessionError.authentication }; return a
    }
    public func accounts() throws -> [Account] {
        try rows("SELECT * FROM accounts ORDER BY rowid").map {
            Account(id: $0["id"]!, name: $0["name"]!, configDir: $0["config_dir"]!, status: $0["status"]!,
                    subscription: $0["subscription"]!, checkedAt: $0["checked_at"].flatMap(Double.init), identity: $0["identity"] ?? "")
        }
    }
    public func addAccount(name: String) throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SessionError.accountName }
        return try transaction {
            guard try accounts().count < 2 else { throw SessionError.accountLimit }
            let id = UUID().uuidString.lowercased()
            let dir = root.appendingPathComponent("accounts/\(id)/claude-config")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try execute("INSERT INTO accounts(id,name,config_dir) VALUES(?,?,?)", [id, String(trimmed.prefix(80)), dir.path])
            try event("account selected", account: id)
            return try account(id)
        }
    }
    public func renameAccount(_ id: String, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SessionError.accountName }
        _ = try account(id)
        try execute("UPDATE accounts SET name=? WHERE id=?", [String(trimmed.prefix(80)), id])
    }
    public func sessions() throws -> [ManagedSession] {
        try rows("""
        SELECT l.*, p.path, f.account_id, f.claude_id, f.pid, f.branch, f.last_hook FROM logical_sessions l
        JOIN projects p ON p.id=l.project_id LEFT JOIN physical_sessions f ON f.id=l.active_physical_id ORDER BY l.updated_at DESC
        """).map {
            ManagedSession(id: $0["id"]!, name: $0["name"]!, project: $0["path"]!, status: $0["status"]!,
                           physicalID: $0["active_physical_id"], accountID: $0["account_id"], claudeID: $0["claude_id"],
                           pid: $0["pid"].flatMap(Int32.init), branch: $0["branch"], lastHook: $0["last_hook"])
        }
    }
    public func physical(_ id: String) throws -> [String: String] {
        guard let row = try rows("SELECT * FROM physical_sessions WHERE id=?", [id]).first else { throw SessionError.sessionMissing }; return row
    }
    /// The most limiting current window; this is what limit checks use.
    public func usage(_ account: String) throws -> UsageSnapshot? {
        try usageWindows(account).max { $0.percent < $1.percent }
    }
    /// Latest snapshot of each rate-limit window (five_hour first). A window whose reset has passed no longer applies.
    public func usageWindows(_ account: String, now: Double = Date().timeIntervalSince1970) throws -> [UsageSnapshot] {
        try ["five_hour", "seven_day"].compactMap { window in
            guard let r = try rows("SELECT * FROM usage_snapshots WHERE account_id=? AND window=? ORDER BY id DESC LIMIT 1", [account, window]).first,
                  let percent = r["percent"].flatMap(Double.init), let time = r["checked_at"].flatMap(Double.init) else { return nil }
            let reset = r["reset_at"].flatMap(Double.init)
            if let reset, reset <= now { return nil }
            return UsageSnapshot(percent: percent, resetAt: reset, checkedAt: time, window: window)
        }
    }
    public func event(_ kind: String, logical: String? = nil, physical: String? = nil, account: String? = nil) throws {
        // Fixed labels only: no subprocess output or hook bodies.
        try execute("INSERT INTO events(logical_id,physical_id,account_id,kind,created_at) VALUES(?,?,?,?,?)", [logical, physical, account, kind, now])
    }
}
public func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
