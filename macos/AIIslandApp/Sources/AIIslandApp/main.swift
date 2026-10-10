import AppKit
import ClaudeSessions

private struct CodexUsageWindow: Decodable, Sendable {
    let usedPercent: Int
    let resetsAt: TimeInterval?
}

private struct CodexUsageSnapshot: Decodable, Sendable {
    let primary: CodexUsageWindow?
    let secondary: CodexUsageWindow?
}

private struct CodexRateLimitResult: Decodable, Sendable {
    let rateLimits: CodexUsageSnapshot?
}

private struct CodexRateLimitResponse: Decodable, Sendable {
    let id: Int?
    let result: CodexRateLimitResult?
}

private enum CodexUsageReader {
    static var executable: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.codex/packages/app-server-daemon/current/bin/codex", "/opt/homebrew/bin/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func read(completion: @escaping @Sendable (CodexUsageSnapshot?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let executable else {
                completion(nil)
                return
            }
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["app-server", "--stdio"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = Pipe()

            let initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"AI Island\",\"version\":\"0.1.0\"},\"capabilities\":{}}}\n"
            let initializedAndRead = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{\"excludeResetCreditDetails\":true}}\n"
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(initialize.utf8))
                // Wait for the app-server's initialize response before the
                // initialized notification. Sending it earlier is ignored by
                // some Codex versions.
                Thread.sleep(forTimeInterval: 1.0)
                input.fileHandleForWriting.write(Data(initializedAndRead.utf8))
                // The app-server keeps its stdio session open after it has
                // answered the read. Keep stdin open until it replies: this
                // version of the server drops a rate-limit read when EOF
                // follows immediately after the notification.
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                    try? input.fileHandleForWriting.close()
                    if process.isRunning { process.terminate() }
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let decoder = JSONDecoder()
                let snapshot = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n")
                    .compactMap { try? decoder.decode(CodexRateLimitResponse.self, from: Data($0.utf8)) }
                    .first(where: { $0.id == 2 })?.result?.rateLimits
                completion(snapshot)
            } catch {
                completion(nil)
            }
        }
    }
}

private struct ClaudeAuthStatus: Decodable, Sendable {
    let loggedIn: Bool
}

private enum ClaudeAuthReader {
    static var executable: String? {
        ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func read(completion: @escaping @Sendable (Bool?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let executable else {
                completion(nil)
                return
            }
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["auth", "status"]
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                completion(try? JSONDecoder().decode(ClaudeAuthStatus.self, from: data).loggedIn)
            } catch {
                completion(nil)
            }
        }
    }
}

private final class UsageRingView: NSView {
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }
    var accent = NSColor.white { didSet { needsDisplay = true } }
    var isLoading = false { didSet { needsDisplay = true } }
    /// Usage could not be read: a dashed track, so it never looks like 0%.
    var isUnknown = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let diameter = min(bounds.width, bounds.height) - 4
        let circle = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let track = NSBezierPath(ovalIn: circle)
        if isUnknown {
            NSColor.white.withAlphaComponent(0.3).setStroke()
            track.setLineDash([3, 4], count: 2, phase: 0)
            track.lineWidth = 2
            track.stroke()
            return
        }
        NSColor.white.withAlphaComponent(0.14).setStroke()
        track.lineWidth = 3.5
        track.stroke()

        guard progress > 0 else {
            if isLoading {
                let dot = NSBezierPath(ovalIn: NSRect(x: circle.midX - 2.5, y: circle.maxY - 4, width: 5, height: 5))
                accent.setFill()
                dot.fill()
            }
            return
        }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: circle.midX, y: circle.midY), radius: diameter / 2,
                      startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        accent.setStroke()
        arc.lineWidth = 3.5
        arc.lineCapStyle = .round
        arc.stroke()
    }
}

/// The thin bar under an island ring. `progress == nil` means usage is unknown:
/// the bar stays empty and dim instead of pretending to show a value.
private final class CompactUsageBar: NSView {
    let progress: CGFloat?

    init(accent: NSColor, progress: CGFloat?) {
        self.progress = progress
        super.init(frame: NSRect(x: 0, y: 0, width: 38, height: 3))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 1.5
        layer?.backgroundColor = NSColor.white.withAlphaComponent(progress == nil ? 0.06 : 0.14).cgColor
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 3),
        ])
        guard let progress, progress > 0 else { return }
        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 1.5
        fill.layer?.backgroundColor = accent.cgColor
        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fill)
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            fill.widthAnchor.constraint(equalTo: widthAnchor, multiplier: min(progress, 1)),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class NotchContentView: NSView {
    var onPointerEnter: (() -> Void)?
    var onPointerExit: (() -> Void)?
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) { onPointerEnter?() }
    override func mouseExited(with event: NSEvent) { onPointerExit?() }
}

private enum Provider: String, CaseIterable {
    case codex = "Codex"
    case claude = "Claude"

    /// Only configuration assets AI Island is allowed to manage. Runtime state,
    /// session history, local databases, caches and authentication files are
    /// deliberately excluded.
    var managedPaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .codex:
            let root = home.appendingPathComponent(".codex")
            return [
                root.appendingPathComponent("config.toml"),
                root.appendingPathComponent("rules"),
                root.appendingPathComponent("skills"),
                root.appendingPathComponent("agents"),
                root.appendingPathComponent("commands"),
            ]
        case .claude:
            let root = home.appendingPathComponent(".claude")
            return [
                root.appendingPathComponent("settings.json"),
                root.appendingPathComponent("settings.local.json"),
                root.appendingPathComponent("agents"),
                root.appendingPathComponent("skills"),
                root.appendingPathComponent("commands"),
                root.appendingPathComponent("hooks"),
                home.appendingPathComponent(".claude.json"),
            ]
        }
    }
}

private enum SettingsArea: Int, CaseIterable {
    case overview
    case codex
    case claude
    case accounts

    var title: String {
        switch self {
        case .overview: "Overview"
        case .codex: "Codex"
        case .claude: "Claude"
        case .accounts: "Accounts"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "slider.horizontal.3"
        case .codex: "circle.hexagongrid.fill"
        case .claude: "sparkle"
        case .accounts: "person.2.fill"
        }
    }

    var provider: Provider? {
        switch self {
        case .overview, .accounts: nil
        case .codex: .codex
        case .claude: .claude
        }
    }
}

private struct ConfigurationCategory {
    let title: String
    let detail: String
    let symbol: String
    let paths: [URL]
}

private final class ConfigurationCardButton: NSButton {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }
}

private struct ProviderSnapshot {
    let provider: Provider
    let paths: [URL]
    let detectedFiles: Int
    let newestChange: Date?

    var isInstalled: Bool { !paths.isEmpty }

    var stateText: String {
        guard isInstalled else { return "Not detected" }
        return "\(detectedFiles) managed file\(detectedFiles == 1 ? "" : "s")"
    }
}

private enum ConfigInventory {
    static func snapshot(for provider: Provider) -> ProviderSnapshot {
        let fileManager = FileManager.default
        let availablePaths = provider.managedPaths.filter { fileManager.fileExists(atPath: $0.path) }
        var files = 0
        var newest: Date?

        for path in availablePaths {
            if let values = try? path.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
               values.isRegularFile == true {
                files += 1
                newest = maxDate(newest, values.contentModificationDate)
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: path,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                files += 1
                newest = maxDate(newest, values.contentModificationDate)
            }
        }
        return ProviderSnapshot(provider: provider, paths: availablePaths, detectedFiles: files, newestChange: newest)
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let rhs else { return lhs }
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }
}

private final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 48, height: 48),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate {
    private let island = IslandPanel()
    private let compactContent = NotchContentView()
    private let statusPopover = NSPopover()
    private var settingsWindow: NSWindow?
    private var settingsDetailView: NSView?
    private var selectedSettingsArea: SettingsArea = .overview
    private var configurationWindow: NSWindow?
    private var configurationSplitView: NSSplitView?
    private let configurationSidebarWidthKey = "ai-island.configuration-sidebar-width.v1"
    private let regressionPreferenceSuite: String? = {
        let arguments = CommandLine.arguments
        guard arguments.contains("--settings-regression-report") else { return nil }
        if let index = arguments.firstIndex(of: "--settings-regression-preferences"), arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }
        return "local.ai-island.regression.\(UUID().uuidString)"
    }()
    private lazy var sidebarPreferences: UserDefaults? = {
        if let suite = regressionPreferenceSuite { return UserDefaults(suiteName: suite) }
        return .standard
    }()
    private var configurationTable: NSTableView?
    private var configurationFiles: [URL] = []
    private var allConfigurationFiles: [URL] = []
    private var configurationFileCount: NSTextField?
    private var configurationSearch: NSSearchField?
    private var configurationFileTitle: NSTextField?
    private var configurationFileSubtitle: NSTextField?
    private var configurationSaveButton: NSButton?
    private var configurationDeleteButton: NSButton?
    private var configurationNewFileButton: NSButton?
    private var isUpdatingConfigurationTable = false
    private var configurationEditor: NSTextView?
    private var configurationStatus: NSTextField?
    private var activeConfigurationCategory: ConfigurationCategory?
    private var activeConfigurationFile: URL?
    private var snapshots: [ProviderSnapshot] = []
    private var codexUsage: CodexUsageSnapshot?
    private var isCodexUsageLoading = false
    /// At least one Codex request has finished, so a missing snapshot means unknown, not loading.
    private var didFinishCodexUsageRequest = false
    private var usageRefreshTimer: Timer?
    private var readCodexUsage: (@escaping @Sendable (CodexUsageSnapshot?) -> Void) -> Void = CodexUsageReader.read
    private var claudeUsage: ClaudeRateLimits?
    private var readClaudeUsage: () -> ClaudeRateLimits? = { ClaudeRateLimitCache.read() }
    private var claudeAccounts: ClaudeAccountsWindow?
    private var claudeLoggedIn: Bool?
    private let positionKey = "ai-island.position.v1"
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var closeWorkItem: DispatchWorkItem?
    private var popoverPinned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()
        buildIsland()
        refreshInventory()
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--accounts-regression-report"), arguments.indices.contains(index + 1) {
            Task { @MainActor in await runAccountsRegression(report: URL(fileURLWithPath: arguments[index + 1])) }
            return
        }
        if let reportIndex = arguments.firstIndex(of: "--usage-regression-report"),
           arguments.indices.contains(reportIndex + 1) {
            let report = URL(fileURLWithPath: arguments[reportIndex + 1])
            Task { @MainActor in await runUsageRegression(report: report) }
            return
        }
        if let reportIndex = arguments.firstIndex(of: "--settings-regression-report"),
           arguments.indices.contains(reportIndex + 1) {
            let report = URL(fileURLWithPath: arguments[reportIndex + 1])
            Task { @MainActor in await runSettingsRegression(report: report) }
            return
        }
        if FileManager.default.fileExists(atPath: SessionStore.defaultRoot.path) { configureClaudeAccounts() }
        startUsageAutoRefresh()
        refreshClaudeAuth()
        island.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopoverForFocusLoss),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        installPopoverDismissMonitors()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func runAccountsRegression(report: URL) async {
        var checks: [String] = []
        func check(_ condition: Bool, _ message: String) { checks.append("\(condition ? "PASS" : "FAIL"): \(message)") }
        func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
        do {
            let root = report.deletingLastPathComponent().appendingPathComponent("accounts-ui-\(UUID().uuidString)")
            let store = try SessionStore(root: root)
            let a = try store.addAccount(name: "Claude A"), b = try store.addAccount(name: "Claude B")
            try store.execute("UPDATE accounts SET status='ready',subscription='pro'")
            let project = "fixture-project", logical = UUID().uuidString, physical = UUID().uuidString, claude = UUID().uuidString
            try store.execute("INSERT INTO projects(id,path) VALUES(?,?)", [project, "/Users/fixture/projects/academy-backend"])
            try store.execute("INSERT INTO logical_sessions(id,project_id,name,created_at,updated_at,status,active_physical_id) VALUES(?,?,?,?,?,'active',?)", [logical, project, "Auth refactoring", store.now, store.now, physical])
            try store.execute("INSERT INTO physical_sessions(id,logical_id,account_id,claude_id,started_at,status,branch,last_hook) VALUES(?,?,?,?,?,'active','feature/auth','PostToolUse')", [physical, logical, a.id, claude, store.now])
            try store.execute("INSERT INTO usage_snapshots(account_id,physical_id,percent,reset_at,checked_at,window) VALUES(?,?,'96',?,?,'five_hour')", [a.id, physical, String(Date().timeIntervalSince1970 + 3600), store.now])
            try store.event("session started", logical: logical, physical: physical, account: a.id)
            try store.event("handoff completed", logical: logical, physical: physical, account: b.id)
            claudeAccounts = try ClaudeAccountsWindow(root: root)
            claudeAccounts?.showWindow(nil); claudeAccounts?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(300))
            guard let window = claudeAccounts?.window, let content = window.contentView else { throw SessionError.storage }
            content.layoutSubtreeIfNeeded()
            var labels: [String] { allViews(content).compactMap { ($0 as? NSTextField)?.stringValue } }
            var buttons: [NSButton] { allViews(content).compactMap { $0 as? NSButton } }
            var menuItems: [String] { buttons.compactMap { ($0 as? NSPopUpButton)?.itemTitles }.flatMap { $0 } }
            check(labels.contains("Claude A") && labels.contains("Claude B"), "Each account has its own card")
            check(labels.contains { $0.contains("96%") && $0.contains("resets") }, "Usage and reset render on the account card")
            check(labels.contains { $0.contains("Auth refactoring") } && labels.contains { $0.contains("Claude A") && $0.contains("feature/auth") },
                  "Session card shows project, name, account and branch")
            check(buttons.filter { $0.title == "Check" }.count == 2 && ["Rename…", "Sign in again…", "Remove…"].allSatisfy(menuItems.contains),
                  "Each account card has its own check and management actions")
            check(buttons.contains { $0.title == "Add account" && !$0.isEnabled }, "Add account is disabled at the two-account limit")
            check(buttons.contains { $0.title == "Continue with…" } && menuItems.contains("Claude B — Ready"),
                  "Continue menu lists the other account and its state")
            let texts = allViews(content).compactMap { ($0 as? NSTextView)?.string }
            check(texts.contains { $0.contains("handoff completed") }, "History renders from SQLite events")
            check(texts.contains { $0.contains("CLAUDE_CONFIG_DIR") && $0.contains(claude) }, "Diagnostics contain session identities")
            // A lower global cache value must not override the active session's account usage.
            claudeUsage = ClaudeRateLimits(fiveHour: ClaudeRateLimitWindow(usedPercent: 12, resetsAt: nil),
                                           sevenDay: nil, capturedAt: nil, stale: true)
            rebuildNotchContent(); collapseIsland()
            check(island.frame.width == 280 && claudeAccounts?.islandSummary?.contains("Claude B auth ready") == true, "Island shows warning and standby account")
            let rings = allViews(compactContent).compactMap { $0 as? UsageRingView }
            check(rings.contains { abs($0.progress - 0.96) < 0.001 }, "Claude island ring prefers account usage over the global cache")
            let popoverView = makeStatusPopoverView()
            let popoverLabels = allViews(popoverView).compactMap { ($0 as? NSTextField)?.stringValue }
            let popoverButtons = allViews(popoverView).compactMap { $0 as? NSButton }
            check(popoverButtons.map(\.toolTip) == ["Refresh limits", "Manage AI Island", "Update Claude Code and Codex CLI"]
                  && popoverButtons.allSatisfy { $0.title.isEmpty && $0.image != nil },
                  "Popover actions are icon buttons: Refresh, Settings, Update (no Accounts)")
            var updateOpened: URL?
            openUpdateScript = { updateOpened = $0; return true }
            popoverButtons.last?.performClick(nil)
            let updateText = updateOpened.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            check(updateOpened?.pathExtension == "command" && updateText.contains("for cli in claude codex") && updateText.contains("\"$cli\" update"),
                  "Update opens a Terminal script that updates Claude Code and Codex")
            let popoverWindow = NSWindow(contentRect: popoverView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            popoverWindow.contentView = popoverView; popoverView.layoutSubtreeIfNeeded()
            if let bitmap = popoverView.bitmapImageRepForCachingDisplay(in: popoverView.bounds) {
                popoverView.cacheDisplay(in: popoverView.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: report.deletingPathExtension().appendingPathExtension("popover.png"))
            }
            check(popoverLabels.contains("Default") && popoverLabels.contains("Claude A  · NOW") && popoverLabels.contains("Claude B")
                  && popoverLabels.contains { $0.hasPrefix("Ready") } && popoverLabels.contains { $0.hasPrefix("5H · 96% USED") }
                  && popoverLabels.contains { $0.hasPrefix("5H · 12% USED") },
                  "Claude card lists Default and every account, marking the one in use")
            let orange = NSColor(calibratedRed: 1, green: 0.57, blue: 0.20, alpha: 1)
            check(rings.contains { $0.accent == .white } && rings.contains { $0.accent == orange }, "Codex is white and Claude is orange")
            try store.execute("INSERT INTO usage_snapshots(account_id,percent,checked_at,window) VALUES(?,'100',?,'five_hour')", [a.id, store.now])
            claudeAccounts?.refresh(); rebuildNotchContent(); collapseIsland()
            check(claudeAccounts?.islandSummary?.contains("Continue with Claude B") == true, "Limit reached exposes manual continuation")
            try store.execute("UPDATE accounts SET status='signed out' WHERE id=?", [b.id])
            try store.renameAccount(b.id, name: "Work")
            claudeAccounts?.refresh(); content.layoutSubtreeIfNeeded()
            check(labels.contains("Work") && labels.contains { $0.hasPrefix("Signed out") } && buttons.contains { $0.title == "Sign in…" },
                  "Renamed, signed-out account offers Sign in…")
            for size in [NSSize(width: 760, height: 780), NSSize(width: 1000, height: 850)] {
                window.setContentSize(size); content.layoutSubtreeIfNeeded()
                check(content.bounds.width >= 760 && content.bounds.height >= 780, "Accounts window lays out at \(Int(size.width))px")
            }
            if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: report.appendingPathExtension("png"))
            }
            window.close(); claudeAccounts?.showWindow(nil)
            check(window.isVisible, "Accounts window reopens safely")
            // No real Claude CLI here: the fixture account must never trigger a real logout.
            let remover = SessionManager(store: store, adapter: LocalClaudeCodeAdapter(executable: "/nonexistent/claude"))
            remover.discardDirectory = { try FileManager.default.removeItem(at: $0) }
            try remover.removeAccount(b.id)
            claudeAccounts?.refresh(); content.layoutSubtreeIfNeeded()
            check(!labels.contains("Work") && buttons.contains { $0.title == "Add account" && $0.isEnabled }, "Removing an unused account frees a slot")
            check((try? remover.removeAccount(a.id)) == nil && labels.contains("Claude A"), "An account with session history is kept")
            var opened: [URL] = []
            claudeAccounts?.promptName = { _ in "  Side  " }
            claudeAccounts?.openFile = { opened.append($0); return true }
            if let add = buttons.first(where: { $0.title == "Add account" }) { add.performClick(nil) }
            content.layoutSubtreeIfNeeded()
            let added = try store.accounts().first { $0.name == "Side" }
            let script = opened.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            check(added != nil && labels.contains("Side") && opened.count == 1 && opened[0].pathExtension == "command"
                  && script.contains(added?.id ?? "-") && script.contains("--claude-login")
                  && !buttons.contains { $0.title == "Add account" && $0.isEnabled },
                  "Add account names the account and immediately opens its sign-in")
            claudeAccounts?.window?.close()
        } catch { checks.append("FAIL: accounts regression: \((error as? SessionError)?.rawValue ?? "unexpected error")") }
        try? checks.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    // Opt-in regression uses the production timer and native views, without
    // querying an account or relying on its usage changing during the test.
    private func runUsageRegression(report: URL) async {
        island.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        var requests: [Date] = []
        readCodexUsage = { completion in
            requests.append(Date())
            let count = requests.count
            let usage: CodexUsageSnapshot? = count == 2 ? nil : CodexUsageSnapshot(
                primary: CodexUsageWindow(usedPercent: count * 10, resetsAt: nil), secondary: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { completion(usage) }
        }
        var claudeCache: ClaudeRateLimits? = ClaudeRateLimits(
            fiveHour: ClaudeRateLimitWindow(usedPercent: 55, resetsAt: Date().timeIntervalSince1970 + 3600),
            sevenDay: nil, capturedAt: Date().timeIntervalSince1970 - 3600, stale: true)
        readClaudeUsage = { claudeCache }
        func allViews(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { allViews($0) }
        }
        var checks: [String] = []
        func check(_ condition: Bool, _ message: String) {
            checks.append("\(condition ? "PASS" : "FAIL"): \(message)")
        }
        func islandCell(_ provider: Provider) -> (ring: UsageRingView, bar: CompactUsageBar)? {
            let ring = allViews(compactContent).compactMap { $0 as? UsageRingView }
                .first { $0.toolTip?.hasPrefix(provider.rawValue) == true }
            let bar = ring?.superview?.subviews.compactMap { $0 as? CompactUsageBar }.first
            return ring.flatMap { ring in bar.map { (ring, $0) } }
        }
        startUsageAutoRefresh()
        refreshCodexUsage()
        refreshCodexUsage()
        check(requests.count == 1, "Concurrent manual refreshes share the in-flight request")
        if let codex = islandCell(.codex) {
            check(codex.ring.isLoading && !codex.ring.isUnknown && codex.bar.progress == nil,
                  "Codex island shows loading, not 0%, before the first request finishes")
        } else {
            check(false, "Codex island cell is rendered")
        }
        try? await Task.sleep(for: .milliseconds(300))
        check(codexUsage?.primary?.usedPercent == 10, "Initial snapshot is loaded")
        check(!statusPopover.isShown, "Card stays closed during background refresh")
        try? await Task.sleep(for: .milliseconds(4200))
        check(requests.count == 2, "Timer polls with the card closed")
        check(codexUsage?.primary?.usedPercent == 10 && !isCodexUsageLoading,
              "Failed refresh preserves the snapshot and releases the in-flight guard")
        showStatusPopover()
        try? await Task.sleep(for: .milliseconds(300))
        check(statusPopover.isShown && codexUsage?.primary?.usedPercent == 30,
              "Opening the card still refreshes immediately")
        try? await Task.sleep(for: .milliseconds(4200))
        check(requests.count == 4 && codexUsage?.primary?.usedPercent == 40,
              "Timer updates usage while the card is open")
        let rings = allViews(compactContent).compactMap { $0 as? UsageRingView }
        check(rings.contains { abs($0.progress - 0.4) < 0.001 }, "Compact island ring updates automatically")
        let labels = statusPopover.contentViewController.map {
            allViews($0.view).compactMap { ($0 as? NSTextField)?.stringValue }
        } ?? []
        check(labels.contains { $0.contains("40%") }, "Open card displays the updated percentage")
        check(labels.contains { $0.hasPrefix("5H · 55% USED") && $0.hasSuffix("· LAST KNOWN") },
              "Claude card shows the cached 5H window marked as last known")
        check(labels.contains("7D · LIMIT UNAVAILABLE"), "Missing Claude 7D window shows LIMIT UNAVAILABLE")
        if claudeAccounts?.islandUsage == nil {
            check(rings.contains { abs($0.progress - 0.55) < 0.001 }, "Claude ring uses the cached maximum percentage")
        }
        claudeCache = nil
        isCodexUsageLoading = true  // A hung Codex request must not block the Claude update.
        refreshCodexUsage()
        isCodexUsageLoading = false
        let claudeLabels = statusPopover.contentViewController.map {
            allViews($0.view).compactMap { ($0 as? NSTextField)?.stringValue }
        } ?? []
        check(claudeLabels.contains("5H · LIMIT UNAVAILABLE") && claudeLabels.contains("7D · LIMIT UNAVAILABLE"),
              "Claude card falls back to LIMIT UNAVAILABLE without waiting for Codex")
        rebuildNotchContent()
        if claudeAccounts?.islandUsage == nil, let claude = islandCell(.claude) {
            // A configured Claude without any recorded usage once rendered a full bar.
            check(claude.bar.progress == nil && claude.ring.isUnknown && !claude.ring.isLoading,
                  "Unknown Claude usage is not drawn as a full or empty bar")
            check(claude.ring.toolTip?.contains("limits unknown") == true,
                  "Claude island tooltip explains why usage is unknown")
        }
        let lastCodexUsage = codexUsage
        codexUsage = nil
        rebuildNotchContent()
        if let codex = islandCell(.codex) {
            check(codex.ring.isUnknown && !codex.ring.isLoading && codex.bar.progress == nil
                  && codex.ring.toolTip?.contains("limits unknown") == true,
                  "Codex island shows unknown with a reason after a request returns no limits")
        }
        codexUsage = CodexUsageSnapshot(primary: CodexUsageWindow(usedPercent: 0, resetsAt: nil), secondary: nil)
        rebuildNotchContent()
        if let codex = islandCell(.codex) {
            check(!codex.ring.isUnknown && codex.ring.progress == 0 && codex.bar.progress == 0,
                  "Known 0% Codex usage stays distinct from unknown")
        }
        codexUsage = lastCodexUsage
        if requests.count == 4 {
            let intervals = [requests[1].timeIntervalSince(requests[0]), requests[3].timeIntervalSince(requests[1])]
            check(intervals.allSatisfy { (3...5).contains($0) }, "Automatic request intervals are between 3 and 5 seconds")
        }
        usageRefreshTimer?.invalidate()
        statusPopover.performClose(nil)
        try? checks.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    // Opt-in native regression: exercise the same NSButton actions and window
    // close callbacks as the UI, including reopening an editor after closing it.
    private func runSettingsRegression(report: URL) async {
        struct RegressionFailure: Error { let message: String }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw RegressionFailure(message: message) }
        }
        var checks: [String] = []
        var didResizeSidebar = false
        do {
            try require(regressionPreferenceSuite?.hasPrefix("local.ai-island.regression.") == true && sidebarPreferences != nil,
                        "Regression must use its own isolated preferences")
            for cycle in 1...3 {
                openSettings()
                try require(settingsWindow?.isVisible == true, "Settings did not reopen")
                try await Task.sleep(for: .milliseconds(50))
                for provider in Provider.allCases {
                    selectedSettingsArea = .overview
                    refreshSettingsPage()
                    let overview = settingsDetailView?.subviews.first as? NSStackView
                    let providerButton = overview?.arrangedSubviews.compactMap { $0 as? NSButton }
                        .first { $0.identifier?.rawValue == provider.rawValue }
                    try require(providerButton != nil, "Missing provider button")
                    providerButton?.performClick(nil)
                    let page = settingsDetailView?.subviews.first as? NSStackView
                    let buttons = page?.arrangedSubviews.compactMap { $0 as? NSButton } ?? []
                    try require(buttons.count == configurationCategories(for: provider).count, "Missing category buttons")
                    guard let settingsSplit = settingsWindow?.contentView as? NSSplitView else {
                        throw RegressionFailure(message: "Missing Settings split view")
                    }
                    for target in [180.0, 300.0, 218.0] {
                        settingsSplit.setPosition(target, ofDividerAt: 0)
                        settingsSplit.layoutSubtreeIfNeeded()
                        try require(abs(settingsSplit.subviews[0].frame.width - target) <= 1,
                                    "\(provider.rawValue) Settings sidebar did not resize to \(target)px")
                    }
                    checks.append("PASS settings sidebar: \(provider.rawValue) page resizes 180/300/218px")
                    if let page {
                        page.layoutSubtreeIfNeeded()
                        for card in buttons {
                            try require(abs(card.frame.minX - page.edgeInsets.left) <= 1
                                        && abs(page.bounds.width - card.frame.maxX - page.edgeInsets.right) <= 1,
                                        "\(provider.rawValue) category cards touch the page edges")
                        }
                        checks.append("PASS settings cards: \(provider.rawValue) cards keep \(page.edgeInsets.left)px side margins")
                    }
                    for button in buttons {
                        button.performClick(nil)
                        try require(configurationWindow?.isVisible == true, "Editor did not reopen")
                        let count = managedFiles().count
                        let listed = configurationTable?.numberOfRows ?? -1
                        try require(count == listed, "File count differs from list")
                        guard let table = configurationTable, let scroll = table.enclosingScrollView else {
                            throw RegressionFailure(message: "Missing file table")
                        }
                        if didResizeSidebar {
                            try require(abs((configurationSplitView?.subviews.first?.frame.width ?? 0) - 190) <= 1,
                                        "Sidebar width changed after reopening a category")
                        } else {
                            if CommandLine.arguments.contains("--settings-regression-restore") {
                                try require(abs((configurationSplitView?.subviews.first?.frame.width ?? 0) - 190) <= 1,
                                            "New app process did not restore saved sidebar width")
                                checks.append("PASS persistence: new app process restored 190px sidebar")
                            }
                            configurationSplitView?.setPosition(190, ofDividerAt: 0)
                            didResizeSidebar = true
                            try require(abs((sidebarPreferences?.double(forKey: configurationSidebarWidthKey) ?? 0) - 190) <= 1,
                                        "Sidebar change was not saved by resize notification")
                        }
                        for size in [NSSize(width: 760, height: 460), NSSize(width: 1200, height: 760)] {
                            configurationWindow?.setContentSize(size)
                            configurationWindow?.contentView?.layoutSubtreeIfNeeded()
                            try await Task.sleep(for: .milliseconds(30))
                            table.scrollRowToVisible(0)
                            let visible = table.rows(in: scroll.documentVisibleRect).length
                            if count > 10 { try require(visible >= 5, "Long file list shows fewer than five rows") }
                            let editorFrame = configurationEditor?.enclosingScrollView?.frame ?? .zero
                            checks.append("LAYOUT: \(button.identifier?.rawValue ?? "unknown") size=\(size) sidebar=\(scroll.frame) viewport=\(scroll.documentVisibleRect) editor=\(editorFrame) visible=\(visible)")
                            try require(editorFrame.width >= 200 && editorFrame.height >= 150, "Editor collapsed on resize")
                            try require(scroll.contentSize.width >= 150, "File sidebar collapsed on resize")
                            try require(abs(scroll.frame.width - 190) <= 1, "Sidebar snapped back after manual resize")
                            if let root = configurationWindow?.contentView {
                                for action in [configurationSaveButton, configurationDeleteButton, configurationNewFileButton].compactMap({ $0 }) {
                                    try require(root.bounds.contains(action.convert(action.bounds, to: root)), "Editor action clipped on resize")
                                }
                            }
                            for index in Set([0, count / 2, count - 1]).sorted() where configurationFiles.indices.contains(index) {
                                table.scrollRowToVisible(index)
                                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                                try await Task.sleep(for: .milliseconds(20))
                                try require(table.rect(ofRow: index).intersects(scroll.documentVisibleRect), "Selected row is not visible after scrolling")
                                let file = configurationFiles[index]
                                if let data = try? Data(contentsOf: file), data.count <= 1_000_000,
                                   let expected = String(data: data, encoding: .utf8) {
                                    try require(activeConfigurationFile?.path == file.path, "Selected text file was not loaded: row \(index), \(file.lastPathComponent)")
                                    try require(configurationEditor?.string == expected, "Editor content differs from selected file")
                                    if let editor = configurationEditor, let layout = editor.layoutManager, let container = editor.textContainer {
                                        layout.ensureLayout(for: container)
                                        try require(layout.glyphRange(for: container).length == layout.numberOfGlyphs, "Editor text is clipped instead of scrollable")
                                    }
                                } else {
                                    try require(configurationEditor?.isEditable == false && activeConfigurationFile == nil,
                                                "Non-text file should display a read-only explanation")
                                }
                            }
                        }
                        if cycle == 1, let search = configurationSearch {
                            let original = configurationEditor?.string ?? ""
                            let draft = original + "\nRegression draft (not saved)"
                            configurationEditor?.string = draft
                            search.stringValue = "__ai_island_no_matching_file__"
                            NSApp.sendAction(search.action!, to: search.target, from: search)
                            try require(table.numberOfRows == 0, "Search should show no matches")
                            try require(configurationEditor?.string == draft, "Search discarded the editor draft")
                            if let first = allConfigurationFiles.first {
                                search.stringValue = first.lastPathComponent
                                NSApp.sendAction(search.action!, to: search.target, from: search)
                                try require(!configurationFiles.isEmpty && configurationFiles.allSatisfy { displayedFilePath($0).localizedCaseInsensitiveContains(search.stringValue) }, "Search returned incorrect files")
                            }
                            search.stringValue = ""
                            NSApp.sendAction(search.action!, to: search.target, from: search)
                            try require(table.numberOfRows == count, "Clearing search did not restore files")
                            try require(configurationEditor?.string == draft, "Clearing search discarded the editor draft")
                            configurationEditor?.string = original
                            checks.append("PASS search: \(button.identifier?.rawValue ?? "unknown") — filter, clear, preserve draft")
                        }
                        if cycle == 1, button.identifier?.rawValue == "Codex::Skills",
                           let index = configurationFiles.firstIndex(where: { $0.lastPathComponent == "SKILL.md" }),
                           let editor = configurationEditor, let view = configurationWindow?.contentView {
                            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                            table.scrollRowToVisible(index)
                            let original = editor.string
                            // Render a public sample instead of capturing the user's file contents.
                            editor.string = "# Image generation skill\n\nCreate and edit images from a clear brief.\n\n## Workflow\n\n1. Read the request and identify the target image.\n2. Choose the appropriate output dimensions.\n3. Generate the image and review the result.\n\n## Guidelines\n\n- Keep the composition focused and readable.\n- Preserve the requested brand colors.\n- Use transparent backgrounds for cutouts.\n- Return the final image with a short description.\n"
                            view.layoutSubtreeIfNeeded()
                            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                                view.cacheDisplay(in: view.bounds, to: bitmap)
                                if let png = bitmap.representation(using: .png, properties: [:]) {
                                    try png.write(to: report.deletingPathExtension().appendingPathExtension("png"))
                                }
                            }
                            if CommandLine.arguments.contains("--settings-regression-capture"), let windowNumber = configurationWindow?.windowNumber {
                                try String(windowNumber).write(to: report.deletingPathExtension().appendingPathExtension("window"), atomically: true, encoding: .utf8)
                                try await Task.sleep(for: .seconds(10))
                            }
                            editor.string = original
                        }
                        checks.append("PASS layout/selection: \(button.identifier?.rawValue ?? "unknown") — resize, first/middle/last file")
                        checks.append("PASS cycle \(cycle): \(button.identifier?.rawValue ?? "unknown") — \(listed) files")
                        configurationWindow?.performClose(nil)
                        try await Task.sleep(for: .milliseconds(50))
                        try require(configurationWindow?.isVisible == false, "Editor did not close")
                    }
                }
                settingsWindow?.performClose(nil)
                try await Task.sleep(for: .milliseconds(50))
                try require(settingsWindow?.isVisible == false, "Settings did not close")
                checks.append("PASS cycle \(cycle): Settings close/reopen")
            }
            openSettings()
            try require(applicationShouldTerminate(NSApp) == .terminateCancel, "Command-Q quit the app with Settings open")
            try require(settingsWindow?.isVisible == false, "Command-Q did not hide Settings")
            openSettings()
            try require(settingsWindow?.isVisible == true, "Settings did not reopen after Command-Q")
            checks.append("PASS: Command-Q hides Settings and Settings reopens")
            checks.append("PASS: all native Settings regression checks")
        } catch {
            checks.append("FAIL: \(error)")
        }
        if let suite = regressionPreferenceSuite {
            if CommandLine.arguments.contains("--settings-regression-keep-preferences") {
                sidebarPreferences?.synchronize()
            } else {
                sidebarPreferences?.removePersistentDomain(forName: suite)
            }
        }
        try? (checks.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        configurationWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let hasOpenSettings = settingsWindow?.isVisible == true || configurationWindow?.isVisible == true
        guard hasOpenSettings else { return .terminateNow }

        configurationWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageRefreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === island else { return }
        let origin = island.frame.origin
        UserDefaults.standard.set([origin.x, origin.y], forKey: positionKey)
    }

    private func buildMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu(title: "AI Island")
        appMenu.addItem(NSMenuItem(title: "Open Settings…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem(title: "Refresh configuration", action: #selector(refreshInventory), keyEquivalent: "r"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Close Settings", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Island")
        item.button?.title = " AI"
        let menu = NSMenu(title: "AI Island")
        menu.addItem(NSMenuItem(title: "Show / hide island", action: #selector(toggleIsland), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Settings…", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Claude Accounts & Sessions…", action: #selector(openClaudeAccounts), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh configuration", action: #selector(refreshInventory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        item.menu = menu
    }

    private func buildIsland() {
        island.delegate = self
        compactContent.wantsLayer = true
        compactContent.layer?.cornerRadius = 17
        // An opaque charcoal notch remains readable over bright editors,
        // wallpapers, and black terminals.
        compactContent.layer?.backgroundColor = NSColor(calibratedWhite: 0.035, alpha: 0.985).cgColor
        compactContent.layer?.borderWidth = 1
        compactContent.layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
        compactContent.layer?.shadowColor = NSColor.black.cgColor
        compactContent.layer?.shadowOpacity = 0.56
        compactContent.layer?.shadowRadius = 14
        compactContent.layer?.shadowOffset = CGSize(width: 0, height: -3)
        restoreIslandPosition()
        collapseIsland()
        let compactRecognizer = NSClickGestureRecognizer(target: self, action: #selector(toggleExpanded))
        compactContent.addGestureRecognizer(compactRecognizer)
        rebuildNotchContent()
    }

    @objc private func toggleExpanded() {
        if statusPopover.isShown {
            if popoverPinned {
                statusPopover.performClose(nil)
            } else {
                popoverPinned = true
                closeWorkItem?.cancel()
            }
        } else {
            popoverPinned = true
            showStatusPopover()
        }
    }

    private func collapseIsland() {
        island.contentView = compactContent
        resizeIsland(width: claudeAccounts?.islandSummary == nil ? 58 : 280, height: claudeLoggedIn == false && claudeAccounts?.hasAccounts != true ? 58 : 126, animate: false)
    }

    private func resizeIsland(width: CGFloat, height: CGFloat, animate: Bool) {
        var frame = island.frame
        let midpoint = frame.midX
        let top = frame.maxY
        frame.origin.x = midpoint - width / 2
        frame.origin.y = top - height
        frame.size.width = width
        frame.size.height = height
        island.setFrame(frame, display: true, animate: animate)
    }

    private func restoreIslandPosition() {
        if let stored = UserDefaults.standard.array(forKey: positionKey) as? [CGFloat], stored.count == 2 {
            let restored = NSRect(x: stored[0], y: stored[1], width: 58, height: 126)
            // A detached monitor may have held the previous position. Never
            // leave the island stranded beyond every currently visible screen.
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(restored) }) {
                island.setFrameOrigin(restored.origin)
                return
            }
        }
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        island.setFrameOrigin(NSPoint(x: visible.midX - 29, y: visible.maxY - 146))
    }

    @objc private func toggleIsland() {
        island.isVisible ? island.orderOut(nil) : island.orderFrontRegardless()
    }

    @objc private func refreshInventory() {
        snapshots = Provider.allCases.map(ConfigInventory.snapshot)
        rebuildNotchContent()
        refreshSettingsPage()
    }

    /// Claude is orange; Codex is white like ChatGPT. Island and popover share these.
    private func accentColor(for provider: Provider) -> NSColor {
        provider == .codex ? .white : NSColor(calibratedRed: 1, green: 0.57, blue: 0.20, alpha: 1)
    }

    private func rebuildNotchContent() {
        compactContent.subviews.forEach { $0.removeFromSuperview() }
        let codex = compactProviderCell(for: .codex)
        compactContent.addSubview(codex)
        guard claudeLoggedIn != false || claudeAccounts?.hasAccounts == true else {
            NSLayoutConstraint.activate([
                codex.centerXAnchor.constraint(equalTo: compactContent.centerXAnchor),
                codex.topAnchor.constraint(equalTo: compactContent.topAnchor, constant: 8),
                codex.widthAnchor.constraint(equalToConstant: 46),
                codex.heightAnchor.constraint(equalToConstant: 48),
            ])
            return
        }
        if let summary = claudeAccounts?.islandSummary {
            let claude = compactProviderCell(for: .claude)
            let text = NSTextField(wrappingLabelWithString: summary)
            text.textColor = .white; text.font = .systemFont(ofSize: 12, weight: .semibold)
            text.translatesAutoresizingMaskIntoConstraints = false
            compactContent.addSubview(claude); compactContent.addSubview(text)
            let accounts = NSButton(title: "Accounts / Continue →", target: self, action: #selector(continueClaudeAccount))
            accounts.bezelStyle = .rounded; accounts.translatesAutoresizingMaskIntoConstraints = false
            compactContent.addSubview(accounts)
            NSLayoutConstraint.activate([
                codex.leadingAnchor.constraint(equalTo: compactContent.leadingAnchor, constant: 6),
                codex.topAnchor.constraint(equalTo: compactContent.topAnchor, constant: 8),
                codex.widthAnchor.constraint(equalToConstant: 46), codex.heightAnchor.constraint(equalToConstant: 48),
                claude.leadingAnchor.constraint(equalTo: codex.leadingAnchor), claude.topAnchor.constraint(equalTo: codex.bottomAnchor, constant: 8),
                claude.widthAnchor.constraint(equalToConstant: 46), claude.heightAnchor.constraint(equalToConstant: 48),
                text.leadingAnchor.constraint(equalTo: codex.trailingAnchor, constant: 8), text.trailingAnchor.constraint(equalTo: compactContent.trailingAnchor, constant: -10),
                text.topAnchor.constraint(equalTo: compactContent.topAnchor, constant: 14),
                accounts.leadingAnchor.constraint(equalTo: text.leadingAnchor), accounts.bottomAnchor.constraint(equalTo: compactContent.bottomAnchor, constant: -18),
            ])
            return
        }
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        let claude = compactProviderCell(for: .claude)
        compactContent.addSubview(separator)
        compactContent.addSubview(claude)
        NSLayoutConstraint.activate([
            codex.centerXAnchor.constraint(equalTo: compactContent.centerXAnchor),
            codex.topAnchor.constraint(equalTo: compactContent.topAnchor, constant: 8),
            codex.widthAnchor.constraint(equalToConstant: 46),
            codex.heightAnchor.constraint(equalToConstant: 48),
            separator.centerXAnchor.constraint(equalTo: compactContent.centerXAnchor),
            separator.topAnchor.constraint(equalTo: codex.bottomAnchor, constant: 4),
            separator.widthAnchor.constraint(equalToConstant: 32),
            separator.heightAnchor.constraint(equalToConstant: 1),
            claude.centerXAnchor.constraint(equalTo: compactContent.centerXAnchor),
            claude.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            claude.widthAnchor.constraint(equalToConstant: 46),
            claude.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    /// What an island cell can honestly show for one provider.
    private enum IslandUsage: Equatable {
        case known(Double)
        case loading
        case unknown(reason: String)
    }

    private func islandUsage(for provider: Provider) -> IslandUsage {
        switch provider {
        case .codex:
            if let primary = codexUsage?.primary { return .known(Double(primary.usedPercent)) }
            if CodexUsageReader.executable == nil { return .unknown(reason: "Codex CLI not found") }
            if !didFinishCodexUsageRequest { return .loading }
            return .unknown(reason: "Codex did not report limits")
        case .claude:
            if let percent = claudeIslandPercent { return .known(percent) }
            if ClaudeAuthReader.executable == nil { return .unknown(reason: "Claude CLI not found") }
            return .unknown(reason: "no usage recorded yet — limits appear after Claude's next response")
        }
    }

    private func islandToolTip(for provider: Provider, usage: IslandUsage) -> String {
        switch usage {
        case .loading:
            return "\(provider.rawValue) · loading limits…"
        case .unknown(let reason):
            return "\(provider.rawValue) · limits unknown: \(reason)"
        case .known:
            if provider == .claude {
                return ([claudeAccounts?.islandSummary, claudeUsageSummary].compactMap { $0 }).joined(separator: "\n")
            }
            let windows = [("5H", codexUsage?.primary), ("7D", codexUsage?.secondary)]
                .compactMap { title, window in window.map { "\(title) \($0.usedPercent)%" } }
            return "Codex: " + windows.joined(separator: " · ")
        }
    }

    private func compactProviderCell(for provider: Provider) -> NSView {
        let accent = accentColor(for: provider)
        let usage = islandUsage(for: provider)
        let progress: CGFloat? = if case .known(let percent) = usage { CGFloat(percent) / 100 } else { nil }
        let ring = UsageRingView(frame: .zero)
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.accent = accent
        ring.progress = progress ?? 0
        ring.isLoading = usage == .loading
        if case .unknown = usage { ring.isUnknown = true }
        let mark = providerLogoView(for: provider, accent: accent)
        ring.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 16),
            mark.heightAnchor.constraint(equalToConstant: 16),
        ])
        let bar = CompactUsageBar(accent: accent, progress: progress)
        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        // The logo and ring cover most of the cell, so they carry the same tooltip.
        let tip = islandToolTip(for: provider, usage: usage)
        for view in [cell, ring, mark] { view.toolTip = tip }
        cell.addSubview(ring)
        cell.addSubview(bar)
        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            ring.topAnchor.constraint(equalTo: cell.topAnchor),
            ring.widthAnchor.constraint(equalToConstant: 34),
            ring.heightAnchor.constraint(equalToConstant: 34),
            bar.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            bar.topAnchor.constraint(equalTo: ring.bottomAnchor, constant: 5),
        ])
        return cell
    }

    private func providerLogoView(for provider: Provider, accent: NSColor) -> NSImageView {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = accent
        let resource = provider == .codex ? "codex" : "claude"
        if let url = Bundle.module.url(forResource: resource, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            imageView.image = image
        } else {
            // This is only a defensive fallback if a packaged resource is
            // missing; release builds always contain the vector brand mark.
            imageView.image = NSImage(systemSymbolName: "questionmark", accessibilityDescription: provider.rawValue)
        }
        imageView.toolTip = provider.rawValue
        return imageView
    }

    private func showStatusPopover() {
        closeWorkItem?.cancel()
        guard !statusPopover.isShown else { return }
        refreshInventory()
        let controller = NSViewController()
        controller.view = makeStatusPopoverView()
        statusPopover.contentViewController = controller
        statusPopover.delegate = self
        statusPopover.behavior = .applicationDefined
        statusPopover.animates = true
        statusPopover.show(relativeTo: compactContent.bounds, of: compactContent, preferredEdge: .minY)
        refreshCodexUsage()
    }

    private func startUsageAutoRefresh() {
        usageRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: 4, target: self, selector: #selector(refreshCodexUsage),
                          userInfo: nil, repeats: true)
        timer.tolerance = 0.25
        usageRefreshTimer = timer
        // Keep polling while menus or the popover are tracking mouse events.
        RunLoop.main.add(timer, forMode: .common)
        refreshCodexUsage()
    }

    @objc private func refreshCodexUsage() {
        // The Claude cache is a small local file, so it is re-read on every tick
        // and redrawn on its own, even while a Codex request is still in flight.
        let claude = readClaudeUsage()
        if claude != claudeUsage {
            claudeUsage = claude
            rebuildUsageViews()
        }
        guard !isCodexUsageLoading else { return }
        isCodexUsageLoading = true
        if codexUsage == nil { rebuildNotchContent() }
        readCodexUsage { [weak self] usage in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let usage { self.codexUsage = usage }
                self.isCodexUsageLoading = false
                self.didFinishCodexUsageRequest = true
                self.rebuildUsageViews()
            }
        }
    }

    private func rebuildUsageViews() {
        rebuildNotchContent()
        guard statusPopover.isShown else { return }
        let controller = NSViewController()
        controller.view = makeStatusPopoverView()
        statusPopover.contentViewController = controller
    }

    private func refreshClaudeAuth() {
        ClaudeAuthReader.read { [weak self] loggedIn in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.claudeLoggedIn = loggedIn
                self.rebuildNotchContent()
                self.collapseIsland()
                self.refreshSettingsPage()
                guard self.statusPopover.isShown else { return }
                let controller = NSViewController()
                controller.view = self.makeStatusPopoverView()
                self.statusPopover.contentViewController = controller
            }
        }
    }

    private func makeStatusPopoverView() -> NSView {
        let showsClaude = claudeLoggedIn != false || claudeAccounts?.hasAccounts == true
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 356, height: showsClaude ? 340 : 254))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(
            calibratedRed: 0.025,
            green: 0.035,
            blue: 0.065,
            alpha: 1
        ).cgColor
        root.layer?.cornerRadius = 20
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "LIVE AI LIMITS")
        heading.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        heading.textColor = .white
        let subtitle = NSTextField(labelWithString: popoverPinned ? "Pinned · click island to close" : "Hover to peek · click to keep open")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.62)
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(providerRow(for: .codex))
        if showsClaude {
            stack.addArrangedSubview(providerRow(for: .claude))
        }

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        for (symbol, tip, action) in [("arrow.clockwise", "Refresh limits", #selector(refreshAndReopenPopover)),
                                      ("gearshape", "Manage AI Island", #selector(openSettingsFromPopover)),
                                      ("arrow.down.circle", "Update Claude Code and Codex CLI", #selector(updateCLIs))] {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)) ?? NSImage()
            let button = NSButton(image: image, target: self, action: action)
            button.title = ""; button.imagePosition = .imageOnly
            button.bezelStyle = .rounded
            button.bezelColor = NSColor(calibratedWhite: 0.18, alpha: 1)
            button.contentTintColor = .white
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            actions.addArrangedSubview(button)
        }
        stack.addArrangedSubview(actions)

        root.addSubview(stack)
        root.setFrameSize(NSSize(width: 356, height: max(root.frame.height, stack.fittingSize.height)))
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
        ])
        return root
    }

    private func providerRow(for provider: Provider) -> NSStackView {
        let snapshot = snapshots.first(where: { $0.provider == provider }) ?? ConfigInventory.snapshot(for: provider)
        let accent = accentColor(for: provider)
        let card = NSView(frame: NSRect(x: 0, y: 0, width: 324, height: 124))
        card.wantsLayer = true
        card.layer?.cornerRadius = 13
        card.layer?.backgroundColor = accent.withAlphaComponent(0.13).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = accent.withAlphaComponent(0.42).cgColor

        let dot = NSTextField(labelWithString: snapshot.isInstalled ? "●" : "○")
        dot.textColor = accent
        dot.font = .systemFont(ofSize: 14, weight: .bold)
        let name = NSTextField(labelWithString: provider.rawValue)
        name.font = .systemFont(ofSize: 16, weight: .bold)
        name.textColor = accent
        let state = NSTextField(labelWithString: snapshot.isInstalled ? snapshot.stateText : "Not detected")
        state.font = .systemFont(ofSize: 13, weight: .semibold)
        state.textColor = NSColor.white.withAlphaComponent(0.78)
        let badge = NSTextField(labelWithString: snapshot.isInstalled ? "LOCAL" : "OFFLINE")
        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        badge.textColor = accent
        let topRow = NSStackView(views: [dot, name, NSView(), badge])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 6
        var content: [NSView] = [topRow, state]
        if provider == .codex {
            if let primary = codexUsage?.primary {
                content += usageBarViews(title: "5H", window: primary, accent: accent)
            } else {
                content += unavailableUsageBarViews(title: "5H", accent: accent)
            }
            if let secondary = codexUsage?.secondary {
                content += usageBarViews(title: "7D", window: secondary, accent: accent)
            } else {
                content += unavailableUsageBarViews(title: "7D", accent: accent)
            }
        } else {
            let sources = claudeSources, current = currentClaudeSource
            for (index, source) in sources.enumerated() {
                if index > 0 { content.append(spacer(6)) }
                let title = NSTextField(labelWithString: source.name + (source.name == current?.name ? "  · NOW" : ""))
                title.font = .systemFont(ofSize: 13, weight: .bold); title.textColor = .white
                let detail = NSTextField(labelWithString: source.detail)
                detail.font = .systemFont(ofSize: 11, weight: .medium); detail.textColor = NSColor.white.withAlphaComponent(0.62)
                let header = NSStackView(views: [title, NSView(), detail]); header.orientation = .horizontal
                header.translatesAutoresizingMaskIntoConstraints = false
                header.widthAnchor.constraint(equalToConstant: 296).isActive = true
                content.append(header)
                for (label, window) in [("5H", source.fiveHour), ("7D", source.sevenDay)] {
                    if let window {
                        content += usageBarViews(title: label, window: window, accent: accent, suffix: source.stale ? " · LAST KNOWN" : "")
                    } else {
                        content += unavailableUsageBarViews(title: label, accent: accent)
                    }
                }
            }
            if let summary = claudeAccounts?.islandSummary {
                let caption = NSTextField(labelWithString: summary)
                caption.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
                caption.textColor = accent.withAlphaComponent(0.9)
                content.append(caption)
            }
        }
        let copy = NSStackView(views: content)
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 2
        copy.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(copy)
        NSLayoutConstraint.activate([
            copy.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            copy.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            copy.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            card.heightAnchor.constraint(equalToConstant: max(124, copy.fittingSize.height + 26)),
        ])
        let row = NSStackView(views: [card])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 324).isActive = true
        return row
    }

    /// One place Claude usage comes from: plain `claude` (~/.claude) or an AI Island account.
    private struct ClaudeSource {
        let name: String
        let detail: String
        let fiveHour: CodexUsageWindow?
        let sevenDay: CodexUsageWindow?
        let updated: Double?
        let stale: Bool
        var maxPercent: Double? { [fiveHour, sevenDay].compactMap { $0.map { Double($0.usedPercent) } }.max() }
    }

    private var claudeSources: [ClaudeSource] {
        func window(_ w: ClaudeRateLimitWindow?) -> CodexUsageWindow? {
            w.map { CodexUsageWindow(usedPercent: Int($0.usedPercent.rounded()), resetsAt: $0.resetsAt) }
        }
        var sources: [ClaudeSource] = []
        if claudeLoggedIn != false || claudeUsage != nil {
            sources.append(ClaudeSource(name: "Default", detail: "claude · ~/.claude", fiveHour: window(claudeUsage?.fiveHour),
                                        sevenDay: window(claudeUsage?.sevenDay), updated: claudeUsage?.capturedAt, stale: claudeUsage?.stale ?? false))
        }
        for row in claudeAccounts?.usageRows ?? [] {
            func window(_ name: String) -> CodexUsageWindow? {
                row.windows.first { $0.window == name }.map { CodexUsageWindow(usedPercent: Int($0.percent.rounded()), resetsAt: $0.resetAt) }
            }
            let plan = ["unknown", ""].contains(row.account.subscription) ? "" : " · " + row.account.subscription.capitalized
            let updated = row.windows.map(\.checkedAt).max()
            sources.append(ClaudeSource(name: row.account.name, detail: row.status + plan, fiveHour: window("five_hour"),
                                        sevenDay: window("seven_day"), updated: updated,
                                        stale: updated.map { Date().timeIntervalSince1970 - $0 > ClaudeRateLimitCache.staleAfter } ?? false))
        }
        return sources
    }

    /// The source whose usage changed most recently (within the stale window) is the one in use now.
    private var currentClaudeSource: ClaudeSource? {
        claudeSources.filter { ($0.updated ?? 0) > Date().timeIntervalSince1970 - ClaudeRateLimitCache.staleAfter }
            .max { ($0.updated ?? 0) < ($1.updated ?? 0) }
    }

    private var claudeIslandPercent: Double? {
        currentClaudeSource?.maxPercent ?? claudeAccounts?.islandUsage ?? claudeUsage?.maxPercent
    }

    private var claudeUsageSummary: String? {
        let lines = claudeSources.map { source in
            let parts = [("5H", source.fiveHour), ("7D", source.sevenDay)].compactMap { title, w in w.map { "\(title) \($0.usedPercent)%" } }
            return "\(source.name): " + (parts.isEmpty ? source.detail : parts.joined(separator: " · ")) + (source.name == currentClaudeSource?.name ? " (now)" : "")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func usageBarViews(title: String, window: CodexUsageWindow, accent: NSColor, suffix: String = "") -> [NSView] {
        let reset = window.resetsAt.map { " · RESET \(Self.resetFormatter.string(from: Date(timeIntervalSince1970: $0)))" } ?? ""
        let caption = NSTextField(labelWithString: "\(title) · \(window.usedPercent)% USED\(reset)\(suffix)")
        caption.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        caption.textColor = accent.withAlphaComponent(0.94)
        return [caption, makeStatusBar(accent: accent, progress: CGFloat(window.usedPercent) / 100)]
    }

    private func unavailableUsageBarViews(title: String, accent: NSColor) -> [NSView] {
        let caption = NSTextField(labelWithString: "\(title) · LIMIT UNAVAILABLE")
        caption.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        caption.textColor = accent.withAlphaComponent(0.7)
        return [caption, makeStatusBar(accent: accent.withAlphaComponent(0.45), progress: 0.02)]
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func resetCountdown(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "—" }
        let remaining = max(0, Int(timestamp - Date().timeIntervalSince1970))
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        return "\(hours)h \(minutes)m"
    }

    private func makeStatusBar(accent: NSColor, progress: CGFloat) -> NSView {
        let track = NSView(frame: NSRect(x: 0, y: 0, width: 296, height: 6))
        track.wantsLayer = true
        track.layer?.cornerRadius = 3
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor
        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 3
        fill.layer?.backgroundColor = accent.cgColor
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        NSLayoutConstraint.activate([
            track.widthAnchor.constraint(equalToConstant: 296),
            track.heightAnchor.constraint(equalToConstant: 6),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: progress),
        ])
        return track
    }

    /// Runs each CLI's own updater (it knows whether it came from Homebrew, npm or a native install).
    static let updateScript = """
    #!/bin/sh
    # AI Island: update Claude Code and Codex CLI.
    for cli in claude codex; do
      echo
      if command -v "$cli" >/dev/null 2>&1; then
        echo "==> Updating $cli ($("$cli" --version 2>/dev/null | head -1))"
        "$cli" update || echo "$cli update failed."
        echo "==> $cli is now $("$cli" --version 2>/dev/null | head -1)"
      else
        echo "==> $cli not found, skipped."
      fi
    done
    echo
    echo "Done. You can close this window."
    """
    /// Regression hook: records the script instead of opening Terminal.
    var openUpdateScript: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    @objc private func updateCLIs() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-island-update.command")
        do {
            try Data(Self.updateScript.utf8).write(to: url, options: .atomic)
            chmod(url.path, 0o700)
            if !openUpdateScript(url) { presentConfigurationError("Terminal could not open the update script.") }
        } catch { presentConfigurationError("Unable to prepare the CLI update.") }
    }

    @objc private func refreshAndReopenPopover() {
        refreshInventory()
        refreshCodexUsage()
        refreshClaudeAuth()
    }

    @objc private func openSettingsFromPopover() {
        closeWorkItem?.cancel()
        popoverPinned = false
        statusPopover.performClose(nil)
        // Let AppKit finish dismissing the application-defined popover before
        // activating a separate key window. Otherwise the popover can retain
        // key focus and make Settings appear not to open.
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
    }

    @objc private func closePopoverForFocusLoss() {
        popoverPinned = false
        statusPopover.performClose(nil)
    }

    private func schedulePopoverClose() {
        guard !popoverPinned else { return }
        closeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.popoverPinned else { return }
            self.statusPopover.performClose(nil)
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
    }

    private func installPopoverDismissMonitors() {
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.closePopoverForMouseEvent(event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopoverAfterCurrentEvent()
            }
        }
    }

    private func closePopoverForMouseEvent(_ event: NSEvent) {
        guard statusPopover.isShown else { return }
        // The island has its own toggle click; it closes an open popover
        // directly and must not immediately re-open it through this monitor.
        guard event.window !== island,
              event.window !== statusPopover.contentViewController?.view.window else { return }
        closePopoverAfterCurrentEvent()
    }

    private func closePopoverAfterCurrentEvent() {
        guard statusPopover.isShown else { return }
        // Closing synchronously lets the originating click fall through to the
        // orb, which caused Refresh to close and immediately re-open the card.
        DispatchQueue.main.async { [weak self] in
            self?.popoverPinned = false
            self?.statusPopover.performClose(nil)
        }
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil { buildSettingsWindow() }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildSettingsWindow() {
        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 860, height: 600))
        split.isVertical = true
        split.dividerStyle = .thin

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 8
        sidebarStack.edgeInsets = NSEdgeInsets(top: 24, left: 16, bottom: 16, right: 16)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        let appName = NSTextField(labelWithString: "AI ISLAND")
        appName.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        appName.textColor = .secondaryLabelColor
        let appSubtitle = NSTextField(wrappingLabelWithString: "Global AI configuration")
        appSubtitle.font = .systemFont(ofSize: 18, weight: .bold)
        appSubtitle.maximumNumberOfLines = 2
        sidebarStack.addArrangedSubview(appName)
        sidebarStack.addArrangedSubview(appSubtitle)
        sidebarStack.addArrangedSubview(NSView())
        for area in SettingsArea.allCases {
            let button = settingsSidebarButton(for: area)
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor, constant: -32).isActive = true
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        sidebarStack.addArrangedSubview(spacer)
        let safety = NSTextField(wrappingLabelWithString: "Every future edit will be backed up before it is saved.")
        safety.font = .systemFont(ofSize: 11, weight: .medium)
        safety.textColor = .secondaryLabelColor
        safety.maximumNumberOfLines = 0
        sidebarStack.addArrangedSubview(safety)
        sidebar.addSubview(sidebarStack)
        NSLayoutConstraint.activate([
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])

        let detail = NSView()
        detail.wantsLayer = true
        detail.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(detail)
        // Window resizes go to the detail pane; the divider stays user-draggable.
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        NSLayoutConstraint.activate([
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
        split.setPosition(218, ofDividerAt: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Island Settings"
        // AppDelegate retains and reuses this window after the close button.
        // AppKit's extra release on close would leave our stored reference dangling.
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        window.contentView = split
        window.center()
        settingsWindow = window
        settingsDetailView = detail
        DispatchQueue.main.async { [weak self] in
            self?.refreshSettingsPage()
        }
    }

    private func settingsSidebarButton(for area: SettingsArea) -> NSButton {
        let button = NSButton(title: area.title, target: self, action: #selector(selectSettingsArea(_:)))
        button.tag = area.rawValue
        button.image = NSImage(systemSymbolName: area.symbol, accessibilityDescription: area.title)
        button.imagePosition = .imageLeading
        button.contentTintColor = area == selectedSettingsArea ? .controlAccentColor : .secondaryLabelColor
        button.font = .systemFont(ofSize: 14, weight: area == selectedSettingsArea ? .semibold : .medium)
        button.alignment = .left
        button.bezelStyle = .texturedRounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func selectSettingsArea(_ sender: NSButton) {
        guard let area = SettingsArea(rawValue: sender.tag) else { return }
        selectedSettingsArea = area
        for case let button as NSButton in sender.superview?.subviews ?? [] {
            guard let buttonArea = SettingsArea(rawValue: button.tag) else { continue }
            let selected = buttonArea == area
            button.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
            button.font = .systemFont(ofSize: 14, weight: selected ? .semibold : .medium)
        }
        DispatchQueue.main.async { [weak self] in
            self?.refreshSettingsPage()
        }
    }

    private func configureClaudeAccounts() {
        guard claudeAccounts == nil else { return }
        do {
            let controller = try ClaudeAccountsWindow()
            controller.onChange = { [weak self] in
                self?.rebuildNotchContent()
                self?.collapseIsland()
                if let self, self.statusPopover.isShown {
                    let view = NSViewController()
                    view.view = self.makeStatusPopoverView()
                    self.statusPopover.contentViewController = view
                }
            }
            claudeAccounts = controller
        } catch { presentConfigurationError("Unable to open Claude session storage.") }
    }

    @objc private func continueClaudeAccount() {
        openClaudeAccounts()
        claudeAccounts?.continueSuggestedAccount()
    }

    @objc private func openClaudeAccounts() {
        configureClaudeAccounts()
        claudeAccounts?.showWindow(nil)
        claudeAccounts?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshSettingsPage() {
        guard let detail = settingsDetailView else { return }
        detail.subviews.forEach { $0.removeFromSuperview() }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Without this the stack hugs its cards and pins the Settings divider.
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        let heading = NSTextField(labelWithString: selectedSettingsArea.title)
        heading.font = .systemFont(ofSize: 28, weight: .bold)
        let subtitle: String
        switch selectedSettingsArea {
        case .overview: subtitle = "A single control center for your local AI tooling."
        case .accounts: subtitle = "Independent Claude accounts and continuous project sessions."
        case .codex: subtitle = "Global configuration discovered in ~/.codex"
        case .claude: subtitle = claudeLoggedIn == false ? "Claude is signed out and hidden from the island." : "Global configuration discovered in ~/.claude"
        }
        let subheading = NSTextField(labelWithString: subtitle)
        subheading.font = .systemFont(ofSize: 14, weight: .medium)
        subheading.textColor = .secondaryLabelColor
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(subheading)
        if selectedSettingsArea == .accounts {
            stack.addArrangedSubview(NSButton(title: "Open Claude Accounts & Sessions…", target: self, action: #selector(openClaudeAccounts)))
        } else if let provider = selectedSettingsArea.provider {
            for category in configurationCategories(for: provider) {
                let card = configurationCard(category, provider: provider)
                stack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
            }
        } else {
            for provider in Provider.allCases {
                let snapshot = snapshots.first(where: { $0.provider == provider }) ?? ConfigInventory.snapshot(for: provider)
                let visible = provider != .claude || claudeLoggedIn != false
                let detailText = visible
                    ? "\(snapshot.stateText) · visible on island"
                    : "Signed out · hidden from island"
                let card = overviewCard(provider: provider, detail: detailText)
                stack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
            }
        }
        detail.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            stack.topAnchor.constraint(equalTo: detail.topAnchor),
        ])
    }

    private func configurationCategories(for provider: Provider) -> [ConfigurationCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch provider {
        case .codex:
            let root = home.appendingPathComponent(".codex")
            return [
                .init(title: "Settings", detail: "config.toml · global behavior and MCP configuration", symbol: "gearshape", paths: [root.appendingPathComponent("config.toml")]),
                .init(title: "Skills", detail: "Reusable task instructions", symbol: "wand.and.stars", paths: [root.appendingPathComponent("skills")]),
                .init(title: "Agents", detail: "Specialized agent definitions", symbol: "person.2", paths: [root.appendingPathComponent("agents")]),
                .init(title: "Rules", detail: "Always-on project rules", symbol: "checklist", paths: [root.appendingPathComponent("rules")]),
                .init(title: "Commands", detail: "Custom slash commands", symbol: "terminal", paths: [root.appendingPathComponent("commands")]),
                .init(title: "MCP", detail: "Servers configured in config.toml", symbol: "point.3.connected.trianglepath.dotted", paths: [root.appendingPathComponent("config.toml")]),
            ]
        case .claude:
            let root = home.appendingPathComponent(".claude")
            return [
                .init(title: "Settings", detail: "settings.json and local preferences", symbol: "gearshape", paths: [root.appendingPathComponent("settings.json"), root.appendingPathComponent("settings.local.json")]),
                .init(title: "Skills", detail: "Reusable task instructions", symbol: "wand.and.stars", paths: [root.appendingPathComponent("skills")]),
                .init(title: "Agents", detail: "Specialized agent definitions", symbol: "person.2", paths: [root.appendingPathComponent("agents")]),
                .init(title: "Commands", detail: "Custom slash commands", symbol: "terminal", paths: [root.appendingPathComponent("commands")]),
                .init(title: "Hooks", detail: "Lifecycle automations", symbol: "bolt.badge.clock", paths: [root.appendingPathComponent("hooks")]),
                .init(title: "MCP & Rules", detail: "Shared MCP definitions and CLAUDE.md rules", symbol: "point.3.connected.trianglepath.dotted", paths: [home.appendingPathComponent(".claude.json"), root.appendingPathComponent("CLAUDE.md")]),
            ]
        }
    }

    private func configurationCard(_ category: ConfigurationCategory, provider: Provider) -> NSView {
        let accent = accentColor(for: provider)
        let fileCount = managedFiles(in: category).count
        let status = fileCount > 0 ? "\(fileCount) FILE\(fileCount == 1 ? "" : "S")" : "NOT CONFIGURED"
        let card = ConfigurationCardButton(title: "", target: self, action: #selector(openConfigurationCategory(_:)))
        card.identifier = NSUserInterfaceItemIdentifier("\(provider.rawValue)::\(category.title)")
        card.toolTip = "Click to manage \(category.title)"
        card.isBordered = false
        card.alignment = .left
        card.bezelStyle = .regularSquare
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = accent.withAlphaComponent(0.08).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
        card.heightAnchor.constraint(equalToConstant: 66).isActive = true

        let icon = NSImageView(image: NSImage(systemSymbolName: category.symbol, accessibilityDescription: category.title) ?? NSImage())
        icon.contentTintColor = accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: category.title)
        title.font = .systemFont(ofSize: 15, weight: .bold)
        let detail = NSTextField(labelWithString: category.detail)
        detail.font = .systemFont(ofSize: 12, weight: .medium)
        detail.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        let badge = NSTextField(labelWithString: status.uppercased())
        badge.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        badge.textColor = accent
        badge.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(icon)
        card.addSubview(labels)
        card.addSubview(badge)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -12),
            badge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            badge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    private func overviewCard(provider: Provider, detail: String) -> NSView {
        let area: SettingsArea = provider == .codex ? .codex : .claude
        let button = ConfigurationCardButton(title: "", target: self, action: #selector(openProviderSettings(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
        button.toolTip = "Open \(provider.rawValue) settings"
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.wantsLayer = true
        button.layer?.cornerRadius = 14
        button.layer?.backgroundColor = accentColor(for: provider).withAlphaComponent(0.08).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = accentColor(for: provider).withAlphaComponent(0.28).cgColor
        button.heightAnchor.constraint(equalToConstant: 76).isActive = true
        button.setAccessibilityLabel("Open \(area.title) settings")

        let accent = accentColor(for: provider)
        let icon = NSImageView(image: NSImage(systemSymbolName: provider == .codex ? "circle.hexagongrid.fill" : "sparkle", accessibilityDescription: provider.rawValue) ?? NSImage())
        icon.contentTintColor = accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: provider.rawValue)
        title.font = .systemFont(ofSize: 16, weight: .bold)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [title, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        labels.translatesAutoresizingMaskIntoConstraints = false
        let status = NSTextField(labelWithString: provider == .claude && claudeLoggedIn == false ? "HIDDEN" : "OPEN SETTINGS  ›")
        status.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        status.textColor = accent
        status.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(icon)
        button.addSubview(labels)
        button.addSubview(status)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            labels.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: status.leadingAnchor, constant: -14),
            status.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -18),
            status.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        return button
    }

    @objc private func openProviderSettings(_ sender: NSButton) {
        guard let provider = Provider(rawValue: sender.identifier?.rawValue ?? "") else { return }
        selectedSettingsArea = provider == .codex ? .codex : .claude
        refreshSettingsPage()
    }

    @objc private func openConfigurationCategory(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        let parts = identifier.components(separatedBy: "::")
        guard parts.count == 2,
              let provider = Provider(rawValue: parts[0]),
              let category = configurationCategories(for: provider).first(where: { $0.title == parts[1] }) else { return }
        activeConfigurationCategory = category
        activeConfigurationFile = nil
        buildConfigurationWindowIfNeeded()
        configurationSearch?.stringValue = ""
        configurationWindow?.title = "\(provider.rawValue) · \(category.title)"
        refreshConfigurationFiles()
        configurationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildConfigurationWindowIfNeeded() {
        guard configurationWindow == nil else { return }
        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 920, height: 620))
        split.isVertical = true
        split.dividerStyle = .thin
        let filePanel = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 620))
        filePanel.autoresizingMask = [.height]
        let fileCount = NSTextField(labelWithString: "Files")
        fileCount.font = .systemFont(ofSize: 12, weight: .semibold)
        fileCount.textColor = .secondaryLabelColor
        fileCount.translatesAutoresizingMaskIntoConstraints = false
        configurationFileCount = fileCount
        let newFile = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New file") ?? NSImage(), target: self, action: #selector(createConfigurationFile))
        newFile.bezelStyle = .rounded
        newFile.toolTip = "Create a file in this category"
        newFile.widthAnchor.constraint(equalToConstant: 40).isActive = true
        newFile.heightAnchor.constraint(equalToConstant: 40).isActive = true
        configurationNewFileButton = newFile
        let listHeader = NSStackView(views: [fileCount, NSView(), newFile])
        listHeader.orientation = .horizontal
        listHeader.alignment = .centerY
        listHeader.translatesAutoresizingMaskIntoConstraints = false
        let search = NSSearchField()
        search.placeholderString = "Search files or skills"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(filterConfigurationFiles)
        search.translatesAutoresizingMaskIntoConstraints = false
        search.heightAnchor.constraint(equalToConstant: 30).isActive = true
        configurationSearch = search
        let listScroll = NSScrollView()
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.title = "Files"
        column.width = 250
        column.minWidth = 150
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 48
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        table.style = .sourceList
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        listScroll.documentView = table
        configurationTable = table
        filePanel.addSubview(listHeader)
        filePanel.addSubview(search)
        filePanel.addSubview(listScroll)
        NSLayoutConstraint.activate([
            listHeader.leadingAnchor.constraint(equalTo: filePanel.leadingAnchor, constant: 14),
            listHeader.trailingAnchor.constraint(equalTo: filePanel.trailingAnchor, constant: -14),
            listHeader.topAnchor.constraint(equalTo: filePanel.topAnchor, constant: 8),
            search.leadingAnchor.constraint(equalTo: filePanel.leadingAnchor, constant: 14),
            search.trailingAnchor.constraint(equalTo: filePanel.trailingAnchor, constant: -14),
            search.topAnchor.constraint(equalTo: listHeader.bottomAnchor, constant: 4),
            listScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            listScroll.leadingAnchor.constraint(equalTo: filePanel.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: filePanel.trailingAnchor),
            listScroll.bottomAnchor.constraint(equalTo: filePanel.bottomAnchor),
        ])

        let editorPanel = NSView(frame: NSRect(x: 231, y: 0, width: 689, height: 620))
        editorPanel.autoresizingMask = [.width, .height]
        let editorScroll = NSScrollView()
        editorScroll.hasVerticalScroller = true
        editorScroll.hasHorizontalScroller = false
        editorScroll.autohidesScrollers = true
        editorScroll.borderType = .noBorder
        editorScroll.wantsLayer = true
        editorScroll.layer?.cornerRadius = 10
        editorScroll.layer?.masksToBounds = true
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 520))
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textColor = .labelColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 16, height: 16)
        editor.textContainer?.containerSize = NSSize(width: 620, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.isEditable = false
        editorScroll.documentView = editor
        configurationEditor = editor

        let status = NSTextField(labelWithString: "Select a configuration file")
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        configurationStatus = status
        status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let fileTitle = NSTextField(labelWithString: "Select a file")
        fileTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        fileTitle.lineBreakMode = .byTruncatingMiddle
        fileTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let fileSubtitle = NSTextField(labelWithString: "Choose a file from the sidebar to edit")
        fileSubtitle.font = .systemFont(ofSize: 11, weight: .medium)
        fileSubtitle.textColor = .secondaryLabelColor
        fileSubtitle.lineBreakMode = .byTruncatingMiddle
        fileSubtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configurationFileTitle = fileTitle
        configurationFileSubtitle = fileSubtitle
        let heading = NSStackView(views: [fileTitle, fileSubtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        heading.setContentHuggingPriority(.defaultLow, for: .horizontal)
        heading.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        fileTitle.widthAnchor.constraint(equalTo: heading.widthAnchor).isActive = true
        fileSubtitle.widthAnchor.constraint(equalTo: heading.widthAnchor).isActive = true
        let deleteFile = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete file") ?? NSImage(), target: self, action: #selector(deleteConfigurationFile))
        deleteFile.bezelStyle = .rounded
        deleteFile.contentTintColor = .systemRed
        deleteFile.toolTip = "Delete selected file (confirmation required)"
        deleteFile.isEnabled = false
        deleteFile.widthAnchor.constraint(equalToConstant: 40).isActive = true
        deleteFile.heightAnchor.constraint(equalToConstant: 40).isActive = true
        configurationDeleteButton = deleteFile
        let save = NSButton(title: "Review & Save", target: self, action: #selector(saveConfigurationFile))
        save.bezelStyle = .rounded
        save.contentTintColor = .controlAccentColor
        save.isEnabled = false
        save.heightAnchor.constraint(equalToConstant: 40).isActive = true
        configurationSaveButton = save
        deleteFile.setContentHuggingPriority(.required, for: .horizontal)
        save.setContentHuggingPriority(.required, for: .horizontal)
        let toolbar = NSStackView(views: [heading, deleteFile, save])
        toolbar.orientation = .horizontal
        toolbar.distribution = .fill
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorPanel.addSubview(editorScroll)
        editorPanel.addSubview(toolbar)
        editorPanel.addSubview(status)
        NSLayoutConstraint.activate([
            editorScroll.leadingAnchor.constraint(equalTo: editorPanel.leadingAnchor, constant: 18),
            editorScroll.trailingAnchor.constraint(equalTo: editorPanel.trailingAnchor, constant: -18),
            editorScroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 16),
            editorScroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -12),
            toolbar.leadingAnchor.constraint(equalTo: editorPanel.leadingAnchor, constant: 18),
            toolbar.trailingAnchor.constraint(equalTo: editorPanel.trailingAnchor, constant: -18),
            toolbar.topAnchor.constraint(equalTo: editorPanel.topAnchor, constant: 18),
            status.leadingAnchor.constraint(equalTo: editorPanel.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(equalTo: editorPanel.trailingAnchor, constant: -20),
            status.bottomAnchor.constraint(equalTo: editorPanel.bottomAnchor, constant: -14),
        ])
        split.addSubview(filePanel)
        split.addSubview(editorPanel)
        split.delegate = self
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 460)
        window.contentView = split
        configurationSplitView = split
        split.layoutSubtreeIfNeeded()
        let savedWidth = sidebarPreferences?.double(forKey: configurationSidebarWidthKey) ?? 0
        split.setPosition(min(max(savedWidth > 0 ? savedWidth : 230, 180), split.bounds.width - 320), ofDividerAt: 0)
        NotificationCenter.default.addObserver(self, selector: #selector(configurationSidebarDidResize(_:)), name: NSSplitView.didResizeSubviewsNotification, object: split)
        window.center()
        configurationWindow = window
    }

    @objc private func configurationSidebarDidResize(_ notification: Notification) {
        guard let split = configurationSplitView,
              notification.object as? NSSplitView === split,
              let panel = split.subviews.first, panel.frame.width >= 180 else { return }
        sidebarPreferences?.set(panel.frame.width, forKey: configurationSidebarWidthKey)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, 180)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - 320)
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        guard splitView.subviews.count == 2 else { return }
        let sidebar = splitView.subviews[0]
        let editor = splitView.subviews[1]
        let width = min(max(sidebar.frame.width, 180), splitView.bounds.width - 320)
        sidebar.frame = NSRect(x: 0, y: 0, width: width, height: splitView.bounds.height)
        let editorX = width + splitView.dividerThickness
        editor.frame = NSRect(x: editorX, y: 0, width: splitView.bounds.width - editorX, height: splitView.bounds.height)
    }

    private func managedFiles(in category: ConfigurationCategory) -> [URL] {
        let manager = FileManager.default
        var filesByResolvedPath: [String: URL] = [:]
        var visitedDirectories = Set<String>()

        func collect(_ url: URL) {
            guard isManagedConfigurationFile(url) else { return }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { return }
            if values.isRegularFile == true {
                filesByResolvedPath[resolved.path] = url
                return
            }
            guard values.isDirectory == true, visitedDirectories.insert(resolved.path).inserted,
                  let children = try? manager.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
            for child in children {
                collect(url.appendingPathComponent(child.lastPathComponent))
            }
        }

        for path in category.paths { collect(path) }
        return filesByResolvedPath.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func managedFiles() -> [URL] {
        guard let activeConfigurationCategory else { return [] }
        return managedFiles(in: activeConfigurationCategory)
    }

    private func displayedFilePath(_ file: URL) -> String {
        guard let category = activeConfigurationCategory else { return file.lastPathComponent }
        if let directory = category.paths.first(where: { $0.pathExtension.isEmpty && file.path.hasPrefix($0.path + "/") }) {
            return String(file.path.dropFirst(directory.path.count + 1))
        }
        return file.lastPathComponent
    }

    private func refreshConfigurationFiles() {
        allConfigurationFiles = managedFiles()
        configurationNewFileButton?.isEnabled = activeConfigurationCategory?.paths.contains { $0.pathExtension.isEmpty } == true
        updateConfigurationFileList(selectFirst: true)
    }

    @objc private func filterConfigurationFiles() {
        updateConfigurationFileList(selectFirst: false)
    }

    private func updateConfigurationFileList(selectFirst: Bool) {
        guard let table = configurationTable else { return }
        let query = configurationSearch?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        configurationFiles = allConfigurationFiles.filter { query.isEmpty || displayedFilePath($0).localizedCaseInsensitiveContains(query) }
        configurationFileCount?.stringValue = query.isEmpty
            ? "\(configurationFiles.count) file\(configurationFiles.count == 1 ? "" : "s")"
            : "\(configurationFiles.count) of \(allConfigurationFiles.count) files"
        isUpdatingConfigurationTable = true
        table.deselectAll(nil)
        table.reloadData()
        let selectedIndex = configurationFiles.firstIndex { $0.path == activeConfigurationFile?.path }
            ?? (selectFirst && !configurationFiles.isEmpty ? 0 : nil)
        if let index = selectedIndex {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        }
        isUpdatingConfigurationTable = false
        if selectFirst, let index = selectedIndex {
            loadConfigurationFile(configurationFiles[index])
        } else if selectFirst {
            activeConfigurationFile = nil
            configurationEditor?.string = ""
            configurationEditor?.isEditable = false
            configurationFileTitle?.stringValue = "No files yet"
            configurationFileSubtitle?.stringValue = "Create a file to configure this category"
            configurationStatus?.stringValue = "No configuration file selected"
            configurationSaveButton?.isEnabled = false
            configurationDeleteButton?.isEnabled = false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        configurationFiles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard configurationFiles.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("configuration-file-cell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            let path = NSTextField(labelWithString: "")
            path.tag = 2
            path.font = .systemFont(ofSize: 11, weight: .regular)
            path.textColor = .secondaryLabelColor
            path.lineBreakMode = .byTruncatingMiddle
            path.translatesAutoresizingMaskIntoConstraints = false
            let icon = NSImageView(image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = .labelColor.withAlphaComponent(0.65)
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.imageView = icon
            cell.textField = label
            cell.addSubview(icon)
            cell.addSubview(label)
            cell.addSubview(path)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
                path.leadingAnchor.constraint(equalTo: label.leadingAnchor),
                path.trailingAnchor.constraint(equalTo: label.trailingAnchor),
                path.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3),
            ])
        }
        let file = configurationFiles[row]
        cell.textField?.stringValue = file.lastPathComponent == "SKILL.md"
            ? file.deletingLastPathComponent().lastPathComponent : file.lastPathComponent
        (cell.viewWithTag(2) as? NSTextField)?.stringValue = displayedFilePath(file)
        cell.toolTip = file.path
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingConfigurationTable,
              let table = notification.object as? NSTableView, table === configurationTable,
              configurationFiles.indices.contains(table.selectedRow) else { return }
        loadConfigurationFile(configurationFiles[table.selectedRow])
    }

    private func loadConfigurationFile(_ file: URL) {
        guard isManagedConfigurationFile(file) else { return }
        configurationFileTitle?.stringValue = file.lastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        configurationFileSubtitle?.stringValue = file.path.hasPrefix(home + "/") ? "~" + file.path.dropFirst(home.count) : file.path
        configurationFileSubtitle?.toolTip = file.path
        guard let data = try? Data(contentsOf: file), data.count <= 1_000_000,
              let content = String(data: data, encoding: .utf8) else {
            configurationEditor?.string = "This file cannot be displayed as editable UTF-8 text."
            configurationEditor?.isEditable = false
            configurationStatus?.stringValue = "Read-only · this file is not editable UTF-8 text"
            configurationSaveButton?.isEnabled = false
            configurationDeleteButton?.isEnabled = false
            activeConfigurationFile = nil
            return
        }
        activeConfigurationFile = file
        configurationEditor?.string = content
        configurationEditor?.isEditable = true
        let lines = content.components(separatedBy: "\n").count
        configurationStatus?.stringValue = "\(file.pathExtension.uppercased()) · \(lines) lines · UTF-8"
        configurationSaveButton?.isEnabled = true
        configurationDeleteButton?.isEnabled = true
    }

    @objc private func createConfigurationFile() {
        guard let category = activeConfigurationCategory,
              category.paths.contains(where: { $0.pathExtension.isEmpty }) else {
            presentConfigurationError("New files can only be created inside a managed Skills, Agents, Rules, Commands, or Hooks folder.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "New \(category.title) file"
        alert.informativeText = "Use letters, numbers, dots, underscores, or dashes. The file remains inside this configuration category."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let nameField = NSTextField(string: "new-item.md")
        nameField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = nameField
        guard alert.runModal() == .alertFirstButtonReturn,
              nameField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).range(of: "^[A-Za-z0-9._-]+$", options: String.CompareOptions.regularExpression) != nil else { return }
        let name = nameField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let root = writableConfigurationRoot(for: category)
        let file = root.appendingPathComponent(name)
        guard isManagedConfigurationFile(file), !FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try "# \(name)\n".write(to: file, atomically: true, encoding: .utf8)
            refreshConfigurationFiles()
            loadConfigurationFile(file)
        } catch {
            presentConfigurationError("Could not create the file.")
        }
    }

    @objc private func saveConfigurationFile() {
        guard let file = activeConfigurationFile,
              let editor = configurationEditor,
              isManagedConfigurationFile(file) else { return }
        let oldContent = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let newContent = editor.string
        guard oldContent != newContent else { return }
        let alert = NSAlert()
        alert.messageText = "Review changes"
        alert.informativeText = changeSummary(from: oldContent, to: newContent) + "\n\nA timestamped backup will be saved before this file is updated."
        alert.addButton(withTitle: "Save with backup")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try backupConfigurationFile(file)
            try newContent.write(to: file, atomically: true, encoding: .utf8)
            configurationStatus?.stringValue = "Saved with backup · \(file.path)"
            refreshInventory()
        } catch {
            presentConfigurationError("Could not save this file. The original was not replaced.")
        }
    }

    @objc private func deleteConfigurationFile() {
        guard let file = activeConfigurationFile, isManagedConfigurationFile(file) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(file.lastPathComponent)?"
        alert.informativeText = "A backup will be saved first. This cannot be undone from AI Island."
        alert.addButton(withTitle: "Delete with backup")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try backupConfigurationFile(file)
            try FileManager.default.removeItem(at: file)
            refreshConfigurationFiles()
            refreshInventory()
        } catch {
            presentConfigurationError("Could not delete this file.")
        }
    }

    private func writableConfigurationRoot(for category: ConfigurationCategory) -> URL {
        if let directory = category.paths.first(where: { $0.pathExtension.isEmpty }) { return directory }
        return category.paths.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func isManagedConfigurationFile(_ file: URL) -> Bool {
        let candidate = file.resolvingSymlinksInPath().standardizedFileURL.path
        return Provider.allCases.flatMap(\.managedPaths).contains { managedPath in
            let root = managedPath.resolvingSymlinksInPath().standardizedFileURL.path
            if managedPath.pathExtension.isEmpty {
                return candidate == root || candidate.hasPrefix(root + "/")
            }
            return candidate == root
        }
    }

    private func backupConfigurationFile(_ file: URL) throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = support.appendingPathComponent("AI Island/Backups/\(stamp)", isDirectory: true)
        let categoryFolder = folder.appendingPathComponent(activeConfigurationCategory?.title ?? "Other", isDirectory: true)
        let relativePath = activeConfigurationCategory?.paths.first(where: { $0.pathExtension.isEmpty && file.path.hasPrefix($0.path + "/") })
            .map { String(file.path.dropFirst($0.path.count + 1)) } ?? file.lastPathComponent
        let backup = categoryFolder.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: backup)
    }

    private func changeSummary(from old: String, to new: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false)
        let shared = zip(oldLines, newLines).filter { $0 == $1 }.count
        let removed = max(0, oldLines.count - shared)
        let added = max(0, newLines.count - shared)
        return "Diff preview: +\(added) line\(added == 1 ? "" : "s"), −\(removed) line\(removed == 1 ? "" : "s")."
    }

    private func presentConfigurationError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

if SessionManager.handleCommandLine() { exit(0) }

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
