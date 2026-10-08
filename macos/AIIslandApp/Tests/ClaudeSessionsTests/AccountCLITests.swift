import XCTest
import Foundation
import Darwin
@testable import ClaudeSessions

final class AccountCLITests: XCTestCase {
    var temp: URL!
    var global: URL!
    var project: URL!
    var store: SessionStore!
    var cli: AccountCLI!
    var a: Account!
    var b: Account!

    // Signed in when the fixture marker exists. No real credentials are involved.
    let fakeClaude = """
    #!/bin/sh
    if [ "$1 $2" = "auth status" ]; then
      if [ -f "$CLAUDE_CONFIG_DIR/fake-auth" ]; then echo '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"pro","email":"'$(basename "$(dirname "$CLAUDE_CONFIG_DIR")")'@example.invalid"}'; exit 0; fi
      echo '{"loggedIn":false}'; exit 1
    fi
    exit 0
    """

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("cca-test-\(UUID().uuidString)")
        global = temp.appendingPathComponent("global-claude")
        project = temp.appendingPathComponent("my project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        store = try SessionStore(root: temp.appendingPathComponent("manager"))
        let fake = temp.appendingPathComponent("claude")
        try Data(fakeClaude.utf8).write(to: fake); chmod(fake.path, 0o700)
        let manager = SessionManager(store: store, adapter: LocalClaudeCodeAdapter(executable: fake.path), runnerExecutable: "/usr/bin/true")
        cli = AccountCLI(manager: manager, globalConfig: global, environment: ["HOME": "/tmp", "ANTHROPIC_API_KEY": "should-be-dropped", "TERM": "xterm"])
        a = try store.addAccount(name: "Personal"); b = try store.addAccount(name: "Work")
        for account in [a!, b!] { try Data().write(to: URL(fileURLWithPath: account.configDir).appendingPathComponent("fake-auth")) }
    }

    override func tearDownWithError() throws {
        cli = nil; store = nil
        try FileManager.default.removeItem(at: temp)
    }

    var cwd: String { project.resolvingSymlinksInPath().path }

    /// Writes a transcript the way Claude does: config/projects/<encoded cwd>/<id>.jsonl.
    @discardableResult
    func transcript(_ id: String, in config: URL, title: String? = nil, text: String = "hello", age: Double = 0) throws -> URL {
        let dir = config.appendingPathComponent("projects/\(AccountCLI.encode(cwd))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var rows: [[String: Any]] = [
            ["type": "user", "sessionId": id, "cwd": cwd, "message": ["role": "user", "content": text]],
            ["type": "assistant", "sessionId": id, "cwd": cwd, "message": ["role": "assistant", "content": [["type": "text", "text": "hi"]]]],
        ]
        if let title { rows.append(["type": "ai-title", "aiTitle": title, "sessionId": id]) }
        let body = try rows.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined(separator: "\n") + "\n"
        let url = dir.appendingPathComponent("\(id).jsonl")
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    func testEncodeMatchesClaudeProjectFolders() {
        XCTAssertEqual(AccountCLI.encode("/Users/me/my-projects/agent hub"), "-Users-me-my-projects-agent-hub")
        XCTAssertEqual(AccountCLI.encode("/private/tmp/x.y_z"), "-private-tmp-x-y-z")
    }

    func testAccountSelectionByNumberAndName() throws {
        XCTAssertEqual(try cli.account("1").id, a.id)
        XCTAssertEqual(try cli.account("work").id, b.id)
        XCTAssertThrowsError(try cli.account("3"))
        XCTAssertThrowsError(try cli.account("0"))
        XCTAssertThrowsError(try cli.account("nobody"))
    }

    func testNewSessionLaunchUsesAccountConfigAndDropsOverrides() throws {
        let launch = try cli.plan(["2", "--model", "opus"], cwd: cwd)
        XCTAssertNil(launch.session)
        XCTAssertEqual(launch.directory, cwd)
        XCTAssertEqual(launch.environment["CLAUDE_CONFIG_DIR"], b.configDir)
        XCTAssertEqual(launch.environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"], b.configDir)
        XCTAssertNil(launch.environment["ANTHROPIC_API_KEY"])
        XCTAssertEqual(launch.environment["TERM"], "xterm")
        XCTAssertEqual(launch.arguments.first, "--settings")
        XCTAssertEqual(Array(launch.arguments.suffix(2)), ["--model", "opus"])
        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: launch.arguments[1]))) as? [String: Any]
        let command = (settings?["statusLine"] as? [String: Any])?["command"] as? String ?? ""
        XCTAssertTrue(command.contains("--cca-statusline") && command.contains(b.id))
    }

    func testContinueGlobalSessionOnAccountKeepsIdAndCopiesTranscript() throws {
        let id = "3543d72e-ce41-458b-98d7-3c223b7e6ef8"
        let source = try transcript(id, in: global, title: "Auth refactoring")
        let sidecar = source.deletingPathExtension().appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: sidecar.appendingPathComponent("agent.jsonl"))
        let elsewhere = temp.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)

        let launch = try cli.plan(["1", "3543d7"], cwd: elsewhere.path)
        XCTAssertEqual(launch.session, id)
        XCTAssertEqual(launch.directory, cwd, "Claude resumes in the session's own folder")
        XCTAssertEqual(Array(launch.arguments.prefix(2)), ["--resume", id])
        let copied = URL(fileURLWithPath: a.configDir).appendingPathComponent("projects/\(AccountCLI.encode(cwd))/\(id).jsonl")
        XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: source))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.deletingPathExtension().appendingPathComponent("subagents/agent.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "~/.claude copy is never moved")

        // Account 1 continued it; moving to account 2 takes account 1's newer copy.
        try Data((try String(contentsOf: copied, encoding: .utf8)) .appending(#"{"type":"user","sessionId":"\#(id)","cwd":"\#(cwd)","message":{"role":"user","content":"more"}}"# + "\n").utf8).write(to: copied)
        _ = try cli.plan(["work", id], cwd: cwd)
        let second = URL(fileURLWithPath: b.configDir).appendingPathComponent("projects/\(AccountCLI.encode(cwd))/\(id).jsonl")
        XCTAssertEqual(try Data(contentsOf: second), try Data(contentsOf: copied))
        XCTAssertEqual(cli.sessions(cwd: cwd).count, 1, "One session, however many accounts hold a copy")
        XCTAssertEqual(cli.info(cli.sessions(cwd: cwd)[0]).title, "Auth refactoring")
    }

    func testContinueLatestAndPrefixErrors() throws {
        try transcript("aaaa1111-0000-4000-8000-000000000001", in: global, text: "old work", age: 600)
        try transcript("aaaa2222-0000-4000-8000-000000000002", in: URL(fileURLWithPath: a.configDir), text: "Fix login\nmore", age: 10)
        let launch = try cli.plan(["2", "-c"], cwd: cwd)
        XCTAssertEqual(launch.session, "aaaa2222-0000-4000-8000-000000000002")
        XCTAssertThrowsError(try cli.plan(["2", "aaaa"], cwd: cwd)) { XCTAssertTrue("\($0)".contains("several sessions")) }
        XCTAssertThrowsError(try cli.plan(["2", "abc"], cwd: cwd)) { XCTAssertTrue("\($0)".contains("at least 4")) }
        XCTAssertThrowsError(try cli.plan(["2", "ffff9999"], cwd: cwd)) { XCTAssertTrue("\($0)".contains("No Claude session")) }
        let empty = temp.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try cli.plan(["2", "-c"], cwd: empty.path)) { XCTAssertTrue("\($0)".contains("No Claude session in this folder")) }
        let list = cli.list(cwd: cwd)
        XCTAssertTrue(list.contains("1  Personal") && list.contains("2  Work"))
        XCTAssertTrue(list.contains("aaaa2222  Fix login") && list.contains("Personal"))
    }

    func testOpenSessionSignedOutAndLimitedAccountsAreRefused() throws {
        let id = "bbbb0000-0000-4000-8000-000000000001"
        try transcript(id, in: global)
        let sessions = global.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["pid": Int(getpid()), "sessionId": id]).write(to: sessions.appendingPathComponent("1.json"))
        XCTAssertThrowsError(try cli.plan(["1", id], cwd: cwd)) { XCTAssertTrue("\($0)".contains("still open in global")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: a.configDir).appendingPathComponent("projects").path))

        try FileManager.default.removeItem(at: URL(fileURLWithPath: b.configDir).appendingPathComponent("fake-auth"))
        XCTAssertThrowsError(try cli.plan(["2"], cwd: cwd)) { XCTAssertTrue("\($0)".contains("cca login 2")) }

        let input = #"{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":\#(Date().timeIntervalSince1970 + 3600)}}}"#
        let line = try cli.statusLine(account: a.id, input: Data(input.utf8))
        XCTAssertTrue(line.hasPrefix("\u{1B}[1;30;46m Personal "), line)
        XCTAssertTrue(line.contains("Opus") && line.contains("5h 100% (resets in 59m)") && !line.contains("7d"), line)
        let other = try cli.statusLine(account: b.id, input: Data(#"{"workspace":{"current_dir":"/tmp"},"context_window":{"remaining_percentage":41.6},"rate_limits":{"five_hour":{"used_percentage":12},"seven_day":{"used_percentage":80.4}}}"#.utf8))
        XCTAssertTrue(other.hasPrefix("\u{1B}[1;30;45m Work ") && other.contains("/tmp") && other.contains("42% left") && other.contains("5h 12%") && other.contains("2;31m7d 80%"), other)
        XCTAssertEqual(try store.usageWindows(b.id).map(\.window), ["five_hour", "seven_day"])
        XCTAssertEqual(try store.usage(b.id)?.percent, 80.4)
        XCTAssertThrowsError(try cli.plan(["1"], cwd: cwd)) { XCTAssertTrue("\($0)".contains("reached its limit")) }
        XCTAssertTrue(cli.list(cwd: cwd).contains("100% (5h) · resets"))
    }
}
