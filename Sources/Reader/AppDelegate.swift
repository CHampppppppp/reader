import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, WKNavigationDelegate, WKUIDelegate {
    private let preferences = Preferences()
    private let hotKey = GlobalHotKey()
    private var panel: ReadingPanel!
    private var webView: TransparentWebView!
    private var statusItem: NSStatusItem!
    private var addressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var statusMenuItem: NSMenuItem?
    private var pageStatus = "轻读" {
        didSet { statusMenuItem?.title = pageStatus }
    }
    private var appearanceTemplate: String?
    private var previousApp: NSRunningApplication?
    private var appMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appearanceTemplate = Bundle.main.url(forResource: "appearance", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        buildWindow()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: "轻读")
        hotKey.onPress = { [weak self] in self?.toggleWindow() }
        let registration = hotKey.register(Shortcut.choices[preferences.shortcutIndex])
        if registration != noErr { preferences.hideMenuIcon = false }
        refreshMenu()
        webView.load(URLRequest(url: preferences.lastURL))
        showWindow()
        var startupIssues: [String] = []
        if registration != noErr {
            startupIssues.append("快捷键注册失败，可能与其他应用冲突（错误码 \(registration)）。请在设置菜单中选择另一个快捷键。菜单栏入口已保留。")
        }
        if appearanceTemplate == nil {
            startupIssues.append("缺少外观资源，请通过 scripts/build-app.sh 构建并打开生成的 app。当前可正常浏览网页，但透明阅读样式不可用。")
        }
        if !webView.backgroundTransparencyAvailable {
            startupIssues.append("当前系统的 WebKit 背景接口不可用，阅读功能可继续使用，但无法去除底层背景。")
        }
        if !startupIssues.isEmpty { message("启动提示", startupIssues.joined(separator: "\n\n")) }
    }

    private func buildWindow() {
        panel = ReadingPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 740),
                             styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.title = "轻读"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: 360, height: 320)
        panel.delegate = self
        panel.center()
        panel.setFrameAutosaveName("ReadingPanel")
        ensureVisibleFrame()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = TransparentWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityLabel("微信读书网页")
        webView.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = 9
        content.layer?.masksToBounds = true
        panel.contentView = content
        content.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        addressObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            guard let self, let url = view.url else { return }
            self.preferences.remember(url)
            self.applyReadingScale()
        }
        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            guard let self else { return }
            if view.isLoading {
                self.pageStatus = "正在加载…"
            } else {
                self.pageStatus = "轻读 · \(Shortcut.choices[self.preferences.shortcutIndex].label) 隐藏"
            }
        }
        applyAppearance()
    }

    private func ensureVisibleFrame() {
        let screens = NSScreen.screens
        let screen = screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        var frame = panel.frame
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        frame.origin.x = max(area.minX, min(frame.minX, area.maxX - frame.width))
        frame.origin.y = max(area.minY, min(frame.minY, area.maxY - frame.height))
        panel.setFrame(frame, display: true)
    }

    @objc private func toggleWindow() {
        if panel.isVisible { hideWindow() } else { showWindow() }
    }

    private func showWindow() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        ensureVisibleFrame()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
        refreshMenu()
    }

    @objc private func hideWindow() {
        WindowVisibility.hide(panel)
        appMenu?.cancelTrackingWithoutAnimation()
        if let sheet = panel.attachedSheet { panel.endSheet(sheet, returnCode: .abort) }
        if NSApp.isActive { previousApp?.activate(options: []) }
        refreshMenu()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hideWindow(); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopening the app from Finder is the escape hatch if the menu icon is disabled.
        preferences.hideMenuIcon = false
        showWindow()
        return false
    }

    @objc private func goHome() { webView.load(URLRequest(url: ReaderPolicy.home)) }
    @objc private func goBack() { if webView.canGoBack { webView.goBack() } }
    @objc private func reloadPage() { webView.reload() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openSettings(_ sender: Any?) {
        refreshMenu()
        appMenu.popUp(positioning: nil, at: NSPoint(x: 16, y: webView.bounds.maxY - 16), in: webView)
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.state = checked ? .on : .off
        return item
    }

    private func refreshMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let status = NSMenuItem(title: pageStatus, action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(item(panel.isVisible ? "隐藏窗口  \(Shortcut.choices[preferences.shortcutIndex].label)" : "显示窗口  \(Shortcut.choices[preferences.shortcutIndex].label)", #selector(toggleWindow)))
        menu.addItem(.separator())
        menu.addItem(item("透明阅读背景", #selector(toggleTransparency), checked: preferences.transparent))
        let background = NSMenuItem(title: "阅读背景不透明度", action: nil, keyEquivalent: "")
        let backgroundMenu = NSMenu()
        for value in [0, 15, 35, 55, 72, 90, 100] {
            backgroundMenu.addItem(item("\(value)%", #selector(changeBackground(_:)), tag: value,
                                        checked: Int((preferences.backgroundOpacity * 100).rounded()) == value))
        }
        background.submenu = backgroundMenu
        menu.addItem(background)
        let opacity = NSMenuItem(title: "整个窗口不透明度（含文字）", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for value in [25, 40, 60, 80, 100] {
            opacityMenu.addItem(item("\(value)%", #selector(changeWindowOpacity(_:)), tag: value,
                                     checked: Int((preferences.windowOpacity * 100).rounded()) == value))
        }
        opacity.submenu = opacityMenu
        menu.addItem(opacity)
        menu.addItem(item("恢复易读外观", #selector(resetAppearance)))
        menu.addItem(.separator())
        let shortcut = NSMenuItem(title: "全局快捷键", action: nil, keyEquivalent: "")
        let shortcutMenu = NSMenu()
        for (index, value) in Shortcut.choices.enumerated() {
            shortcutMenu.addItem(item(value.label, #selector(changeShortcut(_:)), tag: index, checked: preferences.shortcutIndex == index))
        }
        shortcut.submenu = shortcutMenu
        menu.addItem(shortcut)
        let hideIcon = item("隐藏菜单栏图标", #selector(toggleMenuIcon), checked: preferences.hideMenuIcon)
        hideIcon.isEnabled = hotKey.isRegistered
        menu.addItem(hideIcon)
        menu.addItem(.separator())
        menu.addItem(item("回到微信读书首页", #selector(goHome)))
        let back = item("后退", #selector(goBack))
        back.isEnabled = webView.canGoBack
        menu.addItem(back)
        menu.addItem(item("重新加载（⌘R）", #selector(reloadPage)))
        menu.addItem(item("使用说明", #selector(showHelp)))
        menu.addItem(item("退出轻读", #selector(quit)))
        appMenu = menu
        statusItem.menu = menu
        statusItem.isVisible = !preferences.hideMenuIcon || !hotKey.isRegistered
        installApplicationMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(goBack) }?.isEnabled = webView.canGoBack
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let application = NSMenu()
        let quitItem = item("退出轻读", #selector(quit)); quitItem.keyEquivalent = "q"
        application.addItem(quitItem)
        applicationItem.submenu = application
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"),
                                       ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
                                       ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        let viewItem = NSMenuItem()
        let view = NSMenu(title: "阅读")
        let settings = item("设置", #selector(openSettings(_:))); settings.keyEquivalent = ","
        let hideItem = item("隐藏", #selector(hideWindow)); hideItem.keyEquivalent = "w"
        let refresh = item("重新加载", #selector(reloadPage)); refresh.keyEquivalent = "r"
        [settings, hideItem, refresh].forEach { view.addItem($0) }
        viewItem.submenu = view
        main.addItem(viewItem)
        NSApp.mainMenu = main
    }

    @objc private func toggleTransparency() { preferences.transparent.toggle(); applyAppearance(); refreshMenu() }
    @objc private func changeBackground(_ sender: NSMenuItem) {
        preferences.backgroundOpacity = Double(sender.tag) / 100
        preferences.transparent = true
        applyAppearance(); refreshMenu()
    }
    @objc private func changeWindowOpacity(_ sender: NSMenuItem) {
        preferences.windowOpacity = Double(sender.tag) / 100
        applyAppearance(); refreshMenu()
    }
    @objc private func resetAppearance() {
        preferences.transparent = false
        preferences.windowOpacity = 1
        applyAppearance(); refreshMenu()
    }
    @objc private func changeShortcut(_ sender: NSMenuItem) {
        guard sender.tag != preferences.shortcutIndex || !hotKey.isRegistered else { return }
        let status = hotKey.register(Shortcut.choices[sender.tag])
        if status == noErr {
            preferences.shortcutIndex = sender.tag
            pageStatus = "轻读 · \(Shortcut.choices[sender.tag].label) 隐藏"
            refreshMenu()
        } else {
            showWindow()
            let recovery = hotKey.isRegistered ? "之前的快捷键仍然有效。" : "当前没有可用的全局快捷键，菜单栏入口已保留。"
            message("无法使用这个快捷键", "可能已被其他应用占用（错误码 \(status)）。\(recovery)请选择另一个组合。")
        }
    }
    @objc private func toggleMenuIcon() {
        guard hotKey.isRegistered else { return }
        preferences.hideMenuIcon.toggle()
        refreshMenu()
    }

    private func applyReadingScale() {
        let zoom = ReaderPolicy.pageZoom(for: webView.url)
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
    }

    private func applyAppearance() {
        panel.alphaValue = preferences.windowOpacity
        applyReadingScale()
        guard let appearanceTemplate else { return }
        let source = appearanceTemplate.replacingOccurrences(of: "__READER_SETTINGS__", with:
            "{transparent: \(preferences.transparent), opacity: \(preferences.backgroundOpacity)}")
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        guard let url = webView.url, ReaderPolicy.isWeRead(url) else { return }
        webView.evaluateJavaScript(source) { [weak self] _, error in
            if error != nil { self?.pageStatus = "外观未应用，重新加载或恢复易读外观" }
        }
    }

    @objc private func showHelp() {
        showWindow()
        message("轻读", "登录后直接使用微信读书网页，进度和笔记由网页同步。\n\n全局 \(Shortcut.choices[preferences.shortcutIndex].label)：隐藏／恢复\n⌘W：隐藏　⌘,：设置　⌘R：刷新\n按住 Option 拖动阅读区移动窗口，拖动窗口边缘缩放。设置自动保存，重启后继续沿用。\n\n背景透明只适配阅读页；书架、登录框保留原样。某些画布阅读模式可能仍有底色，可调整整个窗口不透明度或恢复易读外观。\n\n隐藏菜单图标后，再次从 Finder 打开 app 可恢复入口。应用进程仍会出现在活动监视器中。")
    }

    private func message(_ title: String, _ text: String) {
        guard panel.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "知道了")
        alert.beginSheetModal(for: panel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyAppearance()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadingFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadingFailed(error) }
    private func loadingFailed(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        pageStatus = "加载失败，请检查网络后按 ⌘R 刷新"
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageStatus = "网页进程已停止，请按 ⌘R 刷新"
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "https" || url.absoluteString == "about:blank" { decisionHandler(.allow) }
        else {
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame != false {
                pageStatus = "该链接无法在此打开，请使用网页扫码登录"
            }
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Keep website links in the one panel, so hiding cannot leave a popup visible.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, url.scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard panel.isVisible, panel.attachedSheet == nil else { completionHandler(); return }
        let alert = NSAlert()
        alert.messageText = "网页提示"
        alert.informativeText = message
        alert.beginSheetModal(for: panel) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard panel.isVisible, panel.attachedSheet == nil else { completionHandler(false); return }
        let alert = NSAlert()
        alert.messageText = "网页确认"
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: panel) { result in completionHandler(result == .alertFirstButtonReturn) }
    }
}
