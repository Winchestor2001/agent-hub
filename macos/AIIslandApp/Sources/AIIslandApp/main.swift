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
    // Setting a value that did not change does not redraw.
    var progress: CGFloat = 0 { didSet { if progress != oldValue { needsDisplay = true } } }
    var accent = NSColor.white { didSet { if accent != oldValue { needsDisplay = true } } }
    var isLoading = false { didSet { if isLoading != oldValue { needsDisplay = true } } }
    /// Usage could not be read: a dashed track, so it never looks like 0%.
    var isUnknown = false { didSet { if isUnknown != oldValue { needsDisplay = true } } }
    /// At or above the critical threshold: an "!" badge, so the state does not rely on color alone.
    var isCritical = false { didSet { if isCritical != oldValue { needsDisplay = true } } }
    /// At or above the warning threshold: a triangle badge (the critical "!" disc wins).
    var isWarning = false { didSet { if isWarning != oldValue { needsDisplay = true } } }
    /// Increase Contrast: stronger track and unknown dashes.
    var highContrast = false { didSet { if highContrast != oldValue { needsDisplay = true } } }
    /// Soft opacity pulse for critical usage; callers leave it off under Reduce Motion.
    var isPulsing = false {
        didSet {
            guard isPulsing != oldValue else { return }
            wantsLayer = true
            guard isPulsing else { layer?.removeAnimation(forKey: Self.pulseKey); return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.55
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(pulse, forKey: Self.pulseKey)
        }
    }
    static let pulseKey = "critical-pulse"

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
            NSColor.white.withAlphaComponent(highContrast ? 0.75 : 0.3).setStroke()
            track.setLineDash([3, 4], count: 2, phase: 0)
            track.lineWidth = 2
            track.stroke()
            return
        }
        NSColor.white.withAlphaComponent(highContrast ? 0.4 : 0.14).setStroke()
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
        let badge = NSRect(x: bounds.maxX - 12, y: bounds.maxY - 12, width: 12, height: 12)
        guard isCritical else {
            guard isWarning else { return }
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: badge.midX, y: badge.maxY))
            triangle.line(to: NSPoint(x: badge.maxX, y: badge.minY + 1))
            triangle.line(to: NSPoint(x: badge.minX, y: badge.minY + 1))
            triangle.close()
            triangle.lineJoinStyle = .round
            NSColor.systemYellow.setFill()
            triangle.fill()
            NSColor.black.setStroke()
            triangle.lineWidth = 1.5
            triangle.stroke()
            let mark = NSAttributedString(string: "!", attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .black),
                .foregroundColor: NSColor.black,
            ])
            let size = mark.size()
            mark.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.minY + 1))
            return
        }
        let disc = NSBezierPath(ovalIn: badge)
        NSColor.systemRed.setFill()
        disc.fill()
        NSColor.black.setStroke()
        disc.lineWidth = 1.5
        disc.stroke()
        let mark = NSAttributedString(string: "!", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .black),
            .foregroundColor: NSColor.white,
        ])
        let size = mark.size()
        mark.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))
    }
}

/// A usage bar: the thin 7D bar under an island ring and the popover's window
/// bars. `progress == nil` means usage is unknown: the bar stays empty and dim
/// instead of pretending to show a value. Values change in place, and setting
/// a value that did not change does not redraw.
private final class UsageBarView: NSView {
    var progress: CGFloat? { didSet { if progress != oldValue { needsDisplay = true } } }
    var accent: NSColor { didSet { if accent != oldValue { needsDisplay = true } } }
    /// Increase Contrast: a stronger track, so the empty part stays visible.
    var highContrast = false { didSet { if highContrast != oldValue { needsDisplay = true } } }
    private let trackAlpha: CGFloat

    init(width: CGFloat, height: CGFloat, accent: NSColor = .white, progress: CGFloat? = nil, trackAlpha: CGFloat = 0.14) {
        self.progress = progress
        self.accent = accent
        self.trackAlpha = trackAlpha
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let alpha = progress == nil ? 0.06 : trackAlpha
        NSColor.white.withAlphaComponent(highContrast ? min(alpha * 3, 0.45) : alpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard let progress, progress > 0 else { return }
        var fill = bounds
        fill.size.width = bounds.width * min(progress, 1)
        accent.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}

private extension NSTextField {
    /// Assigns only what changed, so an unchanged refresh does not redraw.
    func show(_ text: String, color: NSColor) {
        if stringValue != text { stringValue = text }
        if textColor != color { textColor = color }
    }
}

private extension NSView {
    func setToolTipIfChanged(_ tip: String?) {
        if toolTip != tip { toolTip = tip }
    }
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
        case .overview: tr("Overview")
        case .codex: "Codex"
        case .claude: "Claude"
        case .accounts: tr("Accounts")
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
    /// English; also the card identifier and the backup folder name.
    let title: String
    let detail: String
    let symbol: String
    let paths: [URL]
    var displayTitle: String { tr(title) }
    /// Skills folders list one row per skill, with the skill's own files under it.
    var groupsSkills: Bool { title == "Skills" }
}

private final class ConfigurationCardButton: NSButton {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }
}

/// File list that expands and collapses the selected skill with the arrow keys.
private final class ConfigurationFileTableView: NSTableView {
    /// Called with the selected row and true for → (expand), false for ← (collapse).
    /// Returns true when the row was a skill and the key was handled.
    var onDisclosureKey: ((Int, Bool) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let expand: Bool? = switch event.keyCode {
        case 124: true
        case 123: false
        default: nil
        }
        if let expand, onDisclosureKey?(selectedRow, expand) == true { return }
        super.keyDown(with: event)
    }
}

private final class ConfigurationFileCell: NSTableCellView {
    let disclosure = NSButton()
    let title = NSTextField(labelWithString: "")
    let path = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private var iconLeading: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        disclosure.isBordered = false
        disclosure.imagePosition = .imageOnly
        disclosure.contentTintColor = .secondaryLabelColor
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        path.font = .systemFont(ofSize: 11, weight: .regular)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        icon.contentTintColor = .labelColor.withAlphaComponent(0.65)
        let labels = NSStackView(views: [title, path])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        for view in [disclosure, icon, labels] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        imageView = icon
        textField = title
        iconLeading = icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
        NSLayoutConstraint.activate([
            disclosure.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            disclosure.centerYAnchor.constraint(equalTo: centerYAnchor),
            disclosure.widthAnchor.constraint(equalToConstant: 18),
            disclosure.heightAnchor.constraint(equalToConstant: 18),
            iconLeading,
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `grouped` leaves room for the disclosure chevron; `depth` 1 indents a skill's file.
    func configure(symbol: String, title: String, path: String, grouped: Bool, depth: Int) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        self.title.stringValue = title
        self.path.stringValue = path
        self.path.isHidden = path.isEmpty
        iconLeading.constant = grouped ? 30 + CGFloat(depth) * 18 : 12
    }
}

private struct ProviderSnapshot {
    let provider: Provider
    let paths: [URL]
    let detectedFiles: Int
    let newestChange: Date?

    var isInstalled: Bool { !paths.isEmpty }

    var stateText: String {
        guard isInstalled else { return tr("Not detected") }
        return detectedFiles == 1 ? tr("%@ managed file", detectedFiles) : tr("%@ managed files", detectedFiles)
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

/// The Settings sidebar: a native source list, one row per area.
@MainActor
private final class SettingsSidebarController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    var onSelect: ((SettingsArea) -> Void)?

    override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("area"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowSizeStyle = .medium
        table.identifier = NSUserInterfaceItemIdentifier("settings-sidebar")
        table.setAccessibilityLabel(tr("Settings sections"))
        table.dataSource = self
        table.delegate = self
    }

    func select(_ area: SettingsArea) {
        guard table.selectedRow != area.rawValue else { return }
        table.selectRowIndexes(IndexSet(integer: area.rawValue), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { SettingsArea.allCases.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let area = SettingsArea(rawValue: row) else { return nil }
        let cell = NSTableCellView()
        let image = NSImageView(image: NSImage(systemSymbolName: area.symbol, accessibilityDescription: nil) ?? NSImage())
        let label = NSTextField(labelWithString: area.title)
        label.lineBreakMode = .byTruncatingTail
        for view in [image, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = image
        cell.textField = label
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let area = SettingsArea(rawValue: table.selectedRow) else { return }
        onSelect?(area)
    }

    /// An area is always selected; clicking empty space below the rows keeps it.
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        proposed.isEmpty ? tableView.selectedRowIndexes : proposed
    }
}

private enum UnsavedConfigurationChoice { case save, discard, cancel }

/// Scrollable, colored unified diff for the save review alert.
@MainActor
private func makeDiffPreview(_ diff: LineDiff) -> NSScrollView {
    let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    let text = NSMutableAttributedString()
    for (index, line) in diff.unifiedText().components(separatedBy: "\n").enumerated() {
        let color: NSColor = switch line.first {
        case "+": .systemGreen
        case "-": .systemRed
        case "@", "…": .secondaryLabelColor
        default: .labelColor
        }
        let lineText = (index == 0 ? "" : "\n") + line
        text.append(NSAttributedString(string: lineText, attributes: [.font: font, .foregroundColor: color]))
    }
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .bezelBorder
    let view = NSTextView(frame: scroll.bounds)
    view.isEditable = false
    view.isRichText = false
    view.textContainerInset = NSSize(width: 6, height: 6)
    // Keep long configuration lines intact and scroll sideways instead of wrapping.
    view.isHorizontallyResizable = true
    view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.textContainer?.widthTracksTextView = false
    view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.textStorage?.setAttributedString(text)
    view.identifier = NSUserInterfaceItemIdentifier("diff-preview")
    scroll.documentView = view
    return scroll
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate, NSTextViewDelegate, NSMenuItemValidation {
    private let island = IslandPanel()
    private let compactContent = NSView()
    private let statusPopover = NSPopover()
    private var settingsWindow: NSWindow?
    private var settingsDetailView: NSView?
    private let settingsSidebar = SettingsSidebarController()
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
    private var configurationRows: [ConfigurationRow] = []
    /// The file each visible row opens, in row order.
    private var configurationFiles: [URL] { configurationRows.map(\.file) }
    private var allConfigurationFiles: [URL] = []
    /// Set while a Skills category is open; groups its files by skill.
    private var configurationSkillTree: SkillTree?
    private var expandedSkillFolders: Set<String> = []
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
    /// Text of the active file as last loaded or saved; the editor is dirty when it differs.
    private var configurationSavedContent: String?
    private var askAboutUnsavedConfiguration: (URL) -> UnsavedConfigurationChoice = { file in
        let alert = NSAlert()
        alert.messageText = tr("Save changes to %@?", file.lastPathComponent)
        alert.informativeText = tr("Your edits will be lost if you don't save them.")
        alert.addButton(withTitle: tr("Save…"))
        alert.addButton(withTitle: tr("Discard"))
        alert.addButton(withTitle: tr("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
    private var confirmConfigurationSave: (LineDiff) -> Bool = { diff in
        let alert = NSAlert()
        alert.messageText = tr("Review changes")
        alert.informativeText = tr("%@. A timestamped backup will be saved before this file is updated.", diff.summary)
        alert.accessoryView = makeDiffPreview(diff)
        alert.addButton(withTitle: tr("Save with backup"))
        alert.addButton(withTitle: tr("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
    /// Shown when the draft fails the syntax check. Returns true only when the
    /// user consciously chooses "Save Anyway" (offered when `canOverride`).
    private var presentConfigurationSyntaxProblem: (ConfigurationSyntaxError, URL, Bool) -> Bool = { error, file, canOverride in
        let format = file.pathExtension.uppercased()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = canOverride
            ? tr("%@ may not be valid %@", file.lastPathComponent, format)
            : tr("%@ is not valid %@", file.lastPathComponent, format)
        alert.informativeText = tr("Line %@, column %@: %@.", error.line, error.column, error.message)
            + (canOverride ? tr(" Saving it may break the tool that reads this file.") : tr(" The file was not saved."))
        if canOverride {
            alert.addButton(withTitle: tr("Keep Editing"))
            alert.addButton(withTitle: tr("Save Anyway"))
            return alert.runModal() == .alertSecondButtonReturn
        }
        alert.addButton(withTitle: tr("OK"))
        alert.runModal()
        return false
    }
    private var snapshots: [ProviderSnapshot] = []
    private var codexUsage: CodexUsageSnapshot?
    private var isCodexUsageLoading = false
    /// At least one Codex request has finished, so a missing snapshot means unknown, not loading.
    private var didFinishCodexUsageRequest = false
    private var usageRefreshTimer: Timer?
    /// The timer re-reads the local Claude cache on every tick; Codex runs a
    /// process, so ticks only ask it again once `codexRefreshInterval` has passed.
    private var usageTickInterval: TimeInterval = 4
    private var codexRefreshInterval: TimeInterval = 45
    private var lastCodexRequestStart: Date?
    private var readCodexUsage: (@escaping @Sendable (CodexUsageSnapshot?) -> Void) -> Void = CodexUsageReader.read
    private var claudeUsage: ClaudeRateLimits?
    private var readClaudeUsage: () -> ClaudeRateLimits? = { ClaudeRateLimitCache.read() }
    private var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var prefersIncreasedContrast: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    private var claudeAccounts: ClaudeAccountsWindow?
    private var claudeLoggedIn: Bool?
    private let positionKey = "ai-island.position.v1"
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    /// Island origin at the latest mouse-down on it. A drag moves the window
    /// before the click recognizer fires, so a moved island is not a click.
    private var islandOriginAtMouseDown: NSPoint?
    private var islandModel: IslandModel?
    private var islandCellViews: [Provider: IslandCellViews] = [:]
    private var islandSessionViews: IslandSessionViews?
    private var shownPopover: (model: PopoverModel, itemViews: [[NSView]])?

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
            var detailsExpanded = false
            let detailsPreference = ClaudeAccountsWindow.DetailsPreference(load: { detailsExpanded }, save: { detailsExpanded = $0 })
            claudeAccounts = try ClaudeAccountsWindow(root: root, detailsPreference: detailsPreference)
            claudeAccounts?.showWindow(nil); claudeAccounts?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(300))
            guard let window = claudeAccounts?.window, let content = window.contentView else { throw SessionError.storage }
            content.layoutSubtreeIfNeeded()
            var labels: [String] { allViews(content).compactMap { ($0 as? NSTextField)?.stringValue } }
            var buttons: [NSButton] { allViews(content).compactMap { $0 as? NSButton } }
            var menuItems: [String] { buttons.compactMap { ($0 as? NSPopUpButton)?.itemTitles }.flatMap { $0 } }
            check(labels.contains("Claude A") && labels.contains("Claude B"), "Each account has its own card")
            check(labels.contains { $0.contains(tr("%@% of 5-hour limit used", 96)) && $0.contains(tr(" · resets %@", "")) }, "Usage and reset render on the account card")
            check(labels.contains { $0.contains("Auth refactoring") } && labels.contains { $0.contains("Claude A") && $0.contains("feature/auth") },
                  "Session card shows project, name, account and branch")
            check(buttons.filter { $0.title == tr("Check") }.count == 2 && [tr("Rename…"), tr("Sign in again…"), tr("Remove…")].allSatisfy(menuItems.contains),
                  "Each account card has its own check and management actions")
            check(buttons.contains { $0.title == tr("Add account") && !$0.isEnabled }, "Add account is disabled at the two-account limit")
            check(buttons.contains { $0.title == tr("Continue with…") } && menuItems.contains("Claude B — \(tr("Ready"))"),
                  "Continue menu lists the other account and its state")
            func detailViews(_ root: NSView) -> (toggle: NSButton?, texts: [NSTextView]) {
                let views = allViews(root)
                return (views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "accounts-details-toggle" },
                        views.compactMap { $0 as? NSTextView })
            }
            var detailParts = detailViews(content)
            check(detailParts.toggle?.state == .off && detailParts.toggle?.bezelStyle == .disclosure
                  && detailParts.texts.count == 2 && detailParts.texts.allSatisfy { $0.isHiddenOrHasHiddenAncestor && $0.string.isEmpty }
                  && labels.contains(tr("History & diagnostics") + " — academy-backend · Auth refactoring"),
                  "History and diagnostics start collapsed under a disclosure and are not loaded")
            detailParts.toggle?.performClick(nil); content.layoutSubtreeIfNeeded()
            let texts = detailParts.texts.filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.string)
            check(texts.contains { $0.contains(tr("handoff completed")) } && detailsExpanded,
                  "Expanding shows history from SQLite events and remembers the choice")
            check(texts.contains { $0.contains("CLAUDE_CONFIG_DIR") && $0.contains(claude) }, "Diagnostics contain session identities")
            let reopened = try ClaudeAccountsWindow(root: root, detailsPreference: detailsPreference)
            if let reopenedContent = reopened.window?.contentView {
                detailParts = detailViews(reopenedContent)
                check(detailParts.toggle?.state == .on && detailParts.texts.allSatisfy { !$0.isHiddenOrHasHiddenAncestor },
                      "A new Accounts window opens with details expanded as left")
                detailParts.toggle?.performClick(nil)
                check(!detailsExpanded && detailParts.texts.allSatisfy(\.isHiddenOrHasHiddenAncestor),
                      "Collapsing hides the details and is remembered")
            } else { check(false, "A new Accounts window opens with details expanded as left") }
            reopened.window?.close()
            // Action results appear on the card they belong to, not on a shared line.
            func cardNotice(_ account: String) -> NSTextField? {
                let card = allViews(content).first { $0.identifier?.rawValue == "account-card"
                    && allViews($0).contains { ($0 as? NSTextField)?.stringValue == account } }
                return card.flatMap { card in allViews(card).compactMap { $0 as? NSTextField }.first {
                    $0.identifier?.rawValue == "card-notice" && card.bounds.contains($0.convert($0.bounds, to: card)) && $0.frame.height > 0 } }
            }
            func rename(_ account: String, to name: String) {
                claudeAccounts?.promptName = { _ in name }
                let item = buttons.compactMap { ($0 as? NSPopUpButton)?.menu?.items }.flatMap { $0 }
                    .first { $0.title == tr("Rename…") && ($0.representedObject as? String) == (account == "Claude A" ? a.id : b.id) }
                if let item, let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
                content.layoutSubtreeIfNeeded()
            }
            rename("Claude A", to: "Claude A")
            check(cardNotice("Claude A")?.stringValue == tr("Account renamed.") && cardNotice("Claude B") == nil
                  && labels.filter { $0 == tr("Account renamed.") }.count == 1,
                  "A successful action reports on its own account card")
            rename("Claude B", to: "  ")
            let errorNotice = cardNotice("Claude B")
            check(errorNotice?.stringValue == SessionError.accountName.message && errorNotice?.textColor == .systemRed
                  && errorNotice?.superview?.subviews.contains { ($0 as? NSImageView)?.image?.accessibilityDescription == tr("Error") } == true
                  && cardNotice("Claude A") == nil,
                  "An error reports on its account card with a warning icon, replacing the earlier result")
            claudeAccounts?.promptName = nil
            // A lower global cache value must not override the active session's account usage.
            claudeUsage = ClaudeRateLimits(fiveHour: ClaudeRateLimitWindow(usedPercent: 12, resetsAt: nil),
                                           sevenDay: nil, capturedAt: nil, stale: true)
            let defaultReducedMotion = prefersReducedMotion
            prefersReducedMotion = { true }
            defer { prefersReducedMotion = defaultReducedMotion }
            func islandDetails() -> (account: String?, state: String?, button: NSButton?, labels: [NSTextField]) {
                let views = allViews(compactContent)
                let labels = views.compactMap { $0 as? NSTextField }.filter { $0.identifier?.rawValue.hasPrefix("island-") == true && $0.identifier?.rawValue != "island-percent" }
                func text(_ id: String) -> String? { labels.first { $0.identifier?.rawValue == id }?.stringValue }
                let button = views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "island-continue" }
                return (text("island-account"), text("island-state"), button, labels)
            }
            updateNotchContent(); collapseIsland()
            compactContent.layoutSubtreeIfNeeded()
            check(island.frame.width == Self.expandedIslandWidth && claudeAccounts?.islandSummary?.contains(tr(" · %@ auth ready", "Claude B")) == true,
                  "Island expands to \(Int(Self.expandedIslandWidth))pt and shows warning and standby account")
            var details = islandDetails()
            check(details.account == "Claude A" && details.state == tr("%@% used", 96)
                  && details.labels.allSatisfy { $0.maximumNumberOfLines == 1 && $0.frame.height <= 16
                      && compactContent.bounds.contains($0.convert($0.bounds, to: compactContent)) },
                  "Expanded island shows account and state on single lines inside the island")
            check(details.button.map { $0.attributedTitle.string == tr("Continue with %@ →", "Claude B") && !$0.isBordered
                      && $0.action == #selector(continueClaudeAccount)
                      && compactContent.bounds.contains($0.convert($0.bounds, to: compactContent)) } == true,
                  "Near the limit with a ready account, a borderless Continue pill is offered")
            if let bitmap = compactContent.bitmapImageRepForCachingDisplay(in: compactContent.bounds) {
                compactContent.cacheDisplay(in: compactContent.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: report.deletingPathExtension().appendingPathExtension("island.png"))
            }
            // Expanding animates around the top center; Reduce Motion (above) resizes at once.
            let expandedFrame = island.frame
            resizeIsland(width: Self.collapsedIslandWidth, height: 126, animate: false)
            check(island.frame.width == Self.collapsedIslandWidth && island.frame.midX == expandedFrame.midX,
                  "Expanded content never forces the window wider than the island width")
            prefersReducedMotion = { false }
            collapseIsland()
            let startedCollapsed = island.frame.width < Self.expandedIslandWidth
            try await Task.sleep(for: .milliseconds(450))
            check(startedCollapsed && island.frame == expandedFrame,
                  "With motion allowed, the island animates to the expanded size around the same top center")
            prefersReducedMotion = { true }
            let rings = allViews(compactContent).compactMap { $0 as? UsageRingView }
            check(rings.contains { abs($0.progress - 0.96) < 0.001 }, "Claude island ring prefers account usage over the global cache")
            let popoverView = makeStatusPopoverView(currentPopoverModel).view
            let popoverLabels = allViews(popoverView).compactMap { ($0 as? NSTextField)?.stringValue }
            let popoverButtons = allViews(popoverView).compactMap { $0 as? NSButton }
            check(popoverButtons.map(\.toolTip) == [tr("Refresh limits"), tr("Manage AI Island"), tr("Update Claude Code and Codex CLI")]
                  && popoverButtons.allSatisfy { $0.title.isEmpty && $0.image != nil },
                  "Popover actions are icon buttons: Refresh, Settings, Update (no Accounts)")
            var updateOpened: URL?
            openUpdateScript = { updateOpened = $0; return true }
            popoverButtons.last?.performClick(nil)
            let updateText = updateOpened.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            check(updateOpened?.pathExtension == "command" && updateText.contains("for cli in claude codex") && updateText.contains("\"$cli\" update"),
                  "Update opens a Terminal script that updates Claude Code and Codex")
            check(updateText.contains("*/Caskroom/*/*)") && updateText.contains("brew upgrade --cask \"$cask\""),
                  "Update upgrades a Homebrew cask install with brew instead of the CLI's own updater")
            let popoverWindow = NSWindow(contentRect: popoverView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            popoverWindow.contentView = popoverView; popoverView.layoutSubtreeIfNeeded()
            if let bitmap = popoverView.bitmapImageRepForCachingDisplay(in: popoverView.bounds) {
                popoverView.cacheDisplay(in: popoverView.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: report.deletingPathExtension().appendingPathExtension("popover.png"))
            }
            check(popoverLabels.contains(tr("Default")) && popoverLabels.contains("Claude A" + tr(" · now")) && popoverLabels.contains("Claude B")
                  && popoverLabels.contains { $0.hasPrefix(tr("Ready")) } && popoverLabels.contains { $0.hasPrefix(tr("%@ · %@% used", tr("5H"), 96)) }
                  && popoverLabels.contains { $0.hasPrefix(tr("%@ · %@% used", tr("5H"), 12)) },
                  "Claude card lists Default and every account, marking the one in use")
            let orange = NSColor(calibratedRed: 1, green: 0.57, blue: 0.20, alpha: 1)
            // Provider identity lives in the logo; the ring itself is colored by limit level.
            let logoTints = rings.flatMap { $0.subviews.compactMap { ($0 as? NSImageView)?.contentTintColor } }
            check(logoTints.contains(.white) && logoTints.contains(orange), "Codex logo is white and Claude logo is orange")
            let claudeRing = rings.first { $0.toolTip?.hasPrefix("Claude") == true || $0.toolTip?.contains("Claude A") == true }
            check(claudeRing.map { $0.accent == usageColor(accent: orange, percent: Double($0.progress * 100)) } == true,
                  "Claude ring follows the limit-level color rule (\(Int((claudeRing?.progress ?? 0) * 100))%)")
            try store.execute("INSERT INTO usage_snapshots(account_id,percent,checked_at,window) VALUES(?,'100',?,'five_hour')", [a.id, store.now])
            claudeAccounts?.refresh(); updateNotchContent(); collapseIsland()
            check(claudeAccounts?.islandSummary?.contains(tr(" · Continue with %@ →", "Claude B")) == true, "Limit reached exposes manual continuation")
            details = islandDetails()
            check(details.state == tr("Limit reached") && details.button != nil, "Limit reached shows the state and the Continue pill")
            try store.execute("INSERT INTO usage_snapshots(account_id,percent,checked_at,window) VALUES(?,'40',?,'five_hour')", [a.id, store.now])
            claudeAccounts?.refresh(); updateNotchContent(); collapseIsland()
            details = islandDetails()
            check(details.state == tr("%@% used", 40) && details.button == nil && island.frame.width == Self.expandedIslandWidth,
                  "With headroom, the expanded island has no Continue pill")
            try store.execute("UPDATE accounts SET status='signed out' WHERE id=?", [b.id])
            try store.renameAccount(b.id, name: "Work")
            claudeAccounts?.refresh(); content.layoutSubtreeIfNeeded()
            check(labels.contains("Work") && labels.contains { $0.hasPrefix(tr("Signed out")) } && buttons.contains { $0.title == tr("Sign in…") },
                  "Renamed, signed-out account offers Sign in…")
            try store.execute("INSERT INTO usage_snapshots(account_id,percent,checked_at,window) VALUES(?,'97',?,'five_hour')", [a.id, store.now])
            claudeAccounts?.refresh(); updateNotchContent(); collapseIsland()
            details = islandDetails()
            check(details.state == tr("%@% used", 97) && details.button == nil,
                  "Near the limit without a ready account, no Continue pill is offered")
            for size in [NSSize(width: 760, height: 780), NSSize(width: 1000, height: 850)] {
                window.setContentSize(size); content.layoutSubtreeIfNeeded()
                check(content.bounds.width >= 760 && content.bounds.height >= 780, "Accounts window lays out at \(Int(size.width))px")
            }
            if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: report.appendingPathExtension("png"))
            }
            Self.pressCommand("w", keyCode: 13, in: window)
            let closedByShortcut = !window.isVisible
            claudeAccounts?.showWindow(nil)
            check(closedByShortcut && window.isVisible, "Command-W closes the Accounts window and it reopens safely")
            // No real Claude CLI here: the fixture account must never trigger a real logout.
            let remover = SessionManager(store: store, adapter: LocalClaudeCodeAdapter(executable: "/nonexistent/claude"))
            remover.discardDirectory = { try FileManager.default.removeItem(at: $0) }
            try remover.removeAccount(b.id)
            claudeAccounts?.refresh(); content.layoutSubtreeIfNeeded()
            check(!labels.contains("Work") && buttons.contains { $0.title == tr("Add account") && $0.isEnabled }, "Removing an unused account frees a slot")
            check((try? remover.removeAccount(a.id)) == nil && labels.contains("Claude A"), "An account with session history is kept")
            var opened: [URL] = []
            claudeAccounts?.promptName = { _ in "  Side  " }
            claudeAccounts?.openFile = { opened.append($0); return true }
            if let add = buttons.first(where: { $0.title == tr("Add account") }) { add.performClick(nil) }
            content.layoutSubtreeIfNeeded()
            let added = try store.accounts().first { $0.name == "Side" }
            let script = opened.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            check(added != nil && labels.contains("Side") && opened.count == 1 && opened[0].pathExtension == "command"
                  && script.contains(added?.id ?? "-") && script.contains("--claude-login")
                  && !buttons.contains { $0.title == tr("Add account") && $0.isEnabled },
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
        var claudeReads = 0
        readClaudeUsage = { claudeReads += 1; return claudeCache }
        func allViews(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { allViews($0) }
        }
        var checks: [String] = []
        func check(_ condition: Bool, _ message: String) {
            checks.append("\(condition ? "PASS" : "FAIL"): \(message)")
        }
        func popoverFields() -> [NSTextField] {
            statusPopover.contentViewController.map { allViews($0.view).compactMap { $0 as? NSTextField } } ?? []
        }
        func islandCell(_ provider: Provider) -> (ring: UsageRingView, bar: UsageBarView, number: NSTextField)? {
            let ring = allViews(compactContent).compactMap { $0 as? UsageRingView }
                .first { $0.toolTip?.hasPrefix(provider.rawValue) == true }
            let bar = ring?.superview?.subviews.compactMap { $0 as? UsageBarView }.first
            let number = ring?.superview?.subviews.compactMap { $0 as? NSTextField }
                .first { $0.identifier?.rawValue == "island-percent" }
            guard let ring, let bar, let number else { return nil }
            return (ring, bar, number)
        }
        /// Visual record for review, next to the report: usage.<name>.png, on black, 3×.
        func snapshot(_ view: NSView, _ name: String) {
            compactContent.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = NSImage(size: NSSize(width: view.bounds.width * 3, height: view.bounds.height * 3), flipped: false) { rect in
                NSColor.black.setFill(); rect.fill()
                bitmap.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                return true
            }
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: report.deletingPathExtension().appendingPathExtension("\(name).png"))
            }
        }
        // Short intervals keep the timer checks fast; the app uses a 4 s tick and 45 s Codex interval.
        let defaultIntervals = (tick: usageTickInterval, codex: codexRefreshInterval)
        check((30...60).contains(defaultIntervals.codex) && (4...5).contains(defaultIntervals.tick),
              "Codex is polled every 30–60 s and the Claude cache every 4–5 s")
        usageTickInterval = 0.5
        codexRefreshInterval = 1.5
        startUsageAutoRefresh()
        refreshCodexUsage()
        refreshCodexUsage()
        check(requests.count == 1, "Concurrent manual refreshes share the in-flight request")
        if let codex = islandCell(.codex) {
            check(codex.ring.isLoading && !codex.ring.isUnknown && codex.bar.progress == nil && codex.number.stringValue == "…",
                  "Codex island shows loading, not 0%, before the first request finishes")
        } else {
            check(false, "Codex island cell is rendered")
        }
        try? await Task.sleep(for: .milliseconds(300))
        check(codexUsage?.primary?.usedPercent == 10, "Initial snapshot is loaded")
        check(!statusPopover.isShown, "Card stays closed during background refresh")
        let readsBeforeTicks = claudeReads
        try? await Task.sleep(for: .milliseconds(1000))
        check(requests.count == 1 && claudeReads >= readsBeforeTicks + 2,
              "Ticks re-read the Claude cache without starting a Codex request before its interval")
        try? await Task.sleep(for: .milliseconds(1000))
        check(requests.count == 2, "Timer polls Codex after its interval with the card closed")
        check(codexUsage?.primary?.usedPercent == 10 && !isCodexUsageLoading,
              "Failed refresh preserves the snapshot and releases the in-flight guard")
        showStatusPopover()
        try? await Task.sleep(for: .milliseconds(300))
        check(statusPopover.isShown && requests.count == 3 && codexUsage?.primary?.usedPercent == 30,
              "Opening the card asks Codex immediately, before the interval")
        try? await Task.sleep(for: .milliseconds(2000))
        check(requests.count == 4 && codexUsage?.primary?.usedPercent == 40,
              "Timer updates usage while the card is open")
        let rings = allViews(compactContent).compactMap { $0 as? UsageRingView }
        check(rings.contains { abs($0.progress - 0.4) < 0.001 }, "Compact island ring updates automatically")
        let labels = statusPopover.contentViewController.map {
            allViews($0.view).compactMap { ($0 as? NSTextField)?.stringValue }
        } ?? []
        check(labels.contains { $0.contains("40%") }, "Open card displays the updated percentage")
        refreshCodexUsage()  // What the card's Refresh button does.
        try? await Task.sleep(for: .milliseconds(300))
        check(requests.count == 5, "Refresh asks Codex immediately, before the interval")
        if requests.count == 5 {
            let automatic = [requests[1].timeIntervalSince(requests[0]), requests[3].timeIntervalSince(requests[2])]
            check(automatic.allSatisfy { (1.5...2.5).contains($0) },
                  "Automatic Codex requests wait for the interval after the last request")
        }
        // Stop polling so the rendering checks below control the snapshot alone.
        usageRefreshTimer?.invalidate()
        (usageTickInterval, codexRefreshInterval) = defaultIntervals
        check(labels.contains { $0.hasPrefix(tr("%@ · %@% used", tr("5H"), 55)) && $0.hasSuffix(tr(" · last known")) },
              "Claude card shows the cached 5H window marked as last known")
        check(labels.contains(tr("%@ · not available", tr("7D"))), "Missing Claude 7D window shows not available next to the known 5H")
        if claudeAccounts?.islandUsage == nil {
            check(rings.contains { abs($0.progress - 0.55) < 0.001 }, "Claude ring shows the cached 5H window")
        }
        claudeCache = nil
        isCodexUsageLoading = true  // A hung Codex request must not block the Claude update.
        refreshCodexUsage()
        isCodexUsageLoading = false
        let claudeLabels = statusPopover.contentViewController.map {
            allViews($0.view).compactMap { ($0 as? NSTextField)?.stringValue }
        } ?? []
        check(claudeLabels.contains(tr("Limits not available yet")) && !claudeLabels.contains { $0.hasSuffix("LIMIT UNAVAILABLE") },
              "Claude card without any window shows one quiet line, without waiting for Codex")
        updateNotchContent()
        if claudeAccounts?.islandUsage == nil, let claude = islandCell(.claude) {
            // A configured Claude without any recorded usage once rendered a full bar.
            check(claude.bar.progress == nil && claude.ring.isUnknown && !claude.ring.isLoading,
                  "Unknown Claude usage is not drawn as a full or empty bar")
            check(claude.ring.toolTip?.hasPrefix(tr("%@ · limits unknown: %@", "Claude", "")) == true,
                  "Claude island tooltip explains why usage is unknown")
        }
        let lastCodexUsage = codexUsage
        codexUsage = nil
        updateNotchContent()
        if let codex = islandCell(.codex) {
            check(codex.ring.isUnknown && !codex.ring.isLoading && codex.bar.progress == nil && codex.number.stringValue == "—"
                  && codex.ring.toolTip?.hasPrefix(tr("%@ · limits unknown: %@", "Codex", "")) == true,
                  "Codex island shows unknown with a reason after a request returns no limits")
        }
        codexUsage = CodexUsageSnapshot(primary: CodexUsageWindow(usedPercent: 0, resetsAt: nil),
                                        secondary: CodexUsageWindow(usedPercent: 0, resetsAt: nil))
        updateNotchContent()
        if let codex = islandCell(.codex) {
            check(!codex.ring.isUnknown && codex.ring.progress == 0 && codex.bar.progress == 0 && codex.number.stringValue == "0%",
                  "Known 0% Codex usage stays distinct from unknown")
        }
        // Limit levels: one rule colors the island ring, its bar and the popover bar.
        let defaultReducedMotion = prefersReducedMotion
        let codexAccent = accentColor(for: .codex)
        for (percent, expected, critical) in [(50, codexAccent, false), (80, NSColor.systemYellow, false), (95, NSColor.systemRed, true)] {
            for reduceMotion in critical ? [false, true] : [false] {
                prefersReducedMotion = { reduceMotion }
                codexUsage = CodexUsageSnapshot(primary: CodexUsageWindow(usedPercent: percent, resetsAt: nil),
                                                secondary: CodexUsageWindow(usedPercent: percent, resetsAt: nil))
                updateUsageViews()
                let popoverBar = statusPopover.contentViewController.flatMap { controller -> NSView? in
                    let caption = allViews(controller.view).first { ($0 as? NSTextField)?.stringValue.hasPrefix(tr("%@ · %@% used", tr("5H"), percent)) == true }
                    guard let stack = caption?.superview as? NSStackView,
                          let index = stack.arrangedSubviews.firstIndex(where: { $0 === caption }),
                          stack.arrangedSubviews.indices.contains(index + 1) else { return nil }
                    return stack.arrangedSubviews[index + 1]
                }
                if let codex = islandCell(.codex) {
                    let pulsing = codex.ring.layer?.animation(forKey: UsageRingView.pulseKey) != nil
                    check(codex.ring.accent == expected && codex.bar.accent == expected
                          && codex.number.stringValue == "\(percent)%" && codex.number.textColor == expected
                          && (popoverBar as? UsageBarView)?.accent == expected
                          && codex.ring.isCritical == critical && codex.ring.isWarning == (percent == 80)
                          && pulsing == (critical && !reduceMotion),
                          "\(percent)% uses \(critical ? "red with an ! badge" : percent >= 70 ? "yellow with a triangle badge" : "the provider color")"
                          + " on the ring, number, island bar and popover bar\(critical ? (reduceMotion ? ", no pulse under Reduce Motion" : ", pulsing") : "")")
                    if let cell = codex.ring.superview { snapshot(cell, "\(percent)") }
                } else {
                    check(false, "Codex island cell is rendered for \(percent)%")
                }
            }
        }
        // Ring and bar carry different windows: ring + number = 5H, bar = 7D.
        prefersReducedMotion = { true }
        codexUsage = CodexUsageSnapshot(primary: CodexUsageWindow(usedPercent: 10, resetsAt: nil),
                                        secondary: CodexUsageWindow(usedPercent: 95, resetsAt: nil))
        updateUsageViews()
        if let codex = islandCell(.codex) {
            check(abs(codex.ring.progress - 0.1) < 0.001 && codex.ring.accent == codexAccent && codex.number.stringValue == "10%"
                  && codex.bar.progress.map { abs($0 - 0.95) < 0.001 } == true && codex.bar.accent == .systemRed
                  && codex.ring.isCritical,
                  "Ring and number show 5H (10%), the bar shows 7D (95%, red), and the critical 7D raises the ! badge")
            check(codex.ring.toolTip == tr("%@ · Ring: 5H %@ · Bar: 7D %@", "Codex", tr("%@% used", 10), tr("%@% used", 95)),
                  "Island tooltip names which window the ring and the bar show")
        } else {
            check(false, "Codex island cell is rendered for mixed windows")
        }
        codexUsage = CodexUsageSnapshot(primary: CodexUsageWindow(usedPercent: 100, resetsAt: nil),
                                        secondary: CodexUsageWindow(usedPercent: 72, resetsAt: nil))
        updateUsageViews()
        compactContent.layoutSubtreeIfNeeded()
        let cells = [islandCell(.codex), islandCell(.claude)].compactMap { $0 }
        check(island.frame.width == 58 && !cells.isEmpty && cells.allSatisfy { cell in
                  cell.number.fittingSize.width <= 46 && cell.number.font?.pointSize ?? 0 >= 10
                      && cell.bar.superview.map { compactContent.bounds.contains($0.convert($0.bounds, to: compactContent)) } == true
              },
              "Island stays 58pt wide and a 100% number fits readable inside each cell")
        snapshot(compactContent, "island")
        // VoiceOver reads each cell as one sentence, with the level in words.
        if let codex = islandCell(.codex), let cell = codex.ring.superview {
            check(cell.isAccessibilityElement() && cell.accessibilityRole() == .staticText
                  && cell.accessibilityLabel() == ["Codex", tr("%@ limit %@% used", tr("5-hour"), 100), tr("near limit"),
                                                     tr("%@ limit %@% used", tr("7-day"), 72), tr("high")].joined(separator: ", ")
                  && cell.accessibilityChildren()?.isEmpty != false
                  && codex.ring.isCritical && !codex.ring.isWarning,
                  "VoiceOver reads the Codex cell as one sentence with both windows and their levels")
        }
        if let claude = islandCell(.claude), let label = claude.ring.superview?.accessibilityLabel() {
            check(label.hasPrefix("Claude, "), "VoiceOver reads the Claude cell with its name")
        }
        check(compactContent.isAccessibilityElement() && compactContent.accessibilityRole() == .group
              && compactContent.accessibilityLabel() == "AI Island"
              && compactContent.accessibilityCustomActions()?.first?.name == tr("Show or hide limits card"),
              "The island is a named group with an action that shows the limits card")
        let popoverViews = statusPopover.contentViewController.map { allViews($0.view) } ?? []
        let cardLabels = popoverViews.filter { $0.accessibilityRole() == .group && $0.isAccessibilityElement() }
            .compactMap { $0.accessibilityLabel() }
        let buttonLabels = popoverViews.compactMap { $0 as? NSButton }.compactMap { $0.accessibilityLabel() }
        check(cardLabels.contains(tr("%@ limits", "Codex")) && cardLabels.contains(tr("%@ limits", "Claude"))
              && [tr("Refresh limits"), tr("Manage AI Island"), tr("Update Claude Code and Codex CLI")].allSatisfy(buttonLabels.contains),
              "Popover cards and buttons are named for VoiceOver")
        check(popoverViews.contains { ($0 as? NSTextField)?.stringValue.hasPrefix(tr("%@ · %@% used", tr("5H"), 100) + " · " + tr("near limit")) == true }
              && popoverViews.contains { ($0 as? NSTextField)?.stringValue.hasPrefix(tr("%@ · %@% used", tr("7D"), 72) + " · " + tr("high")) == true },
              "Popover names the high and near-limit levels in words, not only in color")
        // Increase Contrast: dim text near-opaque, stronger tracks and borders; fills unchanged.
        let normalBorder = compactContent.layer?.borderColor.flatMap { NSColor(cgColor: $0) }?.alphaComponent ?? 0
        prefersIncreasedContrast = { true }
        accessibilityDisplayOptionsChanged()
        codexUsage = nil
        updateUsageViews()
        if let codex = islandCell(.codex) {
            let contrastBorder = compactContent.layer?.borderColor.flatMap { NSColor(cgColor: $0) }?.alphaComponent ?? 0
            let subtitle = popoverFields().first { $0.stringValue == tr("Click the island or outside to close") }
            check(codex.ring.highContrast && codex.bar.highContrast && (codex.number.textColor?.alphaComponent ?? 0) >= 0.9
                  && (subtitle?.textColor?.alphaComponent ?? 0) >= 0.9 && contrastBorder > normalBorder,
                  "Increase Contrast strengthens dim text, tracks and borders")
            snapshot(compactContent, "contrast")
        }
        prefersIncreasedContrast = { false }
        accessibilityDisplayOptionsChanged()
        if let codex = islandCell(.codex) {
            check(!codex.ring.highContrast && (codex.number.textColor?.alphaComponent ?? 1) < 0.9,
                  "Turning Increase Contrast off restores the normal look")
        }
        // Popover captions: plain case, proportional font, time left until reset with the absolute time in a tooltip.
        let now = Date().timeIntervalSince1970
        let fiveHourReset = now + 2 * 3_600 + 15 * 60 + 30, sevenDayReset = now + 3 * 86_400 + 4 * 3_600 + 30
        codexUsage = CodexUsageSnapshot(primary: CodexUsageWindow(usedPercent: 40, resetsAt: fiveHourReset),
                                        secondary: CodexUsageWindow(usedPercent: 72, resetsAt: sevenDayReset))
        updateUsageViews()
        var fields = popoverFields()
        let fiveHourCaption = fields.first { $0.stringValue.hasPrefix(tr("%@ · %@% used", tr("5H"), 40)) }
        let sevenDayCaption = fields.first { $0.stringValue.hasPrefix(tr("%@ · %@% used", tr("7D"), 72)) }
        check(fiveHourCaption?.stringValue == tr("%@ · %@% used", tr("5H"), 40) + tr(" · resets in %@", tr("%@h %@m", 2, 15).replacingOccurrences(of: " ", with: "\u{00A0}"))
              && sevenDayCaption?.stringValue == tr("%@ · %@% used", tr("7D"), 72) + " · " + tr("high") + tr(" · resets in %@", tr("%@d %@h", 3, 4).replacingOccurrences(of: " ", with: "\u{00A0}")),
              "Popover shows the time left until each window resets")
        if let view = statusPopover.contentViewController?.view, let five = fiveHourCaption, let seven = sevenDayCaption {
            view.layoutSubtreeIfNeeded()
            let card = allViews(view).first { $0.layer?.cornerRadius == 13 && seven.isDescendant(of: $0) }
            let needed = seven.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: seven.frame.width, height: 1_000)).height ?? .infinity
            // Whether the caption needs a second line depends on the interface language.
            let fitsOneLine = (seven.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 1_000)).width ?? .infinity) <= seven.frame.width
            check((fitsOneLine || seven.frame.height > five.frame.height * 1.5) && needed <= seven.frame.height + 1
                  && card.map { $0.bounds.contains(seven.convert(seven.bounds, to: $0)) } == true,
                  "A caption too long for one line wraps to a second line inside its card instead of cutting off the reset time")
        } else {
            check(false, "A caption too long for one line wraps to a second line inside its card instead of cutting off the reset time")
        }
        let year = String(Calendar.current.component(.year, from: Date(timeIntervalSince1970: sevenDayReset)))
        check(fiveHourCaption?.toolTip == Self.resetTooltip(fiveHourReset) && fiveHourCaption?.toolTip?.hasPrefix(tr("Resets at %@", "")) == true
              && fiveHourCaption?.toolTip?.contains(year) == false && sevenDayCaption?.toolTip?.contains(year) == true,
              "The absolute reset time is in the tooltip, with the date when it is days away")
        let texts = fields.map(\.stringValue)
        let captions = texts.filter { $0.hasPrefix(tr("5H") + " · ") || $0.hasPrefix(tr("7D") + " · ") }
        check(texts.contains(tr("Live AI limits")) && !captions.isEmpty
              && captions.allSatisfy { $0.contains(tr("%@% used", "")) || $0.hasSuffix(tr("%@ · not available", "")) }
              && !texts.contains { $0.contains("USED") || $0.contains("UNAVAILABLE") || $0.contains("RESET") || $0 == "LIVE AI LIMITS" },
              "Popover captions are in plain case")
        check(fields.allSatisfy { $0.font?.isFixedPitch == false }, "Popover text uses the proportional system font")
        check(!texts.contains { ["LOCAL", "OFFLINE"].contains($0) || $0.contains("managed file") },
              "Popover has no LOCAL/OFFLINE badge or managed file count")
        if let view = statusPopover.contentViewController?.view { snapshot(view, "popover") }
        // Refreshes update the open popover and the island in place: same views, new values.
        let shownController = statusPopover.contentViewController
        /// Layer-backed views report a pending redraw on their layer.
        func marked(_ view: NSView) -> Bool { view.needsDisplay || view.layer?.needsDisplay() == true }
        let popoverButtons = shownController.map { allViews($0.view).compactMap { $0 as? NSButton } } ?? []
        let codexCell = islandCell(.codex)
        codexUsage = CodexUsageSnapshot(primary: CodexUsageWindow(usedPercent: 41, resetsAt: fiveHourReset),
                                        secondary: CodexUsageWindow(usedPercent: 72, resetsAt: sevenDayReset))
        updateUsageViews()
        let updatedButtons = statusPopover.contentViewController.map { allViews($0.view).compactMap { $0 as? NSButton } } ?? []
        check(statusPopover.contentViewController === shownController && fiveHourCaption?.window != nil
              && fiveHourCaption?.stringValue == tr("%@ · %@% used", tr("5H"), 41) + tr(" · resets in %@", tr("%@h %@m", 2, 15).replacingOccurrences(of: " ", with: "\u{00A0}"))
              && fiveHourCaption?.toolTip == Self.resetTooltip(fiveHourReset)
              && !popoverButtons.isEmpty && updatedButtons.count == popoverButtons.count
              && zip(updatedButtons, popoverButtons).allSatisfy { $0 === $1 && $0.toolTip == $1.toolTip },
              "A refresh updates the open popover in place: same caption, buttons and tooltips, new value")
        check(codexCell.map { cell in islandCell(.codex).map { $0.ring === cell.ring && $0.number.stringValue == "41%" } == true } == true
              && codexCell.map { marked($0.ring) } == true,
              "A refresh updates the island cell in place and redraws the changed ring")
        try? await Task.sleep(for: .milliseconds(100))  // Let AppKit draw the pending changes.
        let pendingBefore = (statusPopover.contentViewController.map { allViews($0.view) } ?? []).filter(marked).count
            + allViews(compactContent).filter(marked).count
        updateUsageViews()
        let popoverRedraws = statusPopover.contentViewController.map { allViews($0.view).filter(marked) } ?? []
        let islandRedraws = allViews(compactContent).filter(marked)
        check(statusPopover.contentViewController === shownController && pendingBefore == 0 && popoverRedraws.isEmpty && islandRedraws.isEmpty,
              "A refresh without changes redraws nothing (\(popoverRedraws.count) popover, \(islandRedraws.count) island views marked)")
        codexUsage = nil
        updateUsageViews()
        check(statusPopover.contentViewController !== shownController, "A change in rows (Codex windows gone) rebuilds the popover")
        fields = popoverFields()
        check(fields.contains { $0.stringValue == tr("Limits not available yet") } && !fields.contains { $0.stringValue.hasSuffix("LIMIT UNAVAILABLE") },
              "Codex without any window shows one quiet line instead of a row per window")
        if let view = statusPopover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            let cards = allViews(view).filter { $0.layer?.cornerRadius == 13 }
            check(cards.count >= 2 && cards.allSatisfy { $0.frame.width == 324 }, "Provider cards keep the full width without usage bars")
        }
        isCodexUsageLoading = true
        updateUsageViews()
        check(popoverFields().contains { $0.stringValue == tr("Loading limits…") }, "Codex shows Loading limits… before the first answer")
        isCodexUsageLoading = false
        prefersReducedMotion = defaultReducedMotion
        codexUsage = lastCodexUsage
        usageRefreshTimer?.invalidate()
        statusPopover.performClose(nil)
        try? await Task.sleep(for: .milliseconds(400))
        // The card is click-only: the island click toggles it, and a drag that
        // moved the island between mouse-down and the click must not open it.
        func pressIsland() {
            if let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                              windowNumber: island.windowNumber, context: nil, eventNumber: 0,
                                              clickCount: 1, pressure: 1) {
                handleLocalMouseDown(event)
            }
        }
        pressIsland(); toggleExpanded()
        let subtitles = statusPopover.contentViewController.map {
            allViews($0.view).compactMap { ($0 as? NSTextField)?.stringValue }
        } ?? []
        check(statusPopover.isShown && subtitles.contains(tr("Click the island or outside to close"))
              && !subtitles.contains { $0.contains("Hover") },
              "Island click opens the card and the subtitle describes click-only behavior")
        pressIsland(); toggleExpanded()
        try? await Task.sleep(for: .milliseconds(400))
        check(!statusPopover.isShown, "A second island click closes the card")
        let restingFrame = island.frame
        pressIsland()
        island.setFrameOrigin(NSPoint(x: restingFrame.minX - 40, y: restingFrame.minY))
        toggleExpanded()
        island.setFrame(restingFrame, display: true)
        check(!statusPopover.isShown, "Dragging the island does not open the card")
        try? checks.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    // Opt-in native regression: exercise the same NSButton actions and window
    // close callbacks as the UI, including reopening an editor after closing it.
    /// Sends a ⌘-key press through the app's normal event path (menus first), as a person would.
    private static func pressCommand(_ key: String, keyCode: UInt16, in window: NSWindow) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: key,
                                           charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode) else { return }
        NSApp.sendEvent(event)
    }

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
                if cycle == 1 {
                    let sidebar = settingsSidebar.table
                    func pageHeading() -> String? {
                        ((settingsDetailView?.subviews.first as? NSStackView)?.arrangedSubviews.first as? NSTextField)?.stringValue
                    }
                    try require(sidebar.style == .sourceList && sidebar.window === settingsWindow
                                && sidebar.numberOfRows == SettingsArea.allCases.count,
                                "Settings sidebar is not a source list with every area")
                    for area in SettingsArea.allCases {
                        sidebar.selectRowIndexes(IndexSet(integer: area.rawValue), byExtendingSelection: false)
                        try require(selectedSettingsArea == area && pageHeading() == area.title,
                                    "Selecting \(area.title) in the sidebar did not open its page")
                    }
                    checks.append("PASS settings sidebar: native source list; selecting a row opens its page")
                    selectedSettingsArea = .codex
                    refreshSettingsPage()
                    try require(sidebar.selectedRow == SettingsArea.codex.rawValue, "Sidebar selection did not follow the page")
                    checks.append("PASS settings sidebar: selection follows pages opened elsewhere")
                    sidebar.selectRowIndexes(IndexSet(integer: SettingsArea.accounts.rawValue), byExtendingSelection: false)
                    let accountsPage = (settingsDetailView?.subviews.first as? NSStackView)?.arrangedSubviews ?? []
                    let accountRows = accountsPage.filter { $0.identifier?.rawValue == "account-row" }
                    let usageLabels = accountRows.compactMap { row in
                        row.subviews.first { $0.identifier?.rawValue == "account-usage" } as? NSTextField
                    }
                    try require(!accountRows.isEmpty && accountRows.count == claudeSources.count
                                && usageLabels.count == accountRows.count && usageLabels.allSatisfy { !$0.stringValue.isEmpty }
                                && accountsPage.contains { $0.identifier?.rawValue == "accounts-manage" },
                                "Accounts page does not list each account with its usage and a manage button")
                    checks.append("PASS settings accounts: \(accountRows.count) account row(s) with status and usage, plus Manage")
                    for provider in Provider.allCases {
                        let paths = configurationCategories(for: provider).flatMap(\.paths)
                        try require(Set(paths).count == paths.count, "\(provider.rawValue) has two cards for one file")
                    }
                    checks.append("PASS settings cards: no two cards open the same file")
                    func texts(in view: NSView) -> [String] {
                        ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap { texts(in: $0) }
                    }
                    let sidebarTexts: [String] = ((settingsWindow?.contentView as? NSSplitView)?.subviews.first).map { texts(in: $0) } ?? []
                    try require(sidebarTexts.contains(Self.backupNote) && Self.backupNote.contains("AI Island/Backups")
                                && !sidebarTexts.contains { $0.contains("Every future edit") },
                                "Sidebar backup note does not describe the actual backup")
                    checks.append("PASS settings sidebar: backup note names when and where backups are written")
                }
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
                        try require(allConfigurationFiles.count == count && configurationRows.count == listed, "File count differs from list")
                        if let tree = configurationSkillTree {
                            try require(listed == tree.skills.count + tree.looseFiles.count && tree.fileCount == count,
                                        "Skills list does not show one collapsed row per skill")
                            if let row = configurationRows.firstIndex(where: { if case .skill(_, let files) = $0.kind { files > 1 } else { false } }),
                               let table = configurationTable, let skill = configurationRows[row].skillFolder.flatMap({ folder in tree.skills.first { $0.folder == folder } }) {
                                try require(setSkillExpanded(true, atRow: row) && table.numberOfRows == listed + skill.files.count
                                            && configurationFiles[(row + 1)...].prefix(skill.files.count).elementsEqual(skill.files),
                                            "Expanding a skill does not list its files under it")
                                try require(setSkillExpanded(false, atRow: row) && table.numberOfRows == listed, "Collapsing a skill does not hide its files")
                                checks.append("PASS skills: \(button.identifier?.rawValue ?? "unknown") — \(tree.skills.count) skills, \(count) files, \(skill.name) expands to \(skill.files.count)")
                            }
                        }
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
                            if listed > 10 { try require(visible >= 5, "Long file list shows fewer than five rows") }
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
                            for index in Set([0, listed / 2, listed - 1]).sorted() where configurationFiles.indices.contains(index) {
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
                                // A skill row may be listed only as the parent of a matching file.
                                let query = search.stringValue
                                try require(!configurationRows.isEmpty && configurationRows.indices.allSatisfy { index in
                                    let row = configurationRows[index]
                                    if displayedFilePath(row.file).localizedCaseInsensitiveContains(query) { return true }
                                    guard case .skill = row.kind, configurationRows.indices.contains(index + 1) else { return false }
                                    return configurationRows[index + 1].kind == .attached
                                }, "Search returned incorrect files")
                            }
                            search.stringValue = ""
                            NSApp.sendAction(search.action!, to: search.target, from: search)
                            try require(table.numberOfRows == listed, "Clearing search did not restore files")
                            try require(configurationEditor?.string == draft, "Clearing search discarded the editor draft")
                            configurationEditor?.string = original
                            checks.append("PASS search: \(button.identifier?.rawValue ?? "unknown") — filter, clear, preserve draft")
                        }
                        if cycle == 1, let editor = configurationEditor, let window = configurationWindow,
                           let file = activeConfigurationFile, configurationFiles.count >= 2,
                           let otherRow = configurationFiles.firstIndex(where: { $0.path != file.path }) {
                            // Exercise the unsaved-changes guard without ever writing the user's files.
                            let defaultAsk = askAboutUnsavedConfiguration, defaultConfirm = confirmConfigurationSave
                            let defaultSyntax = presentConfigurationSyntaxProblem
                            defer {
                                askAboutUnsavedConfiguration = defaultAsk
                                confirmConfigurationSave = defaultConfirm
                                presentConfigurationSyntaxProblem = defaultSyntax
                            }
                            let original = editor.string
                            let selectedRow = table.selectedRow
                            editor.setSelectedRange(NSRange(location: (original as NSString).length, length: 0))
                            editor.insertText("\nRegression draft (not saved)", replacementRange: editor.selectedRange())
                            let draft = editor.string
                            try require(draft != original && window.isDocumentEdited
                                        && configurationStatus?.stringValue.hasPrefix(tr("Edited")) == true,
                                        "Unsaved edit is not marked in the window and status")
                            var asked = 0
                            askAboutUnsavedConfiguration = { _ in asked += 1; return .cancel }
                            try require(!tableView(table, shouldSelectRow: otherRow), "Cancel did not keep the current file selected")
                            try require(editor.string == draft && table.selectedRow == selectedRow && activeConfigurationFile == file,
                                        "Cancel on file switch changed the draft or selection")
                            openConfigurationCategory(button)
                            try require(editor.string == draft && activeConfigurationFile == file, "Cancel on category switch discarded the draft")
                            try require(!windowShouldClose(window) && editor.string == draft, "Cancel on close discarded the draft")
                            try require(asked == 3, "Unsaved-changes prompt was not shown for file, category, and close")
                            try require(applicationShouldTerminate(NSApp) == .terminateCancel && asked == 4
                                        && editor.string == draft && window.isVisible,
                                        "Quit did not ask about the unsaved edit, or cancelling it did not keep the draft")
                            window.makeFirstResponder(editor)
                            Self.pressCommand("a", keyCode: 0, in: window)
                            try require(editor.selectedRange() == NSRange(location: 0, length: (draft as NSString).length),
                                        "Command-A did not select all editor text")
                            NSApp.mainMenu?.update()
                            let undoItem = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] }
                                .first { $0.action == #selector(undoInFrontWindow) }
                            try require(undoItem?.title == tr("Undo") && undoItem?.isEnabled == (editor.undoManager?.canUndo == true),
                                        "Undo menu item lost its translated title or does not follow the editor's undo state")
                            editor.setSelectedRange(NSRange(location: 0, length: 0))
                            var reviewed = false, syntaxProblem: (error: ConfigurationSyntaxError, canOverride: Bool)?
                            confirmConfigurationSave = { _ in reviewed = true; return false }
                            // "Save Anyway" on a TOML warning must still lead to review, never straight to disk.
                            presentConfigurationSyntaxProblem = { error, _, canOverride in syntaxProblem = (error, canOverride); return canOverride }
                            func pressSave() {
                                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                                windowNumber: window.windowNumber, context: nil, characters: "s",
                                                                charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1) {
                                    _ = window.performKeyEquivalent(with: event)
                                }
                            }
                            pressSave()
                            var syntaxNote = ""
                            let format = file.pathExtension.lowercased()
                            if format == "json" || format == "toml", ConfigurationSyntax.validate(original, pathExtension: format) == nil {
                                // The appended plain-text line is invalid in both formats.
                                guard let problem = syntaxProblem else { throw RegressionFailure(message: "⌘S saved invalid \(format) without a syntax check") }
                                try require(editor.selectedRange().location == problem.error.offset
                                            && configurationStatus?.stringValue == tr("Syntax error · %@", problem.error),
                                            "Syntax error position is not selected or not shown in the status")
                                try require((try? String(contentsOf: file, encoding: .utf8)) == original, "Invalid draft wrote the file")
                                if format == "json" {
                                    try require(!problem.canOverride && !reviewed && editor.string == draft,
                                                "Invalid JSON reached review or offered Save Anyway")
                                    // A whitespace-only change is still valid JSON and must reach review.
                                    syntaxProblem = nil
                                    editor.insertText(original + "\n", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
                                    pressSave()
                                    try require(syntaxProblem == nil && reviewed, "Valid JSON did not reach the review step")
                                    syntaxNote = ", invalid JSON blocked at line \(problem.error.line)"
                                } else {
                                    try require(problem.canOverride && reviewed, "TOML warning did not offer Save Anyway before review")
                                    syntaxNote = ", TOML warns at line \(problem.error.line)"
                                }
                            }
                            let draftDiff = LineDiff(old: original, new: draft)
                            let preview = makeDiffPreview(draftDiff)
                            let previewText = (preview.documentView as? NSTextView)?.string ?? ""
                            try require(draftDiff.removed == 0 && (1...2).contains(draftDiff.added)
                                        && previewText.contains("+ Regression draft (not saved)")
                                        && preview.hasVerticalScroller && preview.frame.height <= 300,
                                        "Review preview does not show the changed lines in a scroll view")
                            if let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds) {
                                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                                try? bitmap.representation(using: .png, properties: [:])?
                                    .write(to: report.deletingPathExtension().appendingPathExtension("diff.png"))
                            }
                            try require(reviewed && editor.string != original && window.isDocumentEdited,
                                        "⌘S did not open the review step, or a declined review changed the draft")
                            try require((try? String(contentsOf: file, encoding: .utf8)) == original, "Declined save wrote the file")
                            askAboutUnsavedConfiguration = { _ in .discard }
                            try require(tableView(table, shouldSelectRow: otherRow) && editor.string == original && !window.isDocumentEdited,
                                        "Discard did not restore the saved text")
                            checks.append("PASS unsaved edits: \(button.identifier?.rawValue ?? "unknown") — marked, Cancel keeps draft on file/category/close, ⌘S reviews\(syntaxNote), Discard restores")
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
                        if let window = configurationWindow { Self.pressCommand("w", keyCode: 13, in: window) }
                        try await Task.sleep(for: .milliseconds(50))
                        try require(configurationWindow?.isVisible == false, "Command-W did not close the editor")
                    }
                }
                if let window = settingsWindow { Self.pressCommand("w", keyCode: 13, in: window) }
                try await Task.sleep(for: .milliseconds(50))
                try require(settingsWindow?.isVisible == false, "Command-W did not close Settings")
                checks.append("PASS cycle \(cycle): Command-W closes the editor and Settings, Settings reopens")
            }
            let menuItems = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
            func shortcut(_ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem? {
                menuItems.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == modifiers }
            }
            try require(shortcut("q")?.title == tr("Quit AI Island") && shortcut("q")?.action == #selector(NSApplication.terminate(_:))
                        && shortcut("w")?.title == tr("Close Window") && shortcut("w")?.action == #selector(NSWindow.performClose(_:))
                        && !menuItems.contains { $0.title.contains("Close Settings") },
                        "Menu names do not match their actions (Quit AI Island ⌘Q, Close Window ⌘W)")
            try require(["Undo": shortcut("z"), "Redo": shortcut("z", [.command, .shift]), "Cut": shortcut("x"),
                         "Copy": shortcut("c"), "Paste": shortcut("v"), "Select All": shortcut("a")].allSatisfy { $0.value?.title == tr($0.key) },
                        "Edit menu shortcuts are missing")
            checks.append("PASS: menu has Quit AI Island ⌘Q, Close Window ⌘W and standard Edit shortcuts")
            openSettings()
            try require(applicationShouldTerminate(NSApp) == .terminateNow && settingsWindow?.isVisible == true,
                        "Command-Q with no unsaved edits must quit, not hide Settings")
            checks.append("PASS: Command-Q quits AI Island when nothing is unsaved")
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

    /// ⌘Q and the status menu's Quit both quit AI Island, island included;
    /// only an unsaved editor change can stop it. ⌘W closes a single window.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        resolveUnsavedConfigurationChanges() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageRefreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender !== configurationWindow || resolveUnsavedConfigurationChanges()
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === island else { return }
        // Stored as the collapsed 58×126 origin around the same top center, which is
        // what restoreIslandPosition expects even when the island is expanded.
        let frame = island.frame
        let origin = NSPoint(x: frame.midX - Self.collapsedIslandWidth / 2, y: frame.maxY - 126)
        UserDefaults.standard.set([origin.x, origin.y], forKey: positionKey)
    }

    /// The menu bar stays hidden (accessory app), but its shortcuts work while an
    /// AI Island window is in front: ⌘W closes that window, ⌘Q quits AI Island,
    /// and the Edit items give text fields and the editor copy, paste and undo.
    private func buildMainMenu() {
        let menu = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem(), submenu = NSMenu(title: title)
            items.forEach(submenu.addItem); holder.submenu = submenu; menu.addItem(holder)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        submenu("AI Island", [
            item(tr("Open Settings…"), #selector(openSettings), ","),
            item(tr("Claude Accounts & Sessions…"), #selector(openClaudeAccounts), ""),
            item(tr("Refresh configuration"), #selector(refreshInventory), "r"),
            .separator(),
            item(tr("Quit AI Island"), #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu(tr("File"), [item(tr("Close Window"), #selector(NSWindow.performClose(_:)), "w")])
        submenu(tr("Edit"), [
            item(tr("Undo"), #selector(undoInFrontWindow), "z"),
            item(tr("Redo"), #selector(redoInFrontWindow), "z", [.command, .shift]),
            .separator(),
            item(tr("Cut"), #selector(NSText.cut(_:)), "x"),
            item(tr("Copy"), #selector(NSText.copy(_:)), "c"),
            item(tr("Paste"), #selector(NSText.paste(_:)), "v"),
            item(tr("Select All"), #selector(NSText.selectAll(_:)), "a"),
        ])
        NSApp.mainMenu = menu
    }

    // AppKit retitles the standard undo:/redo: items in English ("Undo Typing");
    // these actions do the same through the front window and keep the translated titles.
    @objc private func undoInFrontWindow(_ sender: Any?) { NSApp.keyWindow?.firstResponder?.undoManager?.undo() }
    @objc private func redoInFrontWindow(_ sender: Any?) { NSApp.keyWindow?.firstResponder?.undoManager?.redo() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let undoManager = NSApp.keyWindow?.firstResponder?.undoManager
        switch item.action {
        case #selector(undoInFrontWindow): return undoManager?.canUndo == true
        case #selector(redoInFrontWindow): return undoManager?.canRedo == true
        default: return true
        }
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Island")
        item.button?.title = " AI"
        let menu = NSMenu(title: "AI Island")
        menu.addItem(NSMenuItem(title: tr("Show / hide island"), action: #selector(toggleIsland), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: tr("Open Settings…"), action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: tr("Claude Accounts & Sessions…"), action: #selector(openClaudeAccounts), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: tr("Refresh configuration"), action: #selector(refreshInventory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: tr("Quit AI Island"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
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
        compactContent.layer?.borderColor = hairline(0.17).cgColor
        compactContent.layer?.shadowColor = NSColor.black.cgColor
        compactContent.layer?.shadowOpacity = 0.56
        compactContent.layer?.shadowRadius = 14
        compactContent.layer?.shadowOffset = CGSize(width: 0, height: -3)
        restoreIslandPosition()
        collapseIsland(animated: false)
        let compactRecognizer = NSClickGestureRecognizer(target: self, action: #selector(toggleExpanded))
        compactContent.addGestureRecognizer(compactRecognizer)
        // VoiceOver: a named group with the provider cells inside, and an action
        // that does what a click does.
        compactContent.setAccessibilityElement(true)
        compactContent.setAccessibilityRole(.group)
        compactContent.setAccessibilityLabel("AI Island")
        compactContent.setAccessibilityHelp(tr("Live AI limits. Click to show or hide the limits card."))
        compactContent.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: tr("Show or hide limits card"), target: self, selector: #selector(toggleLimitsCardForAccessibility)),
        ])
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        updateNotchContent()
    }

    @objc private func toggleLimitsCardForAccessibility() -> Bool {
        toggleExpanded()
        return true
    }

    /// Increase Contrast or Reduce Motion changed: rebuild the island and the
    /// open card, since borders and backgrounds are set only when built.
    @objc private func accessibilityDisplayOptionsChanged() {
        compactContent.layer?.borderColor = hairline(0.17).cgColor
        islandCellViews = [:]
        updateNotchContent()
        if statusPopover.isShown { showPopoverContent(currentPopoverModel) }
    }

    @objc private func toggleExpanded() {
        if let origin = islandOriginAtMouseDown {
            islandOriginAtMouseDown = nil
            let current = island.frame.origin
            guard hypot(current.x - origin.x, current.y - origin.y) <= 2 else { return }
        }
        if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            showStatusPopover()
        }
    }

    /// Sizes the island for its content: collapsed, or expanded with the active
    /// Claude session. Size changes animate around the top center unless
    /// `animated` is false or Reduce Motion is on.
    private func collapseIsland(animated: Bool = true) {
        island.contentView = compactContent
        let width = claudeAccounts?.islandStatus == nil ? Self.collapsedIslandWidth : Self.expandedIslandWidth
        let height: CGFloat = claudeLoggedIn == false && claudeAccounts?.hasAccounts != true ? 66 : 126
        resizeIsland(width: width, height: height, animate: animated && !prefersReducedMotion())
    }

    private func resizeIsland(width: CGFloat, height: CGFloat, animate: Bool) {
        var frame = island.frame
        let midpoint = frame.midX
        let top = frame.maxY
        frame.origin.x = midpoint - width / 2
        frame.origin.y = top - height
        frame.size.width = width
        frame.size.height = height
        guard frame != island.frame else { return }
        guard animate else { island.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            island.animator().setFrame(frame, display: true)
        }
    }

    private func restoreIslandPosition() {
        if let stored = UserDefaults.standard.array(forKey: positionKey) as? [CGFloat], stored.count == 2 {
            let restored = NSRect(x: stored[0], y: stored[1], width: Self.collapsedIslandWidth, height: 126)
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
        updateUsageViews()
        refreshSettingsPage()
    }

    /// Claude is orange; Codex is white like ChatGPT. Island and popover share these.
    private func accentColor(for provider: Provider) -> NSColor {
        provider == .codex ? .white : NSColor(calibratedRed: 1, green: 0.57, blue: 0.20, alpha: 1)
    }

    /// Usage color by limit level (thresholds live in `UsageLevel`): the provider
    /// color while there is headroom, then yellow, then red. Island ring, island
    /// bar and popover bars all use this.
    /// The non-color word for a usage level, shown in text next to the color.
    static func levelWord(percent: Double) -> String? {
        switch UsageLevel(percent: percent) {
        case .normal: nil
        case .warning: tr("high")
        case .critical: tr("near limit")
        }
    }

    /// Secondary text: dimmed normally, near-opaque under Increase Contrast.
    private func quietText(_ alpha: CGFloat, _ color: NSColor = .white) -> NSColor {
        color.withAlphaComponent(prefersIncreasedContrast() ? max(alpha, 0.9) : alpha)
    }

    /// Borders and separators: stronger under Increase Contrast. Fills stay as
    /// they are, so text on them keeps its contrast.
    private func hairline(_ alpha: CGFloat, _ color: NSColor = .white) -> NSColor {
        color.withAlphaComponent(prefersIncreasedContrast() ? max(alpha, min(alpha * 2.5, 0.7)) : alpha)
    }

    private func usageColor(accent: NSColor, percent: Double) -> NSColor {
        switch UsageLevel(percent: percent) {
        case .normal: accent
        case .warning: .systemYellow
        case .critical: .systemRed
        }
    }

    /// Everything one island cell shows, as values.
    private struct IslandCellModel: Equatable {
        let ringAccent: NSColor
        let progress: CGFloat
        let isCritical: Bool
        let isWarning: Bool
        let isPulsing: Bool
        let highContrast: Bool
        let isLoading: Bool
        let isUnknown: Bool
        let number: String
        let numberColor: NSColor
        let barAccent: NSColor
        let barProgress: CGFloat?
        let toolTip: String
        /// What VoiceOver reads for the whole cell.
        let accessibilityLabel: String
    }

    /// Everything the island shows. Views are built once per `layout`; later
    /// refreshes only write the values that changed, and an unchanged refresh
    /// touches nothing.
    private struct IslandModel: Equatable {
        let codex: IslandCellModel
        /// nil while Claude is logged out and has no accounts: the island shows Codex only.
        let claude: IslandCellModel?
        let session: ClaudeAccountsWindow.IslandStatus?
        let sessionToolTip: String?
        var layout: [Bool] { [claude != nil, session != nil, session?.canContinue == true] }
    }

    private struct IslandCellViews {
        let cell: NSView
        let ring: UsageRingView
        let mark: NSImageView
        let number: NSTextField
        let bar: UsageBarView
    }

    private struct IslandSessionViews {
        let stack: NSStackView
        let account: NSTextField
        let state: NSTextField
        let button: NSButton?
    }

    private var currentIslandModel: IslandModel {
        let showsClaude = claudeLoggedIn != false || claudeAccounts?.hasAccounts == true
        let session = showsClaude ? claudeAccounts?.islandStatus : nil
        return IslandModel(codex: islandCellModel(for: .codex),
                           claude: showsClaude ? islandCellModel(for: .claude) : nil,
                           session: session,
                           sessionToolTip: session == nil ? nil : claudeAccounts?.islandSummary)
    }

    /// Brings the island up to date: rebuilt only when its layout changes,
    /// otherwise the existing views take the new values in place.
    private func updateNotchContent() {
        let model = currentIslandModel
        guard model != islandModel || islandCellViews.isEmpty else { return }
        if model.layout != islandModel?.layout || islandCellViews.isEmpty { buildNotchContent(for: model) }
        let previous = islandModel
        islandModel = model
        if let views = islandCellViews[.codex], model.codex != previous?.codex || previous?.layout != model.layout {
            apply(model.codex, to: views)
        }
        if let claude = model.claude, let views = islandCellViews[.claude], claude != previous?.claude || previous?.layout != model.layout {
            apply(claude, to: views)
        }
        if let session = model.session, let views = islandSessionViews {
            apply(session, toolTip: model.sessionToolTip, to: views)
        }
    }

    private func buildNotchContent(for model: IslandModel) {
        compactContent.subviews.forEach { $0.removeFromSuperview() }
        compactContent.layoutGuides.forEach { compactContent.removeLayoutGuide($0) }
        islandCellViews = [:]
        islandSessionViews = nil
        islandModel = nil
        let codex = makeIslandCell(for: .codex)
        islandCellViews[.codex] = codex
        compactContent.addSubview(codex.cell)
        guard model.claude != nil else {
            NSLayoutConstraint.activate([
                codex.cell.centerXAnchor.constraint(equalTo: compactContent.centerXAnchor),
                codex.cell.topAnchor.constraint(equalTo: compactContent.topAnchor, constant: 8),
                codex.cell.widthAnchor.constraint(equalToConstant: 46),
                codex.cell.heightAnchor.constraint(equalToConstant: 51),
            ])
            return
        }
        // The provider column looks the same collapsed and expanded; expanded adds
        // the active session's details to its right.
        let column = NSLayoutGuide()
        compactContent.addLayoutGuide(column)
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = hairline(0.12).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        let claude = makeIslandCell(for: .claude)
        islandCellViews[.claude] = claude
        compactContent.addSubview(separator)
        compactContent.addSubview(claude.cell)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: compactContent.leadingAnchor),
            column.topAnchor.constraint(equalTo: compactContent.topAnchor),
            column.bottomAnchor.constraint(equalTo: compactContent.bottomAnchor),
            column.widthAnchor.constraint(equalToConstant: Self.collapsedIslandWidth),
            codex.cell.centerXAnchor.constraint(equalTo: column.centerXAnchor),
            codex.cell.topAnchor.constraint(equalTo: compactContent.topAnchor, constant: 8),
            codex.cell.widthAnchor.constraint(equalToConstant: 46),
            codex.cell.heightAnchor.constraint(equalToConstant: 51),
            separator.centerXAnchor.constraint(equalTo: column.centerXAnchor),
            separator.topAnchor.constraint(equalTo: codex.cell.bottomAnchor, constant: 4),
            separator.widthAnchor.constraint(equalToConstant: 32),
            separator.heightAnchor.constraint(equalToConstant: 1),
            claude.cell.centerXAnchor.constraint(equalTo: column.centerXAnchor),
            claude.cell.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            claude.cell.widthAnchor.constraint(equalToConstant: 46),
            claude.cell.heightAnchor.constraint(equalToConstant: 51),
        ])
        guard let session = model.session else { return }
        let details = makeIslandSessionViews(withContinue: session.canContinue)
        islandSessionViews = details
        compactContent.addSubview(details.stack)
        // Below windowSizeStayPut: the details must never resize the window
        // themselves, or a 58pt island would grow rightward and drift off center.
        let trailing = details.stack.trailingAnchor.constraint(equalTo: compactContent.trailingAnchor, constant: -12)
        trailing.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 10)
        NSLayoutConstraint.activate([
            details.stack.leadingAnchor.constraint(equalTo: column.trailingAnchor, constant: 2),
            trailing,
            details.stack.centerYAnchor.constraint(equalTo: compactContent.centerYAnchor),
        ])
    }

    static let collapsedIslandWidth: CGFloat = 58
    static let expandedIslandWidth: CGFloat = 232

    /// Active-session details beside the provider column: account name, state,
    /// and a Continue pill only when switching accounts would actually help.
    private func makeIslandSessionViews(withContinue: Bool) -> IslandSessionViews {
        func line(size: CGFloat, weight: NSFont.Weight, identifier: String) -> NSTextField {
            let label = NSTextField(labelWithString: "")
            label.identifier = NSUserInterfaceItemIdentifier(identifier)
            label.font = .systemFont(ofSize: size, weight: weight)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return label
        }
        let account = line(size: 12, weight: .semibold, identifier: "island-account")
        let state = line(size: 11, weight: .medium, identifier: "island-state")
        var views: [NSView] = [account, state]
        var button: NSButton?
        if withContinue {
            let orange = accentColor(for: .claude)
            let pill = NSButton(title: "", target: self, action: #selector(continueClaudeAccount))
            pill.identifier = NSUserInterfaceItemIdentifier("island-continue")
            pill.isBordered = false
            pill.lineBreakMode = .byTruncatingMiddle
            pill.wantsLayer = true
            pill.layer?.cornerRadius = 10
            pill.layer?.backgroundColor = orange.withAlphaComponent(0.16).cgColor
            pill.layer?.borderWidth = 1
            pill.layer?.borderColor = hairline(0.45, orange).cgColor
            pill.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            pill.heightAnchor.constraint(equalToConstant: 22).isActive = true
            views.append(pill)
            button = pill
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.setCustomSpacing(8, after: state)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in views { view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true }
        button?.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return IslandSessionViews(stack: stack, account: account, state: state, button: button)
    }

    private func apply(_ status: ClaudeAccountsWindow.IslandStatus, toolTip: String?, to views: IslandSessionViews) {
        let state: (text: String, color: NSColor) = if status.limitReached {
            (tr("Limit reached"), .systemRed)
        } else if let percent = status.percent {
            (tr("%@% used", Int(percent)) + (status.stale ? tr(" · last known") : status.restored ? tr(" · restored") : ""),
             status.stale ? quietText(0.55) : usageColor(accent: quietText(0.7), percent: percent))
        } else {
            (tr("Usage unknown") + (status.restored ? tr(" · restored") : ""), quietText(0.55))
        }
        views.account.show(status.account, color: .white)
        views.state.show(state.text, color: state.color)
        if let button = views.button, let standby = status.standby {
            let title = tr("Continue with %@ →", standby)
            if button.attributedTitle.string != title {
                button.attributedTitle = NSAttributedString(string: title, attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: accentColor(for: .claude),
                ])
            }
        }
        views.stack.setToolTipIfChanged(toolTip)
    }

    /// The two limit windows an island cell shows: the ring is 5H, the bar is 7D.
    private struct IslandWindows: Equatable {
        let fiveHour: Double?
        let sevenDay: Double?
        var hasAny: Bool { fiveHour != nil || sevenDay != nil }
    }

    /// What an island cell can honestly show for one provider.
    private enum IslandUsage: Equatable {
        case known(IslandWindows)
        case loading
        case unknown(reason: String)
    }

    private func islandUsage(for provider: Provider) -> IslandUsage {
        switch provider {
        case .codex:
            let windows = IslandWindows(fiveHour: codexUsage?.primary.map { Double($0.usedPercent) },
                                        sevenDay: codexUsage?.secondary.map { Double($0.usedPercent) })
            if windows.hasAny { return .known(windows) }
            if CodexUsageReader.executable == nil { return .unknown(reason: tr("Codex CLI not found")) }
            if !didFinishCodexUsageRequest { return .loading }
            return .unknown(reason: tr("Codex did not report limits"))
        case .claude:
            if let windows = claudeIslandWindows { return .known(windows) }
            if ClaudeAuthReader.executable == nil { return .unknown(reason: tr("Claude CLI not found")) }
            return .unknown(reason: tr("no usage recorded yet — limits appear after Claude's next response"))
        }
    }

    private func islandToolTip(for provider: Provider, usage: IslandUsage) -> String {
        switch usage {
        case .loading:
            return tr("%@ · loading limits…", provider.rawValue)
        case .unknown(let reason):
            return tr("%@ · limits unknown: %@", provider.rawValue, reason)
        case .known(let windows):
            func describe(_ percent: Double?) -> String { percent.map { tr("%@% used", Int($0.rounded())) } ?? tr("unknown") }
            let legend = tr("%@ · Ring: 5H %@ · Bar: 7D %@", provider.rawValue, describe(windows.fiveHour), describe(windows.sevenDay))
            guard provider == .claude else { return legend }
            return ([legend, claudeAccounts?.islandSummary, claudeUsageSummary].compactMap { $0 }).joined(separator: "\n")
        }
    }

    /// The cell as one sentence, e.g. "Claude, 5-hour limit 74% used, high, 7-day limit unknown".
    private func islandAccessibilityLabel(for provider: Provider, usage: IslandUsage) -> String {
        switch usage {
        case .loading:
            return tr("%@, loading limits", provider.rawValue)
        case .unknown(let reason):
            return tr("%@, limits unknown: %@", provider.rawValue, reason)
        case .known(let windows):
            func describe(_ title: String, _ percent: Double?) -> String {
                guard let percent else { return tr("%@ limit unknown", title) }
                return ([tr("%@ limit %@% used", title, Int(percent.rounded())), Self.levelWord(percent: percent)]
                    .compactMap { $0 }).joined(separator: ", ")
            }
            return [provider.rawValue, describe(tr("5-hour"), windows.fiveHour), describe(tr("7-day"), windows.sevenDay)]
                .joined(separator: ", ")
        }
    }

    private func islandCellModel(for provider: Provider) -> IslandCellModel {
        let accent = accentColor(for: provider)
        let usage = islandUsage(for: provider)
        let windows: IslandWindows? = if case .known(let windows) = usage { windows } else { nil }
        let fiveHour = windows?.fiveHour, sevenDay = windows?.sevenDay
        let ringAccent = fiveHour.map { usageColor(accent: accent, percent: $0) } ?? accent
        // Either window near its limit raises the badge, so a critical 7D is never hidden behind a calm 5H ring.
        let levels = [fiveHour, sevenDay].compactMap { $0.map { UsageLevel(percent: $0) } }
        let critical = levels.contains(.critical)
        let isUnknown: Bool = if case .unknown = usage { true } else { windows != nil && fiveHour == nil }
        let number = switch usage {
        case .loading: "…"
        case .unknown: "—"
        case .known: fiveHour.map { "\(Int($0.rounded()))%" } ?? "—"
        }
        return IslandCellModel(ringAccent: ringAccent, progress: fiveHour.map { CGFloat($0) / 100 } ?? 0,
                               isCritical: critical, isWarning: !critical && levels.contains(.warning),
                               isPulsing: critical && !prefersReducedMotion(), highContrast: prefersIncreasedContrast(),
                               isLoading: usage == .loading, isUnknown: isUnknown, number: number,
                               numberColor: fiveHour == nil ? quietText(0.45) : ringAccent,
                               barAccent: sevenDay.map { usageColor(accent: accent, percent: $0) } ?? accent,
                               barProgress: sevenDay.map { CGFloat($0) / 100 },
                               toolTip: islandToolTip(for: provider, usage: usage),
                               accessibilityLabel: islandAccessibilityLabel(for: provider, usage: usage))
    }

    private func makeIslandCell(for provider: Provider) -> IslandCellViews {
        let ring = UsageRingView(frame: .zero)
        ring.translatesAutoresizingMaskIntoConstraints = false
        let number = NSTextField(labelWithString: "")
        number.identifier = NSUserInterfaceItemIdentifier("island-percent")
        number.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        number.alignment = .center
        number.translatesAutoresizingMaskIntoConstraints = false
        let mark = providerLogoView(for: provider, accent: accentColor(for: provider))
        ring.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 16),
            mark.heightAnchor.constraint(equalToConstant: 16),
        ])
        let bar = UsageBarView(width: 38, height: 3)
        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        // VoiceOver reads the cell as one sentence instead of a logo and a bare number.
        cell.setAccessibilityElement(true)
        cell.setAccessibilityRole(.staticText)
        cell.identifier = NSUserInterfaceItemIdentifier("island-cell-\(provider.rawValue.lowercased())")
        for view in [ring, mark, number] as [NSView] { view.setAccessibilityElement(false) }
        cell.setAccessibilityChildren([])  // The text field and image report through their cells otherwise.
        cell.addSubview(ring)
        cell.addSubview(number)
        cell.addSubview(bar)
        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            ring.topAnchor.constraint(equalTo: cell.topAnchor),
            ring.widthAnchor.constraint(equalToConstant: 34),
            ring.heightAnchor.constraint(equalToConstant: 34),
            number.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            number.topAnchor.constraint(equalTo: ring.bottomAnchor),
            number.heightAnchor.constraint(equalToConstant: 12),
            bar.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            bar.topAnchor.constraint(equalTo: number.bottomAnchor, constant: 2),
        ])
        return IslandCellViews(cell: cell, ring: ring, mark: mark, number: number, bar: bar)
    }

    private func apply(_ model: IslandCellModel, to views: IslandCellViews) {
        views.ring.accent = model.ringAccent
        views.ring.progress = model.progress
        views.ring.isCritical = model.isCritical
        views.ring.isWarning = model.isWarning
        views.ring.highContrast = model.highContrast
        views.ring.isPulsing = model.isPulsing
        views.ring.isLoading = model.isLoading
        views.ring.isUnknown = model.isUnknown
        views.number.show(model.number, color: model.numberColor)
        views.bar.accent = model.barAccent
        views.bar.progress = model.barProgress
        views.bar.highContrast = model.highContrast
        if views.cell.accessibilityLabel() != model.accessibilityLabel { views.cell.setAccessibilityLabel(model.accessibilityLabel) }
        // The logo and ring cover most of the cell, so they carry the same tooltip.
        for view in [views.cell, views.ring, views.mark, views.number] { view.setToolTipIfChanged(model.toolTip) }
    }

    private func providerLogoView(for provider: Provider, accent: NSColor) -> NSImageView {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = accent
        let resource = provider == .codex ? "codex" : "claude"
        if let url = Self.resourceBundle?.url(forResource: resource, withExtension: "svg", subdirectory: "Resources"),
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

    /// SwiftPM's generated `Bundle.module` traps unless the resource bundle sits
    /// at the .app root or at the absolute build path baked in at compile time,
    /// which breaks as soon as the repository moves. The packaged app ships the
    /// bundle in Contents/Resources; only `swift run` falls back to `Bundle.module`.
    private static let resourceBundle: Bundle? = {
        if let url = Bundle.main.url(forResource: "AIIslandApp_AIIslandApp", withExtension: "bundle") {
            return Bundle(url: url)
        }
        return Bundle.main.bundleURL.pathExtension == "app" ? nil : Bundle.module
    }()

    private func showStatusPopover() {
        guard !statusPopover.isShown else { return }
        refreshInventory()
        showPopoverContent(currentPopoverModel)
        statusPopover.delegate = self
        statusPopover.behavior = .applicationDefined
        statusPopover.animates = true
        statusPopover.show(relativeTo: compactContent.bounds, of: compactContent, preferredEdge: .minY)
        refreshCodexUsage()
    }

    private func startUsageAutoRefresh() {
        usageRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: usageTickInterval, target: self, selector: #selector(usageTick),
                          userInfo: nil, repeats: true)
        timer.tolerance = usageTickInterval / 10
        usageRefreshTimer = timer
        // Keep polling while menus or the popover are tracking mouse events.
        RunLoop.main.add(timer, forMode: .common)
        refreshCodexUsage()
    }

    @objc private func usageTick() {
        refreshUsage(forceCodex: false)
    }

    /// Manual refresh (launch, opening the card, the Refresh button): asks Codex
    /// right away instead of waiting for the next interval.
    private func refreshCodexUsage() {
        refreshUsage(forceCodex: true)
    }

    private func refreshUsage(forceCodex: Bool) {
        // The Claude cache is a small local file, so it is re-read on every tick
        // and redrawn on its own, even while a Codex request is still in flight.
        let claude = readClaudeUsage()
        if claude != claudeUsage {
            claudeUsage = claude
            updateUsageViews()
        }
        // Only one Codex process at a time; a manual refresh joins the one in flight.
        guard !isCodexUsageLoading else { return }
        if !forceCodex, let last = lastCodexRequestStart,
           Date().timeIntervalSince(last) < codexRefreshInterval {
            return
        }
        isCodexUsageLoading = true
        lastCodexRequestStart = Date()
        if codexUsage == nil { updateUsageViews() }
        readCodexUsage { [weak self] usage in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let usage { self.codexUsage = usage }
                self.isCodexUsageLoading = false
                self.didFinishCodexUsageRequest = true
                self.updateUsageViews()
            }
        }
    }

    private func refreshClaudeAuth() {
        ClaudeAuthReader.read { [weak self] loggedIn in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.claudeLoggedIn = loggedIn
                self.updateNotchContent()
                self.collapseIsland()
                self.refreshSettingsPage()
                self.updatePopoverContent()
            }
        }
    }

    /// Everything the popover shows, as values. While its `shape` stays the
    /// same, a refresh writes the changed values into the open popover instead
    /// of replacing it, so tooltips, hover and VoiceOver focus survive.
    private struct PopoverModel: Equatable {
        struct Bar: Equatable {
            let progress: CGFloat
            let accent: NSColor
        }
        enum Item: Equatable {
            /// A Claude source heading: name (with " · now") and its status.
            case source(title: String, detail: String)
            /// A limit window caption with its bar, or one quiet line without a bar.
            case usage(caption: String, color: NSColor, toolTip: String?, bar: Bar?)
            case note(String, color: NSColor)
            case gap
            var shape: String {
                switch self {
                case .source: "source"
                case .usage(let caption, _, _, let bar): (bar == nil ? "line" : "bar") + (Self.wraps(caption) ? " wrapped" : "")
                case .note: "note"
                case .gap: "gap"
                }
            }
            /// Usage captions wrap to a second line instead of cutting off the reset time;
            /// a change in line count rebuilds the popover so the card height follows.
            static let captionWidth: CGFloat = 296
            static var captionFont: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .medium) }
            static func wraps(_ caption: String) -> Bool {
                (caption as NSString).size(withAttributes: [.font: captionFont]).width > captionWidth - 4
            }
        }
        struct Card: Equatable {
            let provider: Provider
            let detected: Bool
            let items: [Item]
        }
        let cards: [Card]
        var items: [Item] { cards.flatMap(\.items) }
        var shape: [String] { cards.flatMap { ["\($0.provider.rawValue) \($0.detected)"] + $0.items.map(\.shape) } }
    }

    private struct PopoverContent {
        let view: NSView
        /// The views each model item writes to, in `PopoverModel.items` order.
        let itemViews: [[NSView]]
    }

    private var currentPopoverModel: PopoverModel {
        func card(_ provider: Provider) -> PopoverModel.Card {
            let snapshot = snapshots.first(where: { $0.provider == provider }) ?? ConfigInventory.snapshot(for: provider)
            let accent = accentColor(for: provider)
            var items: [PopoverModel.Item] = []
            if provider == .codex {
                items = usageWindowItems([(tr("5H"), codexUsage?.primary), (tr("7D"), codexUsage?.secondary)], accent: accent,
                                         loading: isCodexUsageLoading && codexUsage == nil)
            } else {
                let current = currentClaudeSource
                for (index, source) in claudeSources.enumerated() {
                    if index > 0 { items.append(.gap) }
                    items.append(.source(title: source.name + (source.name == current?.name ? tr(" · now") : ""), detail: source.detail))
                    items += usageWindowItems([(tr("5H"), source.fiveHour), (tr("7D"), source.sevenDay)], accent: accent,
                                              suffix: source.stale ? tr(" · last known") : "")
                }
                if let summary = claudeAccounts?.islandSummary {
                    items.append(.note(summary, color: accent.withAlphaComponent(0.9)))
                }
            }
            return PopoverModel.Card(provider: provider, detected: snapshot.isInstalled, items: items)
        }
        let showsClaude = claudeLoggedIn != false || claudeAccounts?.hasAccounts == true
        return PopoverModel(cards: [card(.codex)] + (showsClaude ? [card(.claude)] : []))
    }

    private func showPopoverContent(_ model: PopoverModel) {
        let content = makeStatusPopoverView(model)
        let controller = NSViewController()
        controller.view = content.view
        statusPopover.contentViewController = controller
        shownPopover = (model, content.itemViews)
    }

    /// Brings the open popover up to date: rebuilt only when its rows change
    /// (an account added, a window appearing), otherwise updated in place.
    private func updatePopoverContent() {
        guard statusPopover.isShown else { return }
        let model = currentPopoverModel
        guard let shown = shownPopover, shown.model.shape == model.shape else { showPopoverContent(model); return }
        guard model != shown.model else { return }
        for (index, item) in model.items.enumerated() where item != shown.model.items[index] {
            apply(item, to: shown.itemViews[index])
        }
        shownPopover = (model, shown.itemViews)
    }

    private func updateUsageViews() {
        updateNotchContent()
        updatePopoverContent()
    }

    private func makeStatusPopoverView(_ model: PopoverModel) -> PopoverContent {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 356, height: 254))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(
            calibratedRed: 0.025,
            green: 0.035,
            blue: 0.065,
            alpha: 1
        ).cgColor
        root.layer?.cornerRadius = 20
        root.layer?.borderWidth = 1
        root.layer?.borderColor = hairline(0.12).cgColor
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: tr("Live AI limits"))
        heading.font = .systemFont(ofSize: 14, weight: .bold)
        heading.textColor = .white
        let subtitle = NSTextField(labelWithString: tr("Click the island or outside to close"))
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = quietText(0.62)
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(subtitle)
        var itemViews: [[NSView]] = []
        for card in model.cards {
            stack.addArrangedSubview(providerRow(for: card, itemViews: &itemViews))
        }

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        for (symbol, tip, action) in [("arrow.clockwise", tr("Refresh limits"), #selector(refreshAndReopenPopover)),
                                      ("gearshape", tr("Manage AI Island"), #selector(openSettingsFromPopover)),
                                      ("arrow.down.circle", tr("Update Claude Code and Codex CLI"), #selector(updateCLIs))] {
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
        root.setFrameSize(NSSize(width: 356, height: stack.fittingSize.height))
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
        ])
        return PopoverContent(view: root, itemViews: itemViews)
    }

    private func providerRow(for model: PopoverModel.Card, itemViews: inout [[NSView]]) -> NSStackView {
        let provider = model.provider
        let accent = accentColor(for: provider)
        let card = NSView(frame: NSRect(x: 0, y: 0, width: 324, height: 124))
        card.wantsLayer = true
        card.layer?.cornerRadius = 13
        card.layer?.backgroundColor = accent.withAlphaComponent(0.13).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = hairline(0.42, accent).cgColor
        card.setAccessibilityElement(true)
        card.setAccessibilityRole(.group)
        card.setAccessibilityLabel(tr("%@ limits", provider.rawValue))

        let dot = NSTextField(labelWithString: model.detected ? "●" : "○")
        dot.textColor = accent
        dot.font = .systemFont(ofSize: 14, weight: .bold)
        dot.cell?.setAccessibilityElement(false)  // "Not detected" says the same in words.
        let name = NSTextField(labelWithString: provider.rawValue)
        name.font = .systemFont(ofSize: 16, weight: .bold)
        name.textColor = accent
        let topRow = NSStackView(views: [dot, name])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 6
        var content: [NSView] = [topRow]
        // File counts live in Settings; the card is about limits only.
        if !model.detected {
            let state = NSTextField(labelWithString: tr("Not detected"))
            state.font = .systemFont(ofSize: 13, weight: .semibold)
            state.textColor = quietText(0.78)
            content.append(state)
        }
        for item in model.items {
            let views = makePopoverItemViews(item)
            apply(item, to: views.updated)
            content += views.arranged
            itemViews.append(views.updated)
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
            card.widthAnchor.constraint(equalToConstant: 324),
            card.heightAnchor.constraint(equalToConstant: copy.fittingSize.height + 26),
        ])
        let row = NSStackView(views: [card])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 324).isActive = true
        return row
    }

    /// `arranged` go into the card's stack; `updated` are the views `apply` writes to.
    private func makePopoverItemViews(_ item: PopoverModel.Item) -> (arranged: [NSView], updated: [NSView]) {
        switch item {
        case .source:
            let title = NSTextField(labelWithString: "")
            title.font = .systemFont(ofSize: 13, weight: .bold)
            let detail = NSTextField(labelWithString: "")
            detail.font = .systemFont(ofSize: 11, weight: .medium)
            let header = NSStackView(views: [title, NSView(), detail]); header.orientation = .horizontal
            header.translatesAutoresizingMaskIntoConstraints = false
            header.widthAnchor.constraint(equalToConstant: 296).isActive = true
            return ([header], [title, detail])
        case .usage(_, _, _, let bar):
            let caption = NSTextField(wrappingLabelWithString: "")
            caption.font = PopoverModel.Item.captionFont
            caption.maximumNumberOfLines = 2
            caption.cell?.truncatesLastVisibleLine = true
            caption.preferredMaxLayoutWidth = PopoverModel.Item.captionWidth
            caption.isSelectable = false
            guard bar != nil else { return ([caption], [caption]) }
            let barView = UsageBarView(width: PopoverModel.Item.captionWidth, height: 6, trackAlpha: 0.13)
            return ([caption, barView], [caption, barView])
        case .note:
            let caption = NSTextField(labelWithString: "")
            caption.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            return ([caption], [caption])
        case .gap:
            return ([spacer(6)], [])
        }
    }

    private func apply(_ item: PopoverModel.Item, to views: [NSView]) {
        switch item {
        case .source(let title, let detail):
            (views.first as? NSTextField)?.show(title, color: .white)
            (views.last as? NSTextField)?.show(detail, color: quietText(0.62))
        case .usage(let caption, let color, let toolTip, let bar):
            (views.first as? NSTextField)?.show(caption, color: color)
            views.first?.setToolTipIfChanged(toolTip)
            if let bar, let barView = views.last as? UsageBarView {
                barView.progress = bar.progress
                barView.accent = bar.accent
                barView.highContrast = prefersIncreasedContrast()
            }
        case .note(let text, let color):
            (views.first as? NSTextField)?.show(text, color: color)
        case .gap:
            break
        }
    }

    /// One place Claude usage comes from: plain `claude` (~/.claude) or an AI Island account.
    private struct ClaudeSource {
        let name: String
        let detail: String
        let fiveHour: CodexUsageWindow?
        let sevenDay: CodexUsageWindow?
        let updated: Double?
        let stale: Bool
    }

    private var claudeSources: [ClaudeSource] {
        func window(_ w: ClaudeRateLimitWindow?) -> CodexUsageWindow? {
            w.map { CodexUsageWindow(usedPercent: Int($0.usedPercent.rounded()), resetsAt: $0.resetsAt) }
        }
        var sources: [ClaudeSource] = []
        if claudeLoggedIn != false || claudeUsage != nil {
            sources.append(ClaudeSource(name: tr("Default"), detail: "claude · ~/.claude", fiveHour: window(claudeUsage?.fiveHour),
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

    /// The Claude source the island shows: the one in use now, else the active
    /// account, else plain `claude` (~/.claude).
    private var claudeIslandWindows: IslandWindows? {
        let sources = claudeSources
        let candidates = [currentClaudeSource,
                          claudeAccounts?.activeAccountName.flatMap { name in sources.first { $0.name == name } },
                          sources.first { $0.name == tr("Default") }]
        return candidates.lazy.compactMap { source in
            source.map { IslandWindows(fiveHour: $0.fiveHour.map { Double($0.usedPercent) },
                                       sevenDay: $0.sevenDay.map { Double($0.usedPercent) }) }
        }.first { $0.hasAny }
    }

    private var claudeUsageSummary: String? {
        let lines = claudeSources.map { source in
            let parts = [(tr("5H"), source.fiveHour), (tr("7D"), source.sevenDay)].compactMap { title, w in w.map { "\(title) \($0.usedPercent)%" } }
            return "\(source.name): " + (parts.isEmpty ? source.detail : parts.joined(separator: " · ")) + (source.name == currentClaudeSource?.name ? tr(" (now)") : "")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    /// Caption and bar per limit window. Without any known window the source
    /// gets one quiet line instead of a "not available" row per window.
    private func usageWindowItems(_ windows: [(title: String, window: CodexUsageWindow?)], accent: NSColor,
                                  suffix: String = "", loading: Bool = false) -> [PopoverModel.Item] {
        let quiet = quietText(0.55)
        guard windows.contains(where: { $0.window != nil }) else {
            return [.usage(caption: loading ? tr("Loading limits…") : tr("Limits not available yet"), color: quiet, toolTip: nil, bar: nil)]
        }
        return windows.map { title, window in
            guard let window else {
                return .usage(caption: tr("%@ · not available", title), color: quiet, toolTip: nil,
                              bar: PopoverModel.Bar(progress: 0.02, accent: accent.withAlphaComponent(0.45)))
            }
            var text = tr("%@ · %@% used", title, window.usedPercent)
            if let word = Self.levelWord(percent: Double(window.usedPercent)) { text += " · \(word)" }
            if let resetsAt = window.resetsAt {
                let left = ResetCountdown.text(until: resetsAt, now: Date().timeIntervalSince1970)
                // A wrapped caption keeps "3 kun 4 soat" together on one line.
                text += left == tr("now") ? tr(" · resets now") : tr(" · resets in %@", left.replacingOccurrences(of: " ", with: "\u{00A0}"))
            }
            return .usage(caption: text + suffix, color: accent.withAlphaComponent(0.94), toolTip: window.resetsAt.map(Self.resetTooltip),
                          bar: PopoverModel.Bar(progress: CGFloat(window.usedPercent) / 100,
                                                accent: usageColor(accent: accent, percent: Double(window.usedPercent))))
        }
    }

    /// The absolute reset time, with the date when it is not within the next day.
    static func resetTooltip(_ resetsAt: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: resetsAt)
        let formatter = DateFormatter()
        formatter.locale = Language.current.locale
        formatter.timeStyle = .short
        formatter.dateStyle = date.timeIntervalSinceNow > 86_400 ? .medium : .none
        return tr("Resets at %@", formatter.string(from: date))
    }

    /// Upgrades a Homebrew cask install with brew (`claude update` only prints the brew command),
    /// otherwise runs the CLI's own updater (npm or a native install).
    static let updateScript = """
    #!/bin/sh
    # AI Island: update Claude Code and Codex CLI.
    PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
    # Prints the Homebrew cask that owns the CLI, e.g. claude-code@latest.
    cask_of() {
      real=$(realpath "$(command -v "$1")" 2>/dev/null) || return 1
      case "$real" in
        */Caskroom/*/*) rest=${real#*/Caskroom/}; echo "${rest%%/*}" ;;
        *) return 1 ;;
      esac
    }
    for cli in claude codex; do
      echo
      if command -v "$cli" >/dev/null 2>&1; then
        echo "==> \(tr("Updating %@", "$cli")) ($("$cli" --version 2>/dev/null | head -1))"
        if cask=$(cask_of "$cli") && command -v brew >/dev/null 2>&1; then
          echo "    \(tr("via Homebrew: %@", "brew upgrade --cask $cask"))"
          brew upgrade --cask "$cask" || echo "\(tr("%@ update failed.", "$cli"))"
        else
          "$cli" update || echo "\(tr("%@ update failed.", "$cli"))"
        fi
        echo "==> \(tr("%@ is now %@", "$cli", #"$("$cli" --version 2>/dev/null | head -1)"#))"
      else
        echo "==> \(tr("%@ not found, skipped.", "$cli"))"
      fi
    done
    echo
    echo "\(tr("Done. You can close this window."))"
    """
    /// Regression hook: records the script instead of opening Terminal.
    var openUpdateScript: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    @objc private func updateCLIs() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-island-update.command")
        do {
            try Data(Self.updateScript.utf8).write(to: url, options: .atomic)
            chmod(url.path, 0o700)
            if !openUpdateScript(url) { presentConfigurationError(tr("Terminal could not open the update script.")) }
        } catch { presentConfigurationError(tr("Unable to prepare the CLI update.")) }
    }

    @objc private func refreshAndReopenPopover() {
        refreshInventory()
        refreshCodexUsage()
        refreshClaudeAuth()
    }

    @objc private func openSettingsFromPopover() {
        statusPopover.performClose(nil)
        // Let AppKit finish dismissing the application-defined popover before
        // activating a separate key window. Otherwise the popover can retain
        // key focus and make Settings appear not to open.
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
    }

    @objc private func closePopoverForFocusLoss() {
        statusPopover.performClose(nil)
    }

    private func installPopoverDismissMonitors() {
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handleLocalMouseDown(event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopoverAfterCurrentEvent()
            }
        }
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.window === island {
            islandOriginAtMouseDown = island.frame.origin
        }
        closePopoverForMouseEvent(event)
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
        appName.setContentCompressionResistancePriority(.required, for: .vertical)
        appName.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        appName.textColor = .secondaryLabelColor
        let appSubtitle = NSTextField(wrappingLabelWithString: tr("Global AI configuration"))
        appSubtitle.font = .systemFont(ofSize: 18, weight: .bold)
        appSubtitle.maximumNumberOfLines = 2
        sidebarStack.addArrangedSubview(appName)
        sidebarStack.addArrangedSubview(appSubtitle)
        let sidebarScroll = NSScrollView()
        sidebarScroll.documentView = settingsSidebar.table
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        sidebarStack.addArrangedSubview(sidebarScroll)
        // The source list fills the sidebar width between the insets.
        sidebarScroll.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor, constant: -32).isActive = true
        settingsSidebar.onSelect = { [weak self] area in
            guard let self, area != self.selectedSettingsArea else { return }
            self.selectedSettingsArea = area
            self.refreshSettingsPage()
        }
        settingsSidebar.table.reloadData()
        settingsSidebar.select(selectedSettingsArea)
        let safety = NSTextField(wrappingLabelWithString: Self.backupNote)
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
        window.title = tr("AI Island Settings")
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

    /// What actually happens on save and delete, shown under the Settings sidebar.
    static let backupNote = tr("Before AI Island saves or deletes a file, it copies the current version to ~/Library/Application Support/AI Island/Backups.")

    private func configureClaudeAccounts() {
        guard claudeAccounts == nil else { return }
        do {
            let controller = try ClaudeAccountsWindow()
            controller.onChange = { [weak self] in
                self?.updateUsageViews()
                self?.collapseIsland()
            }
            claudeAccounts = controller
        } catch { presentConfigurationError(tr("Unable to open Claude session storage.")) }
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
        settingsSidebar.select(selectedSettingsArea)
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
        case .overview: subtitle = tr("A single control center for your local AI tooling.")
        case .accounts: subtitle = tr("Claude accounts, their status and current usage.")
        case .codex: subtitle = tr("Global configuration discovered in ~/.codex")
        case .claude: subtitle = claudeLoggedIn == false ? tr("Claude is signed out and hidden from the island.") : tr("Global configuration discovered in ~/.claude")
        }
        let subheading = NSTextField(labelWithString: subtitle)
        subheading.font = .systemFont(ofSize: 14, weight: .medium)
        subheading.textColor = .secondaryLabelColor
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(subheading)
        if selectedSettingsArea == .accounts {
            for source in claudeSources {
                let row = accountSummaryRow(source)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
            }
            let manage = NSButton(title: tr("Manage Accounts & Sessions…"), target: self, action: #selector(openClaudeAccounts))
            manage.identifier = NSUserInterfaceItemIdentifier("accounts-manage")
            stack.addArrangedSubview(manage)
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
                    ? tr("%@ · visible on island", snapshot.stateText)
                    : tr("Signed out · hidden from island")
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

    /// One Claude account on the Accounts page: name, status and both usage windows.
    private func accountSummaryRow(_ source: ClaudeSource) -> NSView {
        let accent = accentColor(for: .claude)
        let row = NSView()
        row.identifier = NSUserInterfaceItemIdentifier("account-row")
        row.wantsLayer = true
        row.layer?.cornerRadius = 12
        row.layer?.backgroundColor = accent.withAlphaComponent(0.08).cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
        let name = NSTextField(labelWithString: source.name)
        name.font = .systemFont(ofSize: 14, weight: .bold)
        let detail = NSTextField(labelWithString: source.detail)
        detail.font = .systemFont(ofSize: 12, weight: .medium)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let windows = [(tr("5H"), source.fiveHour), (tr("7D"), source.sevenDay)].compactMap { title, window in
            window.map { "\(title) \($0.usedPercent)%" }
        }
        let usageText = windows.isEmpty ? tr("Usage unknown") : windows.joined(separator: " · ") + (source.stale ? tr(" · last known") : "")
        let usage = NSTextField(labelWithString: usageText)
        usage.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        usage.textColor = windows.isEmpty || source.stale ? .secondaryLabelColor : .labelColor
        usage.identifier = NSUserInterfaceItemIdentifier("account-usage")
        let labels = NSStackView(views: [name, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        for view in [labels, usage] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        row.setAccessibilityLabel("\(source.name), \(source.detail), \(usageText)")
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 58),
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: usage.leadingAnchor, constant: -12),
            usage.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            usage.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        usage.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func configurationCategories(for provider: Provider) -> [ConfigurationCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch provider {
        case .codex:
            let root = home.appendingPathComponent(".codex")
            return [
                // config.toml holds both settings and MCP servers, so it gets one card.
                .init(title: "Settings & MCP", detail: "config.toml · global behavior and MCP servers", symbol: "gearshape", paths: [root.appendingPathComponent("config.toml")]),
                .init(title: "Skills", detail: "Reusable task instructions", symbol: "wand.and.stars", paths: [root.appendingPathComponent("skills")]),
                .init(title: "Agents", detail: "Specialized agent definitions", symbol: "person.2", paths: [root.appendingPathComponent("agents")]),
                .init(title: "Rules", detail: "Always-on project rules", symbol: "checklist", paths: [root.appendingPathComponent("rules")]),
                .init(title: "Commands", detail: "Custom slash commands", symbol: "terminal", paths: [root.appendingPathComponent("commands")]),
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
        let files = managedFiles(in: category)
        let fileCount = files.count
        var status = fileCount == 0 ? tr("NOT CONFIGURED") : fileCount == 1 ? tr("%@ FILE", fileCount) : tr("%@ FILES", fileCount)
        if category.groupsSkills, fileCount > 0 {
            let skillCount = SkillTree(files: files).skills.count
            status = (skillCount == 1 ? tr("%@ SKILL", 1) : tr("%@ SKILLS", skillCount)) + " · " + status
        }
        let card = ConfigurationCardButton(title: "", target: self, action: #selector(openConfigurationCategory(_:)))
        card.identifier = NSUserInterfaceItemIdentifier("\(provider.rawValue)::\(category.title)")
        card.toolTip = tr("Click to manage %@", category.displayTitle)
        card.isBordered = false
        card.alignment = .left
        card.bezelStyle = .regularSquare
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = accent.withAlphaComponent(0.08).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
        card.heightAnchor.constraint(equalToConstant: 66).isActive = true

        let icon = NSImageView(image: NSImage(systemSymbolName: category.symbol, accessibilityDescription: category.displayTitle) ?? NSImage())
        icon.contentTintColor = accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: category.displayTitle)
        title.font = .systemFont(ofSize: 15, weight: .bold)
        let detail = NSTextField(labelWithString: tr(category.detail))
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
        button.toolTip = tr("Open %@ settings", provider.rawValue)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.wantsLayer = true
        button.layer?.cornerRadius = 14
        button.layer?.backgroundColor = accentColor(for: provider).withAlphaComponent(0.08).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = accentColor(for: provider).withAlphaComponent(0.28).cgColor
        button.heightAnchor.constraint(equalToConstant: 76).isActive = true
        button.setAccessibilityLabel(tr("Open %@ settings", area.title))

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
        let status = NSTextField(labelWithString: provider == .claude && claudeLoggedIn == false ? tr("HIDDEN") : tr("OPEN SETTINGS  ›"))
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
        guard resolveUnsavedConfigurationChanges() else {
            configurationWindow?.makeKeyAndOrderFront(nil)
            return
        }
        activeConfigurationCategory = category
        activeConfigurationFile = nil
        buildConfigurationWindowIfNeeded()
        configurationSearch?.stringValue = ""
        configurationWindow?.title = "\(provider.rawValue) · \(category.displayTitle)"
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
        let fileCount = NSTextField(labelWithString: tr("Files"))
        fileCount.font = .systemFont(ofSize: 12, weight: .semibold)
        fileCount.textColor = .secondaryLabelColor
        fileCount.translatesAutoresizingMaskIntoConstraints = false
        configurationFileCount = fileCount
        let newFile = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: tr("New file")) ?? NSImage(), target: self, action: #selector(createConfigurationFile))
        newFile.bezelStyle = .rounded
        newFile.toolTip = tr("Create a file in this category")
        newFile.widthAnchor.constraint(equalToConstant: 40).isActive = true
        newFile.heightAnchor.constraint(equalToConstant: 40).isActive = true
        configurationNewFileButton = newFile
        let listHeader = NSStackView(views: [fileCount, NSView(), newFile])
        listHeader.orientation = .horizontal
        listHeader.alignment = .centerY
        listHeader.translatesAutoresizingMaskIntoConstraints = false
        let search = NSSearchField()
        search.placeholderString = tr("Search files or skills")
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
        let table = ConfigurationFileTableView()
        table.onDisclosureKey = { [weak self] row, expand in self?.setSkillExpanded(expand, atRow: row) ?? false }
        table.target = self
        table.doubleAction = #selector(toggleSkillOnDoubleClick(_:))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.title = tr("Files")
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
        editor.delegate = self
        editorScroll.documentView = editor
        configurationEditor = editor

        let status = NSTextField(labelWithString: tr("Select a configuration file"))
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        configurationStatus = status
        status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let fileTitle = NSTextField(labelWithString: tr("Select a file"))
        fileTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        fileTitle.lineBreakMode = .byTruncatingMiddle
        fileTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let fileSubtitle = NSTextField(labelWithString: tr("Choose a file from the sidebar to edit"))
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
        let deleteFile = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: tr("Delete file")) ?? NSImage(), target: self, action: #selector(deleteConfigurationFile))
        deleteFile.bezelStyle = .rounded
        deleteFile.contentTintColor = .systemRed
        deleteFile.toolTip = tr("Delete selected file (confirmation required)")
        deleteFile.isEnabled = false
        deleteFile.widthAnchor.constraint(equalToConstant: 40).isActive = true
        deleteFile.heightAnchor.constraint(equalToConstant: 40).isActive = true
        configurationDeleteButton = deleteFile
        let save = NSButton(title: tr("Review & Save"), target: self, action: #selector(saveConfigurationFile))
        save.bezelStyle = .rounded
        save.contentTintColor = .controlAccentColor
        save.isEnabled = false
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = .command
        save.toolTip = tr("Review and save with a backup (⌘S)")
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
        window.delegate = self
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
        configurationSkillTree = activeConfigurationCategory?.groupsSkills == true ? SkillTree(files: allConfigurationFiles) : nil
        // Keep the open file visible when it sits inside a skill.
        if let file = activeConfigurationFile, let skill = configurationSkillTree?.skill(containing: file), file != skill.main {
            expandedSkillFolders.insert(skill.folder.path)
        }
        configurationNewFileButton?.isEnabled = activeConfigurationCategory?.paths.contains { $0.pathExtension.isEmpty } == true
        updateConfigurationFileList(selectFirst: true)
    }

    @objc private func filterConfigurationFiles() {
        updateConfigurationFileList(selectFirst: false)
    }

    private var configurationQuery: String {
        configurationSearch?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func updateConfigurationFileList(selectFirst: Bool) {
        guard let table = configurationTable else { return }
        let query = configurationQuery
        if let tree = configurationSkillTree {
            configurationRows = tree.rows(expanded: expandedSkillFolders, query: query, path: displayedFilePath)
            let shown = configurationRows.filter { if case .skill = $0.kind { true } else { false } }.count
            let files = tree.fileCount == 1 ? tr("%@ file", 1) : tr("%@ files", tree.fileCount)
            configurationFileCount?.stringValue = query.isEmpty
                ? (tree.skills.count == 1 ? tr("%@ skill", 1) : tr("%@ skills", tree.skills.count)) + " · " + files
                : tr("%@ of %@ skills", shown, tree.skills.count)
        } else {
            configurationRows = allConfigurationFiles
                .filter { query.isEmpty || displayedFilePath($0).localizedCaseInsensitiveContains(query) }
                .map { ConfigurationRow(file: $0, kind: .file) }
            configurationFileCount?.stringValue = query.isEmpty
                ? (configurationRows.count == 1 ? tr("%@ file", 1) : tr("%@ files", configurationRows.count))
                : tr("%@ of %@ files", configurationRows.count, allConfigurationFiles.count)
        }
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
            configurationSavedContent = nil
            configurationWindow?.isDocumentEdited = false
            configurationEditor?.string = ""
            configurationEditor?.isEditable = false
            configurationFileTitle?.stringValue = tr("No files yet")
            configurationFileSubtitle?.stringValue = tr("Create a file to configure this category")
            configurationStatus?.stringValue = tr("No configuration file selected")
            configurationSaveButton?.isEnabled = false
            configurationDeleteButton?.isEnabled = false
        }
    }

    /// Expands or collapses the skill on `row`. Returns false when the row is not a skill
    /// with files to show, or while a search decides which files are listed.
    @discardableResult
    private func setSkillExpanded(_ expand: Bool, atRow row: Int) -> Bool {
        guard configurationQuery.isEmpty, configurationRows.indices.contains(row),
              case .skill(let expanded, let fileCount) = configurationRows[row].kind, fileCount > 1,
              let folder = configurationRows[row].skillFolder else { return false }
        if expand != expanded {
            if expand { expandedSkillFolders.insert(folder.path) } else { expandedSkillFolders.remove(folder.path) }
            updateConfigurationFileList(selectFirst: false)
        }
        return true
    }

    @objc private func toggleSkillDisclosure(_ sender: NSButton) {
        guard let row = configurationTable?.row(for: sender), configurationRows.indices.contains(row),
              case .skill(let expanded, _) = configurationRows[row].kind else { return }
        setSkillExpanded(!expanded, atRow: row)
    }

    @objc private func toggleSkillOnDoubleClick(_ sender: NSTableView) {
        guard configurationRows.indices.contains(sender.clickedRow),
              case .skill(let expanded, _) = configurationRows[sender.clickedRow].kind else { return }
        setSkillExpanded(!expanded, atRow: sender.clickedRow)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        configurationRows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard tableView === configurationTable, configurationRows.indices.contains(row) else { return tableView.rowHeight }
        return configurationRows[row].kind == .attached ? 34 : 46
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard configurationRows.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("configuration-file-cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ConfigurationFileCell ?? {
            let cell = ConfigurationFileCell(frame: .zero)
            cell.identifier = identifier
            cell.disclosure.target = self
            cell.disclosure.action = #selector(toggleSkillDisclosure(_:))
            return cell
        }()
        let item = configurationRows[row]
        let grouped = configurationSkillTree != nil
        cell.disclosure.isHidden = true
        switch item.kind {
        case .skill(let expanded, let fileCount):
            let folder = item.skillFolder.map(displayedFilePath) ?? ""
            let parent = (folder as NSString).deletingLastPathComponent
            let count = fileCount == 1 ? tr("%@ file", 1) : tr("%@ files", fileCount)
            cell.configure(symbol: "wand.and.stars", title: item.file.deletingLastPathComponent().lastPathComponent,
                           path: parent.isEmpty ? count : "\(count) · \(parent)", grouped: true, depth: 0)
            if fileCount > 1, configurationQuery.isEmpty {
                cell.disclosure.isHidden = false
                cell.disclosure.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                                                accessibilityDescription: expanded ? tr("Collapse") : tr("Expand"))
                cell.disclosure.toolTip = expanded ? tr("Hide this skill's files") : tr("Show this skill's files")
            }
        case .attached:
            let inside = item.skillFolder.map { String(item.file.path.dropFirst($0.path.count + 1)) } ?? item.file.lastPathComponent
            cell.configure(symbol: "doc.text", title: item.file.lastPathComponent,
                           path: (inside as NSString).deletingLastPathComponent, grouped: true, depth: 1)
        case .file:
            cell.configure(symbol: "doc.text", title: item.file.lastPathComponent, path: displayedFilePath(item.file),
                           grouped: grouped, depth: 0)
        }
        cell.toolTip = item.file.path
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard tableView === configurationTable, !isUpdatingConfigurationTable,
              configurationFiles.indices.contains(row),
              configurationFiles[row].path != activeConfigurationFile?.path else { return true }
        return resolveUnsavedConfigurationChanges()
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === configurationEditor else { return }
        updateConfigurationEditedState()
    }

    private var hasUnsavedConfigurationChanges: Bool {
        activeConfigurationFile != nil && configurationEditor?.string != configurationSavedContent
    }

    private func configurationSummary(for file: URL, content: String) -> String {
        tr("%@ · %@ lines · UTF-8", file.pathExtension.uppercased(), content.components(separatedBy: "\n").count)
    }

    private func updateConfigurationEditedState() {
        let edited = hasUnsavedConfigurationChanges
        configurationWindow?.isDocumentEdited = edited
        if edited {
            configurationStatus?.stringValue = tr("Edited · unsaved changes · ⌘S to review and save")
        } else if configurationStatus?.stringValue.hasPrefix(tr("Edited")) == true,
                  let file = activeConfigurationFile, let saved = configurationSavedContent {
            configurationStatus?.stringValue = configurationSummary(for: file, content: saved)
        }
    }

    /// Asks before an action would replace unsaved editor text. Returns false
    /// when the user cancels, leaving the selection and the draft untouched.
    private func resolveUnsavedConfigurationChanges() -> Bool {
        guard hasUnsavedConfigurationChanges, let file = activeConfigurationFile else { return true }
        switch askAboutUnsavedConfiguration(file) {
        case .save:
            return saveActiveConfigurationFile()
        case .discard:
            configurationEditor?.string = configurationSavedContent ?? ""
            updateConfigurationEditedState()
            return true
        case .cancel:
            return false
        }
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
            configurationEditor?.string = tr("This file cannot be displayed as editable UTF-8 text.")
            configurationEditor?.isEditable = false
            configurationStatus?.stringValue = tr("Read-only · this file is not editable UTF-8 text")
            configurationSaveButton?.isEnabled = false
            configurationDeleteButton?.isEnabled = false
            activeConfigurationFile = nil
            configurationSavedContent = nil
            configurationWindow?.isDocumentEdited = false
            return
        }
        activeConfigurationFile = file
        configurationSavedContent = content
        configurationWindow?.isDocumentEdited = false
        configurationEditor?.string = content
        configurationEditor?.isEditable = true
        configurationStatus?.stringValue = configurationSummary(for: file, content: content)
        configurationSaveButton?.isEnabled = true
        configurationDeleteButton?.isEnabled = true
    }

    @objc private func createConfigurationFile() {
        guard let category = activeConfigurationCategory,
              category.paths.contains(where: { $0.pathExtension.isEmpty }) else {
            presentConfigurationError(tr("New files can only be created inside a managed Skills, Agents, Rules, Commands, or Hooks folder."))
            return
        }
        guard resolveUnsavedConfigurationChanges() else { return }
        let root = writableConfigurationRoot(for: category)
        let alert = NSAlert()
        let nameField = NSTextField(string: "new-item.md")
        if category.groupsSkills {
            alert.messageText = tr("New skill or skill file")
            alert.informativeText = tr("Type a skill name such as backend-style to create backend-style/SKILL.md, or a path such as backend-style/references/algorithms.md to add a file to a skill. Skill names use lowercase letters, numbers, and dashes.")
            let selected = activeConfigurationFile.flatMap { configurationSkillTree?.skill(containing: $0) }
            nameField.stringValue = selected.map { "\(displayedFilePath($0.main).dropLast(SkillTree.mainFileName.count))references/new-file.md" } ?? "my-skill"
        } else {
            alert.messageText = tr("New %@ file", category.displayTitle)
            alert.informativeText = tr("Use letters, numbers, dots, underscores, or dashes. The file remains inside this configuration category.")
        }
        alert.addButton(withTitle: tr("Create"))
        alert.addButton(withTitle: tr("Cancel"))
        nameField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let relativePath = category.groupsSkills
            ? SkillTree.newItemPath(input)
            : input.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression).map { _ in input }
        guard let relativePath else {
            presentConfigurationError(tr("“%@” is not a valid name for this category.", input))
            return
        }
        let file = root.appendingPathComponent(relativePath)
        guard isManagedConfigurationFile(file) else { return }
        guard !FileManager.default.fileExists(atPath: file.path) else {
            presentConfigurationError(tr("%@ already exists.", relativePath))
            return
        }
        let isNewSkill = file.lastPathComponent == SkillTree.mainFileName && category.groupsSkills
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let content = isNewSkill ? SkillTree.template(name: file.deletingLastPathComponent().lastPathComponent) : "# \(file.lastPathComponent)\n"
            try content.write(to: file, atomically: true, encoding: .utf8)
            // Refreshing selects the active file, expanding its skill when needed.
            activeConfigurationFile = file
            refreshConfigurationFiles()
            refreshInventory()
        } catch {
            presentConfigurationError(tr("Could not create the file."))
        }
    }

    @objc private func saveConfigurationFile() {
        saveActiveConfigurationFile()
    }

    /// Review + backup save flow. Returns true only when the editor text is on disk.
    @discardableResult
    private func saveActiveConfigurationFile() -> Bool {
        guard let file = activeConfigurationFile,
              let editor = configurationEditor,
              isManagedConfigurationFile(file) else { return false }
        let oldContent = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let newContent = editor.string
        guard oldContent != newContent else {
            configurationSavedContent = newContent
            updateConfigurationEditedState()
            return true
        }
        if let error = ConfigurationSyntax.validate(newContent, pathExtension: file.pathExtension) {
            let location = NSRange(location: min(error.offset, (newContent as NSString).length), length: 0)
            editor.setSelectedRange(location)
            editor.scrollRangeToVisible(location)
            configurationStatus?.stringValue = tr("Syntax error · %@", error)
            // JSON readers reject any error outright; the TOML check is structural, so it only warns.
            let canOverride = file.pathExtension.lowercased() == "toml"
            guard presentConfigurationSyntaxProblem(error, file, canOverride), canOverride else { return false }
        }
        guard confirmConfigurationSave(LineDiff(old: oldContent, new: newContent)) else { return false }
        do {
            try backupConfigurationFile(file)
            try newContent.write(to: file, atomically: true, encoding: .utf8)
            configurationSavedContent = newContent
            configurationStatus?.stringValue = tr("Saved with backup · %@", file.path)
            updateConfigurationEditedState()
            refreshInventory()
            return true
        } catch {
            presentConfigurationError(tr("Could not save this file. The original was not replaced."))
            return false
        }
    }

    @objc private func deleteConfigurationFile() {
        guard let file = activeConfigurationFile, isManagedConfigurationFile(file) else { return }
        let alert = NSAlert()
        alert.messageText = tr("Delete %@?", file.lastPathComponent)
        alert.informativeText = tr("A backup will be saved first. This cannot be undone from AI Island.")
        alert.addButton(withTitle: tr("Delete with backup"))
        alert.addButton(withTitle: tr("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try backupConfigurationFile(file)
            try FileManager.default.removeItem(at: file)
            refreshConfigurationFiles()
            refreshInventory()
        } catch {
            presentConfigurationError(tr("Could not delete this file."))
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

    private func presentConfigurationError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: tr("OK"))
        alert.runModal()
    }
}

if SessionManager.handleCommandLine() { exit(0) }

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
