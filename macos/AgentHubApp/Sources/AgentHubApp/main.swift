import AppKit
import UniformTypeIdentifiers
@preconcurrency import UserNotifications
import WebKit

private let nativePasteEventName = "agent-hub-native-paste-files"
private let maxNativePasteFileBytes = 25 * 1024 * 1024

private struct AppConfig {
    let appURL: URL
    let healthURL: URL
    let repositoryPath: String?

    static func load() -> AppConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        let environment = ProcessInfo.processInfo.environment
        let rawURL = environment["AGENT_HUB_APP_URL"]
            ?? info["AgentHubURL"] as? String
            ?? "http://127.0.0.1:8700"
        let appURL = URL(string: rawURL) ?? URL(string: "http://127.0.0.1:8700")!
        var healthComponents = URLComponents(url: appURL, resolvingAgainstBaseURL: false)
        healthComponents?.path = "/api/health"
        healthComponents?.query = nil
        healthComponents?.fragment = nil
        let healthURL = healthComponents?.url ?? URL(string: "http://127.0.0.1:8700/api/health")!
        return AppConfig(
            appURL: appURL,
            healthURL: healthURL,
            repositoryPath: info["AgentHubRepositoryPath"] as? String
        )
    }

    var installCommand: String {
        guard let repositoryPath, !repositoryPath.isEmpty else {
            return "cd /path/to/agent-hub && make install"
        }
        return "cd \(shellQuote(repositoryPath)) && make install"
    }

    var statusCommand: String {
        guard let repositoryPath, !repositoryPath.isEmpty else {
            return "cd /path/to/agent-hub && make status"
        }
        return "cd \(shellQuote(repositoryPath)) && make status"
    }

    var logDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("agent-hub")
    }
}

private func shellQuote(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "$", with: "\\$")
        .replacingOccurrences(of: "`", with: "\\`") + "\""
}

@MainActor
private protocol NativePasteHandling: AnyObject {
    func pasteNativeClipboardFiles() -> Bool
}

private final class AgentHubWebView: WKWebView {
    weak var nativePasteHandler: NativePasteHandling?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            if nativePasteHandler?.pasteNativeClipboardFiles() == true {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct NativePasteFile {
    let name: String
    let type: String
    let data: Data

    var payload: [String: String] {
        [
            "name": name,
            "type": type,
            "dataBase64": data.base64EncodedString(),
        ]
    }
}

private enum BackendState: Equatable {
    case checking
    case online
    case offline(String)
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate,
    NativePasteHandling, UNUserNotificationCenterDelegate
{
    private let config = AppConfig.load()
    private var window: NSWindow!
    private var webView: AgentHubWebView!
    private var offlineView: NSView!
    private var titleLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var commandField: NSTextField!
    private var healthTask: URLSessionDataTask?
    private var pasteEventMonitor: Any?
    private var statusItem: NSStatusItem!
    private var statusTitleItem: NSMenuItem!
    private var showHideItem: NSMenuItem!
    private var lastBackendState: BackendState = .checking

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()
        installNotifications()
        buildWindow()
        installPasteMonitor()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        checkBackend()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let pasteEventMonitor {
            NSEvent.removeMonitor(pasteEventMonitor)
        }
    }

    func windowWillClose(_ notification: Notification) {
        updateShowHideTitle()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showOffline(
            title: "Agent Hub ochilmadi",
            detail: "WebView sahifani yuklay olmadi: \(error.localizedDescription)"
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        showOffline(
            title: "Agent Hub ochilmadi",
            detail: "Backend sahifasiga ulanib bo‘lmadi: \(error.localizedDescription)"
        )
    }

    private func buildWindow() {
        let contentView = NSView()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        webView = AgentHubWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.nativePasteHandler = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false

        offlineView = buildOfflineView()
        offlineView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(webView)
        contentView.addSubview(offlineView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            offlineView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            offlineView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            offlineView.topAnchor.constraint(equalTo: contentView.topAnchor),
            offlineView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Hub"
        window.minSize = NSSize(width: 960, height: 640)
        window.contentView = contentView
        window.delegate = self
        window.center()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Agent Hub")
        appMenu.addItem(NSMenuItem(title: "Agent Hubni ko‘rsatish", action: #selector(showWindow), keyEquivalent: "0"))
        appMenu.addItem(NSMenuItem(title: "Agent Hubni yashirish", action: #selector(hideWindow), keyEquivalent: "w"))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Statusni tekshirish", action: #selector(retry), keyEquivalent: "r"))
        appMenu.addItem(NSMenuItem(title: "Brauzerda ochish", action: #selector(openInBrowser), keyEquivalent: "b"))
        appMenu.addItem(NSMenuItem(title: "Log papkasini ochish", action: #selector(openLogs), keyEquivalent: "l"))
        appMenu.addItem(
            NSMenuItem(title: "Servislarni yangilash/restart…", action: #selector(restartServices), keyEquivalent: "")
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "AgentHubdan chiqish",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        )
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Agent Hub"
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.connected.to.line.below",
            accessibilityDescription: "Agent Hub"
        )

        let menu = NSMenu(title: "Agent Hub")
        statusTitleItem = NSMenuItem(title: "Agent Hub: tekshirilmoqda…", action: nil, keyEquivalent: "")
        statusTitleItem.isEnabled = false
        menu.addItem(statusTitleItem)
        menu.addItem(NSMenuItem.separator())

        showHideItem = NSMenuItem(title: "Oynani ko‘rsatish", action: #selector(toggleWindow), keyEquivalent: "")
        menu.addItem(showHideItem)
        menu.addItem(NSMenuItem(title: "Statusni tekshirish", action: #selector(retry), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Brauzerda ochish", action: #selector(openInBrowser), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Log papkasini ochish", action: #selector(openLogs), keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(title: "Servislarni yangilash/restart…", action: #selector(restartServices), keyEquivalent: "")
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Install buyrug‘ini nusxalash", action: #selector(copyCommand), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Chiqish", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = menu
        updateStatusItem(state: .checking)
    }

    private func installNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    private func installPasteMonitor() {
        pasteEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" else {
                return event
            }
            if self?.pasteNativeClipboardFiles() == true {
                return nil
            }
            return event
        }
    }

    private func buildOfflineView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel = NSTextField(labelWithString: "Agent Hub tekshirilmoqda…")
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        titleLabel.maximumNumberOfLines = 0

        detailLabel = NSTextField(wrappingLabelWithString: "")
        detailLabel.font = .systemFont(ofSize: 15)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 0

        commandField = NSTextField(labelWithString: config.installCommand)
        commandField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        commandField.textColor = .secondaryLabelColor
        commandField.maximumNumberOfLines = 0

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 10
        buttonStack.addArrangedSubview(makeButton("Qayta urinish", action: #selector(retry)))
        buttonStack.addArrangedSubview(makeButton("Brauzerda ochish", action: #selector(openInBrowser)))
        buttonStack.addArrangedSubview(makeButton("Buyruqni nusxalash", action: #selector(copyCommand)))

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(detailLabel)
        stack.addArrangedSubview(commandField)
        stack.addArrangedSubview(buttonStack)
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 56),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -56),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
        ])

        return root
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        return button
    }

    @objc private func showWindow() {
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        updateShowHideTitle()
    }

    @objc private func hideWindow() {
        window.orderOut(nil)
        updateShowHideTitle()
    }

    @objc private func toggleWindow() {
        if window.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    @objc private func retry() {
        showWindow()
        checkBackend()
    }

    @objc private func openInBrowser() {
        NSWorkspace.shared.open(config.appURL)
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(config.logDirectoryURL)
    }

    @objc private func restartServices() {
        runCommandInTerminal(config.installCommand)
        notify(
            title: "Agent Hub servis restart",
            body: "Terminalda `make install` ochildi. Buyruq launchd servislarini xavfsiz yangilaydi."
        )
    }

    @objc private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config.installCommand, forType: .string)
        detailLabel.stringValue = "Buyruq nusxalandi. Terminalda ishga tushirib, keyin qayta urinib ko‘ring."
    }

    private func runCommandInTerminal(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script \(String(reflecting: command))
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
        if error != nil {
            copyCommand()
        }
    }

    private func checkBackend() {
        healthTask?.cancel()
        updateStatusItem(state: .checking)
        titleLabel.stringValue = "Agent Hub tekshirilmoqda…"
        detailLabel.stringValue = "Backend health endpoint so‘ralmoqda: \(config.healthURL.absoluteString)"
        commandField.stringValue = config.installCommand
        offlineView.isHidden = false
        webView.isHidden = true

        var request = URLRequest(url: config.healthURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 2.5
        healthTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleHealth(data: data, response: response, error: error)
            }
        }
        healthTask?.resume()
    }

    private func handleHealth(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            updateStatusItem(state: .offline(error.localizedDescription))
            showOffline(
                title: "Agent Hub backend ishlamayapti",
                detail: "Terminalda quyidagi buyruqni ishga tushiring yoki mavjud servislarni tekshiring."
                    + "\n\nXato: \(error.localizedDescription)"
            )
            return
        }

        guard let http = response as? HTTPURLResponse else {
            updateStatusItem(state: .offline("HTTP javob yo‘q"))
            showOffline(title: "Agent Hub javobi noma’lum", detail: "Health endpoint HTTP javob qaytarmadi.")
            return
        }
        guard http.statusCode == 200 else {
            updateStatusItem(state: .offline("HTTP \(http.statusCode)"))
            showOffline(
                title: "Agent Hub health xato qaytardi",
                detail: "Health endpoint HTTP \(http.statusCode) qaytardi. Terminalda statusni tekshiring."
            )
            return
        }
        if let data,
           let object = try? JSONSerialization.jsonObject(with: data),
           let json = object as? [String: Any],
           let ok = json["ok"] as? Bool,
           !ok {
            updateStatusItem(state: .offline("health ok=false"))
            showOffline(
                title: "Agent Hub health ok emas",
                detail: "Backend javob berdi, lekin health ok=false. Terminalda make status bilan sababini ko‘ring."
            )
            return
        }
        updateStatusItem(state: .online)
        loadAgentHub()
    }

    private func loadAgentHub() {
        offlineView.isHidden = true
        webView.isHidden = false
        if webView.url?.absoluteString != config.appURL.absoluteString {
            webView.load(URLRequest(url: config.appURL))
        }
    }

    private func showOffline(title: String, detail: String) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        commandField.stringValue = config.installCommand
        offlineView.isHidden = false
        webView.isHidden = true
    }

    private func updateStatusItem(state: BackendState) {
        switch state {
        case .checking:
            statusTitleItem?.title = "Agent Hub: tekshirilmoqda…"
            statusItem?.button?.title = "Agent Hub"
        case .online:
            statusTitleItem?.title = "Agent Hub: online"
            statusItem?.button?.title = "Agent Hub ✓"
        case let .offline(reason):
            statusTitleItem?.title = "Agent Hub: offline — \(reason)"
            statusItem?.button?.title = "Agent Hub !"
        }
        updateShowHideTitle()
        notifyIfBackendStateChanged(to: state)
        lastBackendState = state
    }

    private func updateShowHideTitle() {
        showHideItem?.title = window?.isVisible == true ? "Oynani yashirish" : "Oynani ko‘rsatish"
    }

    private func notifyIfBackendStateChanged(to state: BackendState) {
        guard state != lastBackendState else {
            return
        }
        switch (lastBackendState, state) {
        case (_, .offline(let reason)):
            notify(title: "Agent Hub offline", body: reason)
        case (.offline, .online):
            notify(title: "Agent Hub online", body: "Backend health qayta tiklandi.")
        default:
            break
        }
    }

    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Self.deliverNotification(title: title, body: body)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        Self.deliverNotification(title: title, body: body)
                    }
                }
            default:
                break
            }
        }
    }

    private nonisolated static func deliverNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "agent-hub-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func pasteNativeClipboardFiles() -> Bool {
        let pasteboard = NSPasteboard.general
        let files = collectNativePasteFiles(from: pasteboard)
        if files.isEmpty {
            return pasteboardContainsFileLikeData(pasteboard)
        }
        injectNativePaste(files)
        return true
    }

    private func collectNativePasteFiles(from pasteboard: NSPasteboard) -> [NativePasteFile] {
        var files: [NativePasteFile] = []
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        for url in urls where url.isFileURL {
            if let file = nativePasteFile(from: url) {
                files.append(file)
            }
        }
        if files.isEmpty, let image = NSImage(pasteboard: pasteboard), let data = image.pngData() {
            files.append(
                NativePasteFile(name: "clipboard-\(Int(Date().timeIntervalSince1970)).png", type: "image/png", data: data)
            )
        }
        return files
    }

    private func nativePasteFile(from url: URL) -> NativePasteFile? {
        guard
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true,
            let size = values.fileSize,
            size <= maxNativePasteFileBytes,
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        let name = url.lastPathComponent.isEmpty ? "clipboard-file" : url.lastPathComponent
        return NativePasteFile(name: name, type: mimeType(for: url), data: data)
    }

    private func mimeType(for url: URL) -> String {
        guard
            let type = UTType(filenameExtension: url.pathExtension),
            let mime = type.preferredMIMEType
        else {
            return "application/octet-stream"
        }
        return mime
    }

    private func pasteboardContainsFileLikeData(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(.fileURL) || types.contains(.tiff) || types.contains(.png)
    }

    private func injectNativePaste(_ files: [NativePasteFile]) {
        let payload: [String: [[String: String]]] = ["files": files.map(\.payload)]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        let script = """
        window.dispatchEvent(new CustomEvent(\(String(reflecting: nativePasteEventName)), { detail: \(json) }));
        """
        webView.evaluateJavaScript(script)
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard
            let tiff = tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
