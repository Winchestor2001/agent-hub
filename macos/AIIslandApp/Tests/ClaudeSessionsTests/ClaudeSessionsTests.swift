import XCTest
import Foundation
import Darwin
@testable import ClaudeSessions

final class ClaudeSessionsTests: XCTestCase {
    var temp: URL!
    var store: SessionStore!
    var adapter: LocalClaudeCodeAdapter!
    var manager: SessionManager!
    var project: URL!
    var a: Account!
    var b: Account!
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("claude-manager-test-\(UUID().uuidString)")
        store = try SessionStore(root: temp.appendingPathComponent("manager"))
        project = temp.appendingPathComponent("project with ' quotes")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fake = temp.appendingPathComponent("fake-claude")
        try Data(fakeCLI.utf8).write(to: fake); chmod(fake.path, 0o700)
        adapter = LocalClaudeCodeAdapter(executable: fake.path)
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        manager = SessionManager(store: store, adapter: adapter, runnerExecutable: package.appendingPathComponent(".build/debug/AIIslandApp").path)
        _ = try adapter.command("/usr/bin/git", ["init", "-q"], cwd: project.path)
        _ = try adapter.command("/usr/bin/git", ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-m", "init", "-q"], cwd: project.path)
        a = try store.addAccount(name: "Claude A"); b = try store.addAccount(name: "Claude B")
        for account in [a!, b!] {
            // Test-only metadata. This is not a real credential or OAuth store.
            try Data(account.id.utf8).write(to: URL(fileURLWithPath: account.configDir).appendingPathComponent("fake-auth"))
            try Data("private-\(account.id)".utf8).write(to: URL(fileURLWithPath: account.configDir).appendingPathComponent("credential-sentinel"))
        }
    }
    override func tearDownWithError() throws {
        manager = nil; store = nil
        if let temp { try FileManager.default.removeItem(at: temp) }
    }
    func startA() throws -> ManagedSession {
        _ = try manager.createSession(name: "Auth refactoring", project: project.path, account: a.id)
        return try XCTUnwrap(store.sessions().first)
    }
    func testAccountIsolationAndTwoAccountMaximum() throws {
        XCTAssertNotEqual(a.configDir, b.configDir)
        XCTAssertThrowsError(try store.addAccount(name: "C")) { XCTAssertEqual($0 as? SessionError, .accountLimit) }
        let env = adapter.environment(b)
        XCTAssertEqual(env["CLAUDE_CONFIG_DIR"], b.configDir)
        XCTAssertEqual(env["CLAUDE_SECURESTORAGE_CONFIG_DIR"], b.configDir)
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDECODE", "CLAUDE_CONFIG_DIR_OVERRIDE"] { XCTAssertNil(env[key]) }
        XCTAssertEqual(try adapter.getVersion(), "2.1.284 (Fixture)")
        let permissions = try FileManager.default.attributesOfItem(atPath: store.root.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)
    }
    func testLiveFixtureForkAtoBtoAWithHooksAndDirtyGit() throws {
        let original = try startA()
        try manager.run(physical: original.physicalID!)
        let sidA = try adapter.getCurrentSession(original.physicalID!, store: store)
        let gitBefore = try adapter.gitState(project.path)
        XCTAssertTrue(gitBefore.status.contains("progress.txt"))
        _ = try manager.continueSession(logical: original.id, account: b.id)
        let pending = try XCTUnwrap(store.rows("SELECT * FROM physical_sessions WHERE account_id=?", [b.id]).first)
        // Active session doesn't change until the target SessionStart hook arrives.
        XCTAssertEqual(try store.sessions().first?.accountID, a.id)
        try manager.run(physical: pending["id"]!)
        let afterB = try XCTUnwrap(store.sessions().first)
        XCTAssertEqual(afterB.id, original.id)
        XCTAssertEqual(afterB.accountID, b.id)
        XCTAssertNotEqual(afterB.claudeID, sidA)
        XCTAssertEqual(try store.rows("SELECT status FROM handoffs").first?["status"], "completed")
        _ = try manager.continueSession(logical: original.id, account: a.id)
        let target = try XCTUnwrap(store.rows("SELECT id FROM physical_sessions WHERE parent_id=?", [afterB.physicalID]).first?["id"])
        try manager.run(physical: target)
        XCTAssertEqual(try store.sessions().first?.accountID, a.id)
        XCTAssertEqual(try store.rows("SELECT * FROM physical_sessions").count, 3)
        XCTAssertEqual(try store.rows("SELECT * FROM handoffs WHERE status='completed'").count, 2)
        XCTAssertTrue(try store.rows("SELECT * FROM session_locks").isEmpty)
        let final = try store.physical(target)
        let transcript = try String(contentsOfFile: final["transcript"]!, encoding: .utf8)
        XCTAssertTrue(transcript.contains("context from previous account"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: b.configDir).appendingPathComponent("credential-sentinel-A").path))
        XCTAssertEqual(try adapter.gitState(project.path).head, gitBefore.head)
        XCTAssertEqual(try adapter.gitState(project.path).branch, gitBefore.branch)
        let events = try store.rows("SELECT kind FROM events WHERE logical_id=?", [original.id]).compactMap { $0["kind"] }
        XCTAssertTrue(events.contains("handoff completed")); XCTAssertTrue(events.contains("lock released"))
        XCTAssertEqual(try store.usage(a.id)?.percent, 82)
    }
    func testProjectReservationIsDurableAcrossConnections() throws {
        let session = try startA()
        let other = try SessionStore(root: store.root)
        let second = SessionManager(store: other, adapter: adapter)
        XCTAssertThrowsError(try second.createSession(name: "Concurrent", project: project.path, account: b.id)) { XCTAssertEqual($0 as? SessionError, .locked) }
        XCTAssertEqual(try other.rows("SELECT physical_id FROM session_locks").first?["physical_id"], session.physicalID)
        try manager.cancelLaunch(session.physicalID!)
        XCTAssertTrue(try other.rows("SELECT * FROM session_locks").isEmpty)
        XCTAssertThrowsError(try manager.run(physical: session.physicalID!))
    }
    func testOSLockExcludesAnotherOwner() throws {
        let url = store.root.appendingPathComponent("locks/test.lock")
        let lock = try FileLock(url)
        XCTAssertThrowsError(try FileLock(url)) { XCTAssertEqual($0 as? SessionError, .locked) }
        withExtendedLifetime(lock) {}
    }
    func testUnauthenticatedTargetDoesNotStopOrModifySource() throws {
        let session = try startA(); try manager.run(physical: session.physicalID!)
        try FileManager.default.removeItem(at: URL(fileURLWithPath: b.configDir).appendingPathComponent("fake-auth"))
        XCTAssertThrowsError(try manager.continueSession(logical: session.id, account: b.id)) { XCTAssertEqual($0 as? SessionError, .authentication) }
        XCTAssertEqual(try store.sessions().first?.physicalID, session.physicalID)
        XCTAssertTrue(try store.rows("SELECT * FROM handoffs").isEmpty)
    }
    func testMCPReadinessBlocksBeforeSourceChanges() throws {
        let session = try startA(); try manager.run(physical: session.physicalID!)
        try Data("{}".utf8).write(to: URL(fileURLWithPath: b.configDir).appendingPathComponent("mcp-blocked"))
        XCTAssertThrowsError(try manager.continueSession(logical: session.id, account: b.id)) { XCTAssertEqual($0 as? SessionError, .mcp) }
        let checks = try store.rows("SELECT * FROM mcp_readiness WHERE account_id=?", [b.id])
        XCTAssertTrue(checks.contains { $0["name"] == "MCP: github" && $0["status"] != "OK" })
        XCTAssertFalse(checks.description.contains("secret-url"))
    }
    func testCorruptTranscriptAndSymlinkRefusedWithoutChangingSource() throws {
        let session = try startA(); try manager.run(physical: session.physicalID!)
        let row = try store.physical(session.physicalID!)
        let path = row["transcript"]!
        try Data("{broken".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertThrowsError(try manager.continueSession(logical: session.id, account: b.id)) { XCTAssertEqual($0 as? SessionError, .corrupted) }
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "{broken")
        try store.execute("UPDATE physical_sessions SET transcript=? WHERE id=?", ["/private/tmp/credentials.jsonl", session.physicalID])
        XCTAssertThrowsError(try adapter.snapshot(physical: session.physicalID!, store: store)) { XCTAssertEqual($0 as? SessionError, .unsafePath) }
    }
    func testHookIDDriftAndSecretPayloadAreNotPersisted() throws {
        let session = try startA()
        try store.execute("UPDATE physical_sessions SET status='starting' WHERE id=?", [session.physicalID])
        let wrong: [String: Any] = ["session_id": UUID().uuidString, "transcript_path": "/secret", "access_token": "SECRET_SENTINEL"]
        try manager.receiveEvent(physical: session.physicalID!, event: "PostToolUse", data: JSONSerialization.data(withJSONObject: wrong))
        XCTAssertNil(try store.physical(session.physicalID!)["last_hook"])
        let usage: [String: Any] = ["session_id": session.claudeID!, "access_token": "SECRET_SENTINEL", "rate_limits": ["five_hour": ["used_percentage": 32, "resets_at": 1900000000], "seven_day": ["used_percentage": 96, "resets_at": 1900001000]]]
        try manager.receiveEvent(physical: session.physicalID!, event: "StatusLine", data: JSONSerialization.data(withJSONObject: usage))
        XCTAssertEqual(try store.usage(a.id)?.percent, 96)
        XCTAssertEqual(try store.usage(a.id)?.window, "seven_day")
        for table in ["accounts", "physical_sessions", "events", "usage_snapshots"] { XCTAssertFalse(try store.rows("SELECT * FROM \(table)").description.contains("SECRET_SENTINEL")) }
    }
    func testMissingProjectGitAndCLIHaveExplicitErrors() throws {
        XCTAssertThrowsError(try adapter.gitState(temp.appendingPathComponent("moved").path)) { XCTAssertEqual($0 as? SessionError, .projectMissing) }
        XCTAssertThrowsError(try adapter.gitState(temp.path)) { XCTAssertEqual($0 as? SessionError, .gitMissing) }
        XCTAssertThrowsError(try LocalClaudeCodeAdapter(executable: "/missing/claude").getVersion()) { XCTAssertEqual($0 as? SessionError, .cliMissing) }
    }
    func testLimitAndSameIdentityBlocked() throws {
        let session = try startA(); try manager.run(physical: session.physicalID!)
        try Data(a.id.utf8).write(to: URL(fileURLWithPath: b.configDir).appendingPathComponent("fake-auth"))
        XCTAssertThrowsError(try manager.continueSession(logical: session.id, account: b.id)) { XCTAssertEqual($0 as? SessionError, .sameAccount) }
        try Data(b.id.utf8).write(to: URL(fileURLWithPath: b.configDir).appendingPathComponent("fake-auth"))
        try store.execute("INSERT INTO usage_snapshots(account_id,percent,reset_at,checked_at,window) VALUES(?,?,?,?,?)", [b.id, "100", String(Date().timeIntervalSince1970 + 3600), store.now, "five_hour"])
        XCTAssertThrowsError(try manager.continueSession(logical: session.id, account: b.id)) { XCTAssertEqual($0 as? SessionError, .limitReached) }
    }
    func testShellQuotingDoesNotExecuteInjectedText() throws {
        let text = "name ' $(touch /tmp/should-not-exist) `whoami`\nnext"
        let r = try adapter.command("/bin/sh", ["-c", "printf %s " + shellQuote(text)])
        XCTAssertEqual(String(decoding: r.output, as: UTF8.self), text)
    }
    func testFailedForkRestoresSourcePointerAndRetainsSnapshot() throws {
        let source = try startA(); try manager.run(physical: source.physicalID!)
        try Data().write(to: URL(fileURLWithPath: b.configDir).appendingPathComponent("fail-fork"))
        _ = try manager.continueSession(logical: source.id, account: b.id)
        let target = try XCTUnwrap(store.rows("SELECT id FROM physical_sessions WHERE account_id=?", [b.id]).first?["id"])
        try manager.run(physical: target)
        XCTAssertEqual(try store.sessions().first?.physicalID, source.physicalID)
        XCTAssertEqual(try store.rows("SELECT status FROM handoffs").first?["status"], "failed")
        let snapshot = try XCTUnwrap(store.physical(target)["resume_path"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot))
        XCTAssertTrue(try store.rows("SELECT * FROM session_locks").isEmpty)
    }
    func testStopLiveProcessWaitsForRunnerAndReleasesLock() throws {
        let source = try startA()
        try Data().write(to: URL(fileURLWithPath: a.configDir).appendingPathComponent("hold-open"))
        let root = store.root, executable = adapter.executable, runner = manager.runnerExecutable, physical = source.physicalID!
        let finished = expectation(description: "Runner reaped Claude")
        Thread.detachNewThread {
            defer { finished.fulfill() }
            do { try SessionManager(store: SessionStore(root: root), adapter: LocalClaudeCodeAdapter(executable: executable), runnerExecutable: runner).run(physical: physical) }
            catch { /* Main thread assertions inspect the persisted result. */ }
        }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if try store.physical(physical)["last_hook"] == "SessionStart" { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(try store.physical(physical)["status"], "active")
        XCTAssertFalse(try store.rows("SELECT * FROM session_locks").isEmpty)
        try adapter.stopProcess(physical, store: store)
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(try store.physical(physical)["status"], "stopped")
        XCTAssertTrue(try store.rows("SELECT * FROM session_locks").isEmpty)
    }
    func testAuthOverrideInSharedProjectSettingsBlocksLaunch() throws {
        let dir = project.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"env":{"ANTHROPIC_AUTH_TOKEN":"SECRET_SENTINEL"}}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        XCTAssertThrowsError(try startA()) { XCTAssertEqual($0 as? SessionError, .mcp) }
        XCTAssertFalse(try store.rows("SELECT * FROM mcp_readiness").description.contains("SECRET_SENTINEL"))
    }
    func testSessionIdentityDriftRequiresReview() throws {
        let session = try startA()
        try store.execute("UPDATE physical_sessions SET status='starting' WHERE id=?", [session.physicalID])
        let event: [String: Any] = ["session_id": UUID().uuidString, "transcript_path": "/not-copied"]
        try manager.receiveEvent(physical: session.physicalID!, event: "SessionStart", data: JSONSerialization.data(withJSONObject: event))
        XCTAssertEqual(try store.physical(session.physicalID!)["last_hook"], "Session ID changed")
        XCTAssertThrowsError(try adapter.getCurrentSession(session.physicalID!, store: store)) { XCTAssertEqual($0 as? SessionError, .sessionChanged) }
    }
    func testUnsupportedVersionAndMissingTranscript() throws {
        let old = temp.appendingPathComponent("old-claude")
        try Data(fakeCLI.replacingOccurrences(of: "2.1.284 (Fixture)", with: "2.0.0 (Fixture)").utf8).write(to: old); chmod(old.path, 0o700)
        XCTAssertThrowsError(try LocalClaudeCodeAdapter(executable: old.path).getVersion()) { XCTAssertEqual($0 as? SessionError, .unsupported) }
        let source = try startA(); try manager.run(physical: source.physicalID!)
        try FileManager.default.removeItem(atPath: store.physical(source.physicalID!)["transcript"]!)
        XCTAssertThrowsError(try manager.continueSession(logical: source.id, account: b.id)) { XCTAssertEqual($0 as? SessionError, .sessionMissing) }
        XCTAssertEqual(try store.sessions().first?.physicalID, source.physicalID)
    }
    private var fakeCLI: String { #"""
#!/usr/bin/python3
import os,sys,json,uuid,subprocess
from pathlib import Path
args=sys.argv[1:]
config=Path(os.environ.get('CLAUDE_CONFIG_DIR','/missing'))
if args==['--version']:
 print('2.1.284 (Fixture)'); sys.exit(0)
if args==['--help']:
 print('--resume --fork-session --session-id --settings'); sys.exit(0)
if args[:2]==['auth','status']:
 auth=config/'fake-auth'
 ok=auth.exists()
 print(json.dumps({'loggedIn':ok,'authMethod':'claude.ai' if ok else 'none','subscriptionType':'pro' if ok else None,'email':auth.read_text()+'@example.invalid' if ok else None})); sys.exit(0 if ok else 1)
if args==['mcp','list']:
 print('github: https://secret-url - ! Needs authentication' if (config/'mcp-blocked').exists() else 'No MCP servers configured.')
 sys.exit(0)
sid=args[args.index('--session-id')+1]
settings=json.loads(Path(args[args.index('--settings')+1]).read_text())
transcript=config/'projects'/'fixture'/ (sid+'.jsonl')
transcript.parent.mkdir(parents=True,exist_ok=True)
rows=[]
if '--resume' in args:
 for line in Path(args[args.index('--resume')+1]).read_text().splitlines():
  row=json.loads(line); row['sessionId']=sid; rows.append(row)
rows.append({'type':'user','sessionId':sid,'uuid':str(uuid.uuid4()),'message':{'role':'user','content':'context from previous account'}})
transcript.write_text('\n'.join(json.dumps(r) for r in rows)+'\n')
Path('progress.txt').write_text('work remains in git working tree')
def event(name):
 payload={'session_id':sid,'transcript_path':str(transcript),'cwd':os.getcwd(),'hook_event_name':name}
 for group in settings['hooks'].get(name,[]):
  for h in group['hooks']:
   subprocess.run(h['command'],shell=True,input=json.dumps(payload).encode(),check=True)
event('SessionStart')
payload={'session_id':sid,'rate_limits':{'five_hour':{'used_percentage':82,'resets_at':1900000000}}}
subprocess.run(settings['statusLine']['command'],shell=True,input=json.dumps(payload).encode(),check=True)
if (config/'fail-fork').exists(): sys.exit(7)
if (config/'hold-open').exists():
 import time
 time.sleep(90)
event('Stop'); event('SessionEnd')
"""# }
}
