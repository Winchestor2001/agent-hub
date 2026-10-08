import AppKit
import ClaudeSessions

/// Rounded card; clicks on its background (not on its controls) call `onClick`.
private final class CardView: NSView {
    var onClick: (() -> Void)?
    var selected = false { didSet { needsDisplay = true } }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = selected ? 2 : 1
        layer?.borderColor = (selected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }
    override func mouseDown(with event: NSEvent) {
        if let onClick { onClick() } else { super.mouseDown(with: event) }
    }
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }

@MainActor
final class ClaudeAccountsWindow: NSWindowController {
    private let store: SessionStore
    private let root: URL
    private let runner: String
    private let stack = NSStackView()
    private let addButton = NSButton()
    private let accountsList = NSStackView()
    private let sessionsList = NSStackView()
    private let newSessionButton = NSButton()
    private let detailsTitle = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "Usage appears after an account's first Claude response. Switching accounts is always manual.")
    private let history = NSTextView()
    private let debug = NSTextView()
    private var accounts: [Account] = []
    private var sessions: [ManagedSession] = []
    private var selectedSessionID: String?
    private var lastProject = ""
    private var renderedSignature = ""
    private var timer: Timer?
    private var busy = false
    private var actionControls: [NSControl] = []
    var onChange: (() -> Void)?
    private var selectedSession: ManagedSession? {
        sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

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

    // MARK: Layout

    private func build(_ window: NSWindow) {
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for list in [accountsList, sessionsList] { list.orientation = .vertical; list.alignment = .leading; list.spacing = 8 }

        addButton.title = "Add account"; addButton.bezelStyle = .rounded
        addButton.target = self; addButton.action = #selector(addAccount)
        newSessionButton.title = "New session…"; newSessionButton.bezelStyle = .rounded
        newSessionButton.target = self; newSessionButton.action = #selector(newSession)

        stack.addArrangedSubview(headerRow("Claude Accounts", size: 24, trailing: addButton))
        stack.addArrangedSubview(secondary("Each account uses its own Claude subscription and sign-in. Sign-in opens in Terminal."))
        stack.addArrangedSubview(accountsList)
        stack.setCustomSpacing(24, after: accountsList)
        stack.addArrangedSubview(headerRow("Sessions", size: 18, trailing: newSessionButton))
        stack.addArrangedSubview(sessionsList)
        message.textColor = .secondaryLabelColor
        stack.addArrangedSubview(message)
        stack.setCustomSpacing(20, after: message)
        detailsTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(detailsTitle)
        let details = NSStackView(views: [textPanel("Handoff history", history), textPanel("Developer diagnostics", debug)])
        details.distribution = .fillEqually; details.spacing = 12
        stack.addArrangedSubview(details)

        let document = FlippedView(); document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        scroll.drawsBackground = true; scroll.backgroundColor = .windowBackgroundColor
        scroll.documentView = document
        window.contentView = scroll
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        for view in stack.arrangedSubviews { fullWidth(view) }
        details.heightAnchor.constraint(equalToConstant: 220).isActive = true
        window.center()
    }

    private func fullWidth(_ view: NSView) {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
    }

    private func headerRow(_ title: String, size: CGFloat, trailing: NSView) -> NSView {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: size, weight: .bold)
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [label, spacer, trailing]); row.alignment = .centerY
        return row
    }

    private func secondary(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text); label.textColor = .secondaryLabelColor
        return label
    }

    private func textPanel(_ title: String, _ view: NSTextView) -> NSView {
        view.isEditable = false; view.isSelectable = true; view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.autoresizingMask = [.width]; view.textContainerInset = NSSize(width: 6, height: 6)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.documentView = view
        let label = NSTextField(labelWithString: title); label.textColor = .secondaryLabelColor
        let column = NSStackView(views: [label, scroll]); column.orientation = .vertical; column.alignment = .leading
        scroll.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    private func card(_ content: NSView, selected: Bool = false, onClick: (() -> Void)? = nil) -> NSView {
        let card = CardView(); card.wantsLayer = true; card.selected = selected; card.onClick = onClick
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        ])
        return card
    }

    private func button(_ title: String, _ selector: Selector, id: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: selector); b.bezelStyle = .rounded
        b.identifier = NSUserInterfaceItemIdentifier(id); b.isEnabled = !busy
        actionControls.append(b); return b
    }

    /// Pull-down button; items are (title, action, value), nil entries become separators.
    private func menuButton(_ title: String, _ items: [(String, Selector, String)?], tip: String? = nil) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        popup.addItem(withTitle: title)
        if title == "⋯" { (popup.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow }
        for entry in items {
            guard let (itemTitle, action, value) = entry else { popup.menu?.addItem(.separator()); continue }
            let item = NSMenuItem(title: itemTitle, action: action, keyEquivalent: "")
            item.target = self; item.representedObject = value
            popup.menu?.addItem(item)
        }
        popup.toolTip = tip; popup.isEnabled = !busy && !items.isEmpty
        actionControls.append(popup); return popup
    }

    // MARK: Data

    @objc func refresh() {
        do {
            accounts = try store.accounts(); sessions = try store.sessions()
            let usage = try accounts.map { try store.usage($0.id) }
            usageRows = try accounts.map { (account: $0, status: statusText($0), windows: try store.usageWindows($0.id)) }
            var parts: [String] = accounts.map { a in "\(a.id)|\(a.name)|\(a.status)|\(a.subscription)" }
            parts += usageRows.flatMap { row in row.windows.map { (u: UsageSnapshot) -> String in
                "\(u.percent)|\(u.resetAt ?? 0)|\(u.stale)|\(u.window)"
            } }
            parts += sessions.map { (s: ManagedSession) -> String in
                "\(s.id)|\(s.name)|\(s.status)|\(s.accountID ?? "")|\(s.branch ?? "")|\(s.physicalID ?? "")"
            }
            parts.append("\(selectedSession?.id ?? "")|\(busy)")
            let signature = parts.joined(separator: ";")
            if signature != renderedSignature {
                renderedSignature = signature
                actionControls.removeAll()
                renderAccounts(usage: usage); renderSessions()
            }
            renderDetails(); onChange?()
        } catch { showError(error) }
    }

    private func statusText(_ account: Account) -> String {
        if sessions.contains(where: { $0.accountID == account.id && $0.status == "active" }) { return "Active" }
        switch account.status {
        case "ready": return "Ready"
        case "signed out": return "Signed out"
        default: return "Not checked"
        }
    }

    private func renderAccounts(usage: [UsageSnapshot?]) {
        accountsList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        addButton.isEnabled = !busy && accounts.count < 2
        addButton.toolTip = accounts.count < 2 ? nil : "AI Island supports two accounts. Remove one to add another."
        if accounts.isEmpty {
            let empty = secondary("No accounts yet. Click Add account, then finish signing in in Terminal.")
            accountsList.addArrangedSubview(card(empty)); fullWidth(accountsList.arrangedSubviews[0])
            return
        }
        for (account, usage) in zip(accounts, usage) {
            let status = statusText(account)
            let dot = NSTextField(labelWithString: "●")
            dot.textColor = status == "Ready" || status == "Active" ? .systemGreen : status == "Signed out" ? .secondaryLabelColor : .systemOrange
            let name = NSTextField(labelWithString: account.name); name.font = .systemFont(ofSize: 14, weight: .semibold)
            let plan = account.subscription == "unknown" ? "" : " · \(account.subscription.capitalized)"
            let state = NSTextField(labelWithString: status + plan); state.textColor = .secondaryLabelColor
            let title = NSStackView(views: [dot, name, state]); title.spacing = 6

            let usageText: String
            let bar = NSProgressIndicator(); bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100
            bar.widthAnchor.constraint(equalToConstant: 180).isActive = true
            if let usage {
                let window = usage.window == "seven_day" ? "weekly limit" : "5-hour limit"
                usageText = "\(Int(usage.percent))% of \(window) used\(usage.resetAt.map { " · resets \(formatTime($0))" } ?? "")\(usage.stale ? " · last known" : "")"
                bar.doubleValue = usage.percent
            } else {
                usageText = account.status == "ready" ? "Usage appears after this account's first Claude response." : "Sign in to use this account."
                bar.isHidden = true
            }
            let usageLabel = NSTextField(labelWithString: usageText); usageLabel.textColor = .secondaryLabelColor
            let usageRow = NSStackView(views: [bar, usageLabel]); usageRow.spacing = 8
            let info = NSStackView(views: [title, usageRow]); info.orientation = .vertical; info.alignment = .leading; info.spacing = 6

            let primary = account.status == "ready"
                ? button("Check", #selector(checkAccount(_:)), id: account.id)
                : button("Sign in…", #selector(signIn(_:)), id: account.id)
            if account.status != "ready" { primary.keyEquivalent = accounts.count == 1 ? "\r" : "" }
            let more = menuButton("⋯", [("Rename…", #selector(renameAccount(_:)), account.id),
                                         ("Sign in again…", #selector(signInMenu(_:)), account.id),
                                         nil,
                                         ("Remove…", #selector(removeAccount(_:)), account.id)], tip: "More actions for \(account.name)")
            let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            let row = NSStackView(views: [info, spacer, primary, more]); row.alignment = .centerY
            let view = card(row)
            accountsList.addArrangedSubview(view); fullWidth(view)
        }
    }

    private func renderSessions() {
        sessionsList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        newSessionButton.isEnabled = !busy && !accounts.isEmpty
        newSessionButton.toolTip = accounts.isEmpty ? "Add and sign in to an account first." : nil
        if sessions.isEmpty {
            let empty = secondary(accounts.isEmpty ? "Add an account first, then start a session in a git project."
                                                   : "No sessions yet. Click New session… to start Claude in a git project.")
            sessionsList.addArrangedSubview(card(empty)); fullWidth(sessionsList.arrangedSubviews[0])
            return
        }
        for session in sessions {
            let owner = accounts.first(where: { $0.id == session.accountID })
            let title = NSTextField(labelWithString: "\(URL(fileURLWithPath: session.project).lastPathComponent) · \(session.name)")
            title.font = .systemFont(ofSize: 14, weight: .semibold); title.lineBreakMode = .byTruncatingMiddle
            let state = NSTextField(labelWithString: session.status.capitalized)
            state.textColor = session.status == "active" ? .systemGreen : .secondaryLabelColor
            let heading = NSStackView(views: [title, state]); heading.spacing = 8
            let branch = session.branch?.isEmpty == false ? session.branch! : "detached / unknown"
            let detail = NSTextField(labelWithString: "Account: \(owner?.name ?? "not started") · Branch: \(branch)")
            detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
            let info = NSStackView(views: [heading, detail]); info.orientation = .vertical; info.alignment = .leading; info.spacing = 4

            let stop = button("Stop", #selector(stop(_:)), id: session.id)
            stop.isEnabled = !busy && session.physicalID != nil && session.status == "active"
            let targets = accounts.filter { $0.id != session.accountID }
            let continueMenu = menuButton("Continue with…", targets.map { ("\($0.name) — \(statusText($0))", #selector(continueWith(_:)), "\(session.id)|\($0.id)") },
                                          tip: targets.isEmpty ? "Add a second account to continue this session with it." : "Stop Claude here and continue the conversation with another account.")
            let more = menuButton("⋯", accounts.map { ("Check readiness: \($0.name)", #selector(readiness(_:)), "\(session.id)|\($0.id)") }
                                       + [nil, ("Cancel pending launch", #selector(cancelPending(_:)), session.id),
                                          ("Recover stopped session", #selector(recoverStopped(_:)), session.id)],
                                  tip: "More actions for \(session.name)")
            let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            let row = NSStackView(views: [info, spacer, stop, continueMenu, more]); row.alignment = .centerY
            info.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let view = card(row, selected: session.id == selectedSession?.id) { [weak self] in
                self?.selectedSessionID = session.id; self?.renderedSignature = ""; self?.refresh()
            }
            view.toolTip = "Click to show this session's history and diagnostics."
            sessionsList.addArrangedSubview(view); fullWidth(view)
        }
    }

    private func formatTime(_ value: Double?) -> String {
        guard let value else { return "unknown" }; return Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .shortened)
    }

    private func setText(_ view: NSTextView, _ text: String) { if view.string != text { view.string = text } }

    private func renderDetails() {
        guard let session = selectedSession else {
            detailsTitle.stringValue = "Session details"
            setText(history, "Start a session to see its handoff history."); setText(debug, ""); return
        }
        detailsTitle.stringValue = "Details — \(URL(fileURLWithPath: session.project).lastPathComponent) · \(session.name)"
        do {
            let rows = try store.rows("SELECT e.*,a.name,f.claude_id FROM events e LEFT JOIN accounts a ON a.id=e.account_id LEFT JOIN physical_sessions f ON f.id=e.physical_id WHERE e.logical_id=? ORDER BY e.id", [session.id])
            setText(history, rows.map { "\(formatTime($0["created_at"].flatMap(Double.init)))  \($0["name"] ?? "")\n\($0["kind"] ?? "") · \($0["claude_id"] ?? "")" }.joined(separator: "\n\n"))
            let f = try session.physicalID.map { try store.physical($0) } ?? [:]
            let locks = try store.rows("SELECT owner_account,pid,locked_at FROM session_locks WHERE logical_id=?", [session.id])
            let h = try store.rows("SELECT status,error FROM handoffs WHERE logical_id=? ORDER BY created_at DESC LIMIT 1", [session.id]).first
            let readiness = try store.rows("SELECT a.name,r.name AS item,r.status FROM mcp_readiness r JOIN accounts a ON a.id=r.account_id WHERE r.project_path=?", [session.project])
            let owner = accounts.first(where: { $0.id == session.accountID })
            setText(debug, """
            Claude CLI: \(LocalClaudeCodeAdapter().executable)
            Version: \(cliVersion)
            Active account: \(owner?.name ?? "unknown")
            CLAUDE_CONFIG_DIR: \(owner?.configDir ?? "unknown")
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

            Readiness:
            \(readiness.map { "\($0["name"] ?? "") · \($0["item"] ?? ""): \($0["status"] ?? "unknown")" }.joined(separator: "\n"))
            """)
        } catch { showError(error) }
    }

    // MARK: Actions

    private var cliVersion = "Not checked"

    private func work<T: Sendable>(_ operation: @escaping @Sendable (SessionManager) throws -> T, done: @escaping (T) -> Void) {
        guard !busy else { return }
        busy = true; actionControls.forEach { $0.isEnabled = false }; addButton.isEnabled = false; newSessionButton.isEnabled = false
        message.stringValue = "Working…"
        let root = root, runner = runner
        Task {
            let result: Result<T, SessionError> = await Task.detached {
                do { return .success(try operation(SessionManager(store: SessionStore(root: root), runnerExecutable: runner))) }
                catch { return .failure((error as? SessionError) ?? .launchFailed) }
            }.value
            busy = false; renderedSignature = ""
            switch result {
            case .success(let value): done(value)
            case .failure(let error): showError(error)
            }
            refresh()
        }
    }
    private func showError(_ error: Error) { message.stringValue = (error as? SessionError)?.rawValue ?? SessionError.storage.rawValue }

    private func account(_ id: String?) -> Account? { accounts.first(where: { $0.id == id }) }
    private func ids(_ sender: Any) -> (String, String)? {
        let parts = ((sender as? NSMenuItem)?.representedObject as? String)?.split(separator: "|").map(String.init) ?? []
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    // Regression hooks: a scripted name instead of a modal prompt, and a recorder instead of Terminal.
    var promptName: ((String) -> String?)?
    var openFile: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    private func askName(title: String, info: String, value: String, confirm: String) -> String? {
        if let promptName { return promptName(title) }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = info
        let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: confirm); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    @objc private func addAccount() {
        guard let name = askName(title: "Add Claude account",
                                 info: "Give it a name you'll recognize, e.g. Personal or Work. Use a different Claude subscription for each account. Terminal opens next so you can sign in.",
                                 value: accounts.isEmpty ? "Personal" : "Work", confirm: "Add & sign in") else { return }
        do {
            let account = try store.addAccount(name: name)
            renderedSignature = ""; refresh()
            openLogin(account)
        } catch { showError(error) }
    }

    private func openLogin(_ account: Account) {
        do {
            let path = try SessionManager(store: store, runnerExecutable: runner).loginCommand(account)
            if openFile(path) {
                message.stringValue = "Terminal opened — finish signing in to \(account.name) there. This window updates when sign-in completes."
            } else { message.stringValue = "Terminal could not open. Try Sign in… again." }
        } catch { showError(error) }
    }

    @objc private func signIn(_ sender: NSButton) { if let a = account(sender.identifier?.rawValue) { openLogin(a) } }
    @objc private func signInMenu(_ sender: NSMenuItem) { if let a = account(sender.representedObject as? String) { openLogin(a) } }

    @objc private func checkAccount(_ sender: NSButton) {
        guard let target = account(sender.identifier?.rawValue) else { return }
        work { manager -> (String, Bool) in
            let version = try manager.adapter.getVersion()
            return (version, try manager.adapter.checkAuthentication(target, store: manager.store))
        } done: { [weak self] version, ok in
            self?.cliVersion = version
            self?.message.stringValue = ok ? "\(target.name) is signed in and ready." : "\(target.name) is signed out. Use Sign in… to connect it again."
        }
    }

    @objc private func renameAccount(_ sender: NSMenuItem) {
        guard let target = account(sender.representedObject as? String),
              let name = askName(title: "Rename \(target.name)", info: "Only the name shown in AI Island changes.", value: target.name, confirm: "Rename") else { return }
        do { try store.renameAccount(target.id, name: name); renderedSignature = ""; refresh(); message.stringValue = "Account renamed." }
        catch { showError(error) }
    }

    @objc private func removeAccount(_ sender: NSMenuItem) {
        guard let target = account(sender.representedObject as? String) else { return }
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "Remove \(target.name)?"
        alert.informativeText = "AI Island signs this account out of Claude Code and moves its private configuration folder to the Trash. Accounts that sessions have used can't be removed."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        work { manager in try manager.removeAccount(target.id) } done: { [weak self] in
            self?.message.stringValue = "\(target.name) removed."
        }
    }

    @objc private func newSession() {
        let alert = NSAlert(); alert.messageText = "New session"
        alert.informativeText = "Starts Claude in Terminal for a local git project, using the account you choose."
        let project = NSTextField(string: lastProject); project.placeholderString = "Local git project folder"
        let choose = NSButton(title: "Choose…", target: nil, action: nil); choose.bezelStyle = .rounded
        let chooser = ProjectChooser(field: project); choose.target = chooser; choose.action = #selector(ProjectChooser.choose)
        let name = NSTextField(string: ""); name.placeholderString = "Session name, e.g. Auth refactoring"
        let picker = NSPopUpButton()
        for a in accounts.sorted(by: { ($0.status == "ready" ? 0 : 1) < ($1.status == "ready" ? 0 : 1) }) {
            picker.addItem(withTitle: "\(a.name) — \(statusText(a))"); picker.lastItem?.representedObject = a.id
        }
        func row(_ label: String, _ views: [NSView]) -> NSStackView {
            let title = NSTextField(labelWithString: label); title.alignment = .right
            title.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let r = NSStackView(views: [title] + views); r.alignment = .centerY; return r
        }
        let form = NSStackView(views: [row("Project", [project, choose]), row("Name", [name]), row("Account", [picker])])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 8
        form.frame = NSRect(x: 0, y: 0, width: 420, height: 96)
        project.widthAnchor.constraint(equalToConstant: 260).isActive = true
        name.widthAnchor.constraint(equalToConstant: 344).isActive = true
        alert.accessoryView = form; alert.addButton(withTitle: "Start"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = lastProject.isEmpty ? project : name
        let response = withExtendedLifetime(chooser) { alert.runModal() }
        guard response == .alertFirstButtonReturn, let accountID = picker.selectedItem?.representedObject as? String else { return }
        let path = project.stringValue.trimmingCharacters(in: .whitespaces)
        let title = name.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? "New session" : name.stringValue
        lastProject = path
        work { try $0.createSession(name: title, project: path, account: accountID) } done: { [weak self] in self?.openSession($0) }
    }

    private func session(_ id: String?) -> ManagedSession? { sessions.first(where: { $0.id == id }) }

    @objc private func stop(_ sender: NSButton) {
        guard let id = session(sender.identifier?.rawValue)?.physicalID else { return }
        work { manager in try manager.adapter.stopProcess(id, store: manager.store) } done: { [weak self] in
            self?.message.stringValue = "Claude stopped. Session preserved."
        }
    }

    @objc private func continueWith(_ sender: NSMenuItem) {
        guard let (sid, aid) = ids(sender), let s = session(sid), let a = account(aid) else { return }
        handoff(s, to: a)
    }

    private func handoff(_ session: ManagedSession, to account: Account) {
        selectedSessionID = session.id
        let alert = NSAlert(); alert.messageText = "Continue \(session.name) with \(account.name)?"
        alert.informativeText = "Claude will stop, save a transcript snapshot, and fork the conversation using this account. Git files remain in the current working tree."
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        work { try $0.continueSession(logical: session.id, account: account.id) } done: { [weak self] in self?.openSession($0) }
    }

    @objc private func readiness(_ sender: NSMenuItem) {
        guard let (sid, aid) = ids(sender), let s = session(sid), let a = account(aid) else { return }
        selectedSessionID = sid
        work { manager in try manager.adapter.readiness(a, project: s.project, store: manager.store).map { "\($0.name): \($0.status)" }.joined(separator: " · ") } done: { [weak self] in
            self?.message.stringValue = "\(a.name): " + $0
        }
    }

    @objc private func cancelPending(_ sender: NSMenuItem) {
        guard let s = session(sender.representedObject as? String) else { return }
        work { manager -> String in
            let locks = try manager.store.rows("SELECT physical_id FROM session_locks WHERE logical_id=?", [s.id])
            guard let id = locks.first?["physical_id"] else { return "No pending launch." }
            try manager.cancelLaunch(id); return "Pending launch cancelled. You can retry Continue."
        } done: { [weak self] in self?.message.stringValue = $0 }
    }

    @objc private func recoverStopped(_ sender: NSMenuItem) {
        guard let id = session(sender.representedObject as? String)?.physicalID else { return }
        work { manager in try manager.recoverStoppedSession(id) } done: { [weak self] in
            self?.message.stringValue = "Stopped session recovered. You can continue."
        }
    }

    func continueSuggestedAccount() {
        guard let session = sessions.first(where: { $0.status == "active" }),
              let target = accounts.first(where: { $0.id != session.accountID && $0.status == "ready" }) else { return }
        handoff(session, to: target)
    }

    private func openSession(_ path: String) {
        if NSWorkspace.shared.open(URL(fileURLWithPath: path)) { message.stringValue = "Terminal opened. Waiting for Claude SessionStart…" }
        else {
            let id = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            try? SessionManager(store: store).cancelLaunch(id); message.stringValue = "Terminal could not open. Launch cancelled."
        }
    }

    // MARK: Island

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
    /// Every account with its display status and current 5h/7d windows, for the island.
    private(set) var usageRows: [(account: Account, status: String, windows: [UsageSnapshot])] = []
}

/// Target for the project "Choose…" button inside the modal New session alert.
@MainActor
private final class ProjectChooser: NSObject {
    let field: NSTextField
    init(field: NSTextField) { self.field = field }
    @objc func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { field.stringValue = url.path }
    }
}
