import AppKit
import ClaudeSessions

@MainActor
final class ClaudeAccountsWindow: NSWindowController {
    private let store: SessionStore
    private let root: URL
    private let runner: String
    private let accountPicker = NSPopUpButton()
    private let sessionPicker = NSPopUpButton()
    private let sessionName = NSTextField(string: "New session")
    private let projectPath = NSTextField(string: "")
    private let accountSummary = NSTextField(wrappingLabelWithString: "")
    private let sessionSummary = NSTextField(wrappingLabelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "Usage becomes available after Claude's first API response. Switching is always manual.")
    private let history = NSTextView()
    private let debug = NSTextView()
    private var accounts: [Account] = []
    private var sessions: [ManagedSession] = []
    private var timer: Timer?
    private var busy = false
    private var actionButtons: [NSButton] = []
    var onChange: (() -> Void)?
    var selectedSession: ManagedSession? { sessions.first(where: { $0.id == sessionPicker.selectedItem?.representedObject as? String }) }
    var selectedAccount: Account? { accounts.first(where: { $0.id == accountPicker.selectedItem?.representedObject as? String }) }

    init(root: URL = SessionStore.defaultRoot) throws {
        self.root = root; self.store = try SessionStore(root: root)
        self.runner = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Claude Accounts & Sessions"
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 760, height: 680)
        super.init(window: window)
        build(window)
        refresh()
        timer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func button(_ title: String, _ selector: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: selector); b.bezelStyle = .rounded
        actionButtons.append(b); return b
    }
    private func build(_ window: NSWindow) {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let heading = NSTextField(labelWithString: "Claude Accounts"); heading.font = .systemFont(ofSize: 24, weight: .bold)
        stack.addArrangedSubview(heading)
        accountPicker.target = self; accountPicker.action = #selector(selectionChanged)
        sessionPicker.target = self; sessionPicker.action = #selector(selectionChanged)
        stack.addArrangedSubview(NSStackView(views: [accountPicker, button("Add account", #selector(addAccount)), button("Sign in…", #selector(login)), button("Check auth", #selector(checkAuth))]))
        stack.addArrangedSubview(accountSummary)
        let divider = NSBox(); divider.boxType = .separator; stack.addArrangedSubview(divider)
        stack.addArrangedSubview(NSTextField(labelWithString: "Project → Logical Session → Claude Account"))
        projectPath.placeholderString = "Existing local git project"
        stack.addArrangedSubview(NSStackView(views: [projectPath, button("Choose project…", #selector(chooseProject))]))
        stack.addArrangedSubview(NSStackView(views: [sessionName, button("Create & start", #selector(createSession))]))
        stack.addArrangedSubview(sessionPicker)
        stack.addArrangedSubview(sessionSummary)
        stack.addArrangedSubview(NSStackView(views: [button("Readiness", #selector(readiness)), button("Stop", #selector(stop)), button("Continue with selected account", #selector(handoff)), button("Cancel pending launch", #selector(cancelPending))]))
        stack.addArrangedSubview(button("Recover stopped session", #selector(recoverStopped)))
        message.textColor = .secondaryLabelColor; stack.addArrangedSubview(message)
        let tabs = NSTabView(); tabs.translatesAutoresizingMaskIntoConstraints = false
        for (title, view) in [("Handoff history", history), ("Developer diagnostics", debug)] {
            view.isEditable = false; view.isSelectable = true; view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = view
            let item = NSTabViewItem(identifier: title); item.label = title; item.view = scroll; tabs.addTabViewItem(item)
        }
        stack.addArrangedSubview(tabs)
        window.contentView = stack
        for view in [accountSummary, sessionSummary, message, tabs, divider] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        }
        projectPath.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        sessionName.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true
        window.center()
    }
    @objc private func selectionChanged() { renderDetails() }
    @objc func refresh() {
        do {
            let a = accountPicker.selectedItem?.representedObject as? String
            let s = sessionPicker.selectedItem?.representedObject as? String
            accounts = try store.accounts(); sessions = try store.sessions()
            accountPicker.removeAllItems(); sessionPicker.removeAllItems()
            for account in accounts { accountPicker.addItem(withTitle: account.name); accountPicker.lastItem?.representedObject = account.id }
            for session in sessions { sessionPicker.addItem(withTitle: "\(URL(fileURLWithPath: session.project).lastPathComponent) · \(session.name)"); sessionPicker.lastItem?.representedObject = session.id }
            if let i = accounts.firstIndex(where: { $0.id == a }) { accountPicker.selectItem(at: i) }
            if let i = sessions.firstIndex(where: { $0.id == s }) { sessionPicker.selectItem(at: i) }
            accountSummary.stringValue = try accounts.map { account in
                let u = try store.usage(account.id)
                let usage = u.map { "\(Int($0.percent))% · \($0.window)\($0.stale ? " · last known" : "") · reset \(formatTime($0.resetAt))" } ?? "Usage unknown — start a conversation"
                let active = sessions.contains { $0.accountID == account.id && $0.status == "active" }
                return "\(account.name) · \(account.subscription) · \(active ? "Active" : account.status)\n\(usage)"
            }.joined(separator: "\n\n")
            if accounts.isEmpty { accountSummary.stringValue = "Add Account A and Account B, then sign in to each independently." }
            renderDetails(); onChange?()
        } catch { showError(error) }
    }
    private func formatTime(_ value: Double?) -> String {
        guard let value else { return "unknown" }; return Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .shortened)
    }
    private func renderDetails() {
        guard let session = selectedSession else { sessionSummary.stringValue = "No logical sessions yet."; history.string = ""; debug.string = ""; return }
        sessionSummary.stringValue = "\(session.name) · \(session.status)\nProvider: \(accounts.first(where: { $0.id == session.accountID })?.name ?? "unknown") · Claude session: \(session.claudeID ?? "waiting for hook")\nBranch: \(session.branch?.isEmpty == false ? session.branch! : "detached / unknown") · \(session.project)"
        do {
            let rows = try store.rows("SELECT e.*,a.name,f.claude_id FROM events e LEFT JOIN accounts a ON a.id=e.account_id LEFT JOIN physical_sessions f ON f.id=e.physical_id WHERE e.logical_id=? ORDER BY e.id", [session.id])
            history.string = rows.map { "\(formatTime($0["created_at"].flatMap(Double.init)))  \($0["name"] ?? "")\n\($0["kind"] ?? "") · \($0["claude_id"] ?? "")" }.joined(separator: "\n\n")
            let f = try session.physicalID.map { try store.physical($0) } ?? [:]
            let locks = try store.rows("SELECT owner_account,pid,locked_at FROM session_locks WHERE logical_id=?", [session.id])
            let h = try store.rows("SELECT status,error FROM handoffs WHERE logical_id=? ORDER BY created_at DESC LIMIT 1", [session.id]).first
            let readiness = try store.rows("SELECT name,status FROM mcp_readiness WHERE account_id=? AND project_path=?", [selectedAccount?.id, session.project])
            debug.string = """
            Claude CLI: \(LocalClaudeCodeAdapter().executable)
            Version: \(cliVersion)
            Active account: \(accounts.first(where: { $0.id == session.accountID })?.name ?? "unknown")
            CLAUDE_CONFIG_DIR: \(accounts.first(where: { $0.id == session.accountID })?.configDir ?? "unknown")
            Logical session ID: \(session.id)
            Physical session ID: \(session.physicalID ?? "none")
            Claude session ID: \(session.claudeID ?? "unconfirmed")
            PID: \(f["pid"] ?? "none") · runner: \(f["runner_pid"] ?? "none")
            Project: \(session.project)
            Branch: \(f["branch"] ?? "unknown")
            HEAD: \(f["head"] ?? "unknown")
            Lock: \(locks.isEmpty ? "released" : "reserved / held")
            Last hook: \(session.lastHook ?? "none")
            Last handoff: \(h?["status"] ?? "none")
            Error: \(h?["error"] ?? "none")

            Readiness for selected target account:
            \(readiness.map { ($0["name"] ?? "") + ": " + ($0["status"] ?? "unknown") }.joined(separator: "\n"))
            """
        } catch { showError(error) }
    }
    private var cliVersion = "Not checked"
    private func work(_ operation: @escaping @Sendable (SessionManager) throws -> String, completion: ((String) -> Void)? = nil) {
        guard !busy else { return }; busy = true; actionButtons.forEach { $0.isEnabled = false }; message.stringValue = "Checking / working…"
        let root = root, runner = runner
        Task {
            let result: Result<String, SessionError> = await Task.detached {
                do { return .success(try operation(SessionManager(store: SessionStore(root: root), runnerExecutable: runner))) }
                catch { return .failure((error as? SessionError) ?? .launchFailed) }
            }.value
            busy = false; actionButtons.forEach { $0.isEnabled = true }
            switch result {
            case .success(let text): message.stringValue = text; completion?(text)
            case .failure(let error): showError(error)
            }
            refresh()
        }
    }
    private func showError(_ error: Error) { message.stringValue = (error as? SessionError)?.rawValue ?? SessionError.storage.rawValue }
    @objc private func addAccount() {
        let alert = NSAlert(); alert.messageText = "Add Claude account"
        alert.informativeText = "Use a different Claude Pro subscription for each account. Sign-in opens Terminal."
        let name = NSTextField(string: accounts.isEmpty ? "Claude A" : "Claude B"); name.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = name; alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { _ = try store.addAccount(name: name.stringValue); refresh(); accountPicker.selectItem(at: accounts.count - 1) } catch { showError(error) }
    }
    @objc private func login() {
        guard let account = selectedAccount else { return }
        do { let path = try SessionManager(store: store, runnerExecutable: runner).loginCommand(account); NSWorkspace.shared.open(path) }
        catch { showError(error) }
    }
    @objc private func checkAuth() {
        work { manager in
            let version = try manager.adapter.getVersion()
            for a in try manager.store.accounts() { _ = try manager.adapter.checkAuthentication(a, store: manager.store) }
            return version
        } completion: { [weak self] version in self?.cliVersion = version; self?.message.stringValue = "Account auth refreshed." }
    }
    @objc private func chooseProject() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { projectPath.stringValue = url.path }
    }
    @objc private func createSession() {
        guard let account = selectedAccount else { return }
        let project = projectPath.stringValue, name = sessionName.stringValue
        work { try $0.createSession(name: name, project: project, account: account.id) } completion: { [weak self] path in self?.openSession(path) }
    }
    @objc private func readiness() {
        guard let account = selectedAccount else { return }
        let project = selectedSession?.project ?? projectPath.stringValue
        work { manager in try manager.adapter.readiness(account, project: project, store: manager.store).map { "\($0.name): \($0.status)" }.joined(separator: " · ") }
    }
    @objc private func handoff() {
        guard let account = selectedAccount, let session = selectedSession else { return }
        let alert = NSAlert(); alert.messageText = "Continue \(session.name) with \(account.name)?"
        alert.informativeText = "Claude will stop, save a transcript snapshot, and fork the conversation using this account. Git files remain in the current working tree."
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        work { try $0.continueSession(logical: session.id, account: account.id) } completion: { [weak self] path in self?.openSession(path) }
    }
    @objc private func stop() {
        guard let id = selectedSession?.physicalID else { return }
        work { manager in try manager.adapter.stopProcess(id, store: manager.store); return "Claude stopped. Session preserved." }
    }
    @objc private func cancelPending() {
        guard let session = selectedSession else { return }
        work { manager in
            let locks = try manager.store.rows("SELECT physical_id FROM session_locks WHERE logical_id=?", [session.id])
            guard let id = locks.first?["physical_id"] else { return "No pending launch." }
            try manager.cancelLaunch(id); return "Pending launch cancelled. You can retry Continue."
        }
    }
    @objc private func recoverStopped() {
        guard let id = selectedSession?.physicalID else { return }
        work { manager in try manager.recoverStoppedSession(id); return "Stopped session recovered. You can continue." }
    }
    func continueSuggestedAccount() {
        guard let session = sessions.first(where: { $0.status == "active" }),
              let target = accounts.first(where: { $0.id != session.accountID && $0.status == "ready" }),
              let si = sessions.firstIndex(where: { $0.id == session.id }), let ai = accounts.firstIndex(where: { $0.id == target.id }) else { return }
        sessionPicker.selectItem(at: si); accountPicker.selectItem(at: ai)
        handoff()
    }

    private func openSession(_ path: String) {
        if NSWorkspace.shared.open(URL(fileURLWithPath: path)) { message.stringValue = "Terminal opened. Waiting for Claude SessionStart…" }
        else {
            let id = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            try? SessionManager(store: store).cancelLaunch(id); message.stringValue = "Terminal could not open. Launch cancelled."
        }
    }
    var islandSummary: String? {
        guard let session = sessions.first(where: { $0.status == "active" }), let id = session.accountID,
              let account = accounts.first(where: { $0.id == id }) else { return nil }
        let usage = try? store.usage(id)
        if let usage, !usage.stale, usage.percent >= 100 {
            let other = accounts.first(where: { $0.id != id && $0.status == "ready" })
            return "\(account.name) limit reached\(other.map { " · Continue with \($0.name) →" } ?? "")"
        }
        let value = usage.map { " · \(Int($0.percent))%\($0.stale ? " (last known)" : "")" } ?? " · usage unknown"
        let ready = accounts.first(where: { $0.id != id && $0.status == "ready" })
        if let usage, !usage.stale, usage.percent >= 95, let ready { return account.name + value + " · \(ready.name) auth ready" }
        return account.name + value + (session.lastHook == "SessionStart" ? " · Session restored" : "")
    }
    var islandUsage: Double? {
        guard let id = sessions.first(where: { $0.status == "active" })?.accountID else { return nil }
        return (try? store.usage(id))?.percent
    }
    var hasAccounts: Bool { !accounts.isEmpty }
}
