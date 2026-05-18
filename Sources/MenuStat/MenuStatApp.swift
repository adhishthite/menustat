import AppKit
import Combine
import ServiceManagement
import SwiftUI

private var retainedAppDelegate: MenuStatAppDelegate?

@main
struct MenuStatApp {
    static func main() {
        if CommandLine.arguments.contains("--probe-fans") {
            let fans = SMCFanReader().readFans()
            print("status=\(fans.statusTitle)")
            print("source=\(fans.source)")
            print("speeds=\(fans.speeds)")
            print("minSpeeds=\(fans.minSpeeds)")
            print("maxSpeeds=\(fans.maxSpeeds)")
            print("rangePercent=\(fans.percentTitle)")
            print("detail=\(fans.detail)")
            print("attemptedKeys=\(fans.attemptedKeys.joined(separator: ","))")
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = MenuStatAppDelegate()
        retainedAppDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class MenuStatAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let sampler = SystemSampler()
    private let displayPreferences = DisplayPreferences.shared
    private var snapshot = SystemSnapshot.empty
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var panel: MenuStatStatusPanel?
    private var hostingController: NSHostingController<MenuStatPanelRoot>?
    private var refreshTimer: Timer?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var preferencesCancellable: AnyCancellable?
    private var isPanelVisible = false
    private let panelSize = NSSize(width: 442, height: 620)
    private let panelGap: CGFloat = -8

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        item.button?.title = "▍MS"
        item.button?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        item.button?.isEnabled = true
        item.button?.toolTip = "MenuStat"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu(title: "MenuStat")
        menu.autoenablesItems = false
        menu.delegate = self

        statusItem = item
        statusMenu = menu

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            refreshSnapshot(includeAppUsage: isPanelVisible)
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        setupPanel()
        installPanelEventMonitors()
        preferencesCancellable = displayPreferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshStatusItem()
                if self?.isPanelVisible == true {
                    self?.refreshPanel()
                }
            }
        }
        refreshSnapshot(includeAppUsage: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        removePanelEventMonitors()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildStatusMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu()
    }

    @objc
    func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        if panel?.isVisible == true {
            hidePanel()
            return
        }

        showPanel()
    }

    @objc
    func openDetails(_ sender: Any?) {
        showPanel()
    }

    @objc
    func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "MenuStat"
        alert.informativeText = "\(copyrightText)\n\nApple Silicon system monitor for CPU, memory, pressure, fans, and top-consuming apps."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc
    func toggleLaunchAtLogin(_ sender: Any?) {
        do {
            if isLaunchAtLoginEnabled() {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showLaunchAtLoginError(error)
        }
        rebuildStatusMenu()
    }

    @objc
    func quitMenuStat(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func showPanel() {
        guard let panel else { return }
        isPanelVisible = true
        refreshPanel()
        let frame = panelFrame()
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        refreshSnapshotSoon(includeAppUsage: true)
    }

    private func hidePanel() {
        isPanelVisible = false
        refreshPanel()
        panel?.orderOut(nil)
    }

    private func showStatusMenu() {
        guard let menu = statusMenu, let button = statusItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 2), in: button)
        refreshSnapshotSoon(includeAppUsage: true)
    }

    private func refreshSnapshotSoon(includeAppUsage: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshSnapshot(includeAppUsage: includeAppUsage)
        }
    }

    private func refreshSnapshot(includeAppUsage: Bool) {
        snapshot = sampler.sample(includeAppUsage: includeAppUsage)
        refreshStatusItem()
        if isPanelVisible {
            refreshPanel()
        }
    }

    private func refreshStatusItem() {
        statusItem?.button?.title = menuBarTitle()
        statusItem?.button?.toolTip = "MenuStat — \(snapshot.menuTitle)"
    }

    private func menuBarTitle() -> String {
        switch displayPreferences.primaryMetric {
        case .cpu:
            compactTitle(value: snapshot.cpu.total.percentString)
        case .memory:
            compactTitle(value: snapshot.memory.usedPercent.percentString)
        case .gpu:
            compactTitle(value: snapshot.gpu.tileValue)
        case .pressure:
            "▍\(snapshot.pressure.shortMenuTitle)"
        case .fans:
            compactTitle(value: snapshot.fans.speeds.isEmpty ? "--" : snapshot.fans.percentTitle)
        }
    }

    private func compactTitle(value: String) -> String {
        "▍\(value)"
    }

    private var copyrightText: String {
        "Copyright © \(Self.currentYear) Adhish Thite"
    }

    private func isLaunchAtLoginEnabled(_ status: SMAppService.Status = SMAppService.mainApp.status) -> Bool {
        status == .enabled
    }

    private func launchAtLoginTitle(_ status: SMAppService.Status = SMAppService.mainApp.status) -> String {
        switch status {
        case .enabled:
            "Launch at Login"
        case .requiresApproval:
            "Launch at Login (Needs Approval)"
        case .notRegistered, .notFound:
            "Launch at Login"
        @unknown default:
            "Launch at Login"
        }
    }

    private static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private func showLaunchAtLoginError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Could Not Update Launch at Login"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setupPanel() {
        let hosting = NSHostingController(
            rootView: MenuStatPanelRoot(
                snapshot: snapshot,
                preferences: displayPreferences,
                height: panelSize.height,
                isVisible: isPanelVisible
            )
        )
        hosting.view.frame = NSRect(origin: .zero, size: panelSize)

        let panel = MenuStatStatusPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        hostingController = hosting
        self.panel = panel
    }

    private func refreshPanel() {
        hostingController?.rootView = MenuStatPanelRoot(
            snapshot: snapshot,
            preferences: displayPreferences,
            height: panelSize.height,
            isVisible: isPanelVisible
        )
    }

    private func panelFrame() -> NSRect {
        guard let buttonFrame = statusButtonFrameOnScreen() else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
            return NSRect(
                x: screen.maxX - panelSize.width - 12,
                y: screen.maxY - panelSize.height - 12,
                width: panelSize.width,
                height: panelSize.height
            )
        }

        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? buttonFrame
        let x = min(
            max(buttonFrame.midX - panelSize.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let y = max(
            visibleFrame.minY + 8,
            buttonFrame.minY - panelSize.height - panelGap
        )

        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    private func statusButtonFrameOnScreen() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func installPanelEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePanelIfClickIsOutside()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanelIfClickIsOutside()
        }
    }

    private func removePanelEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        localEventMonitor = nil
        globalEventMonitor = nil
    }

    private func closePanelIfClickIsOutside() {
        guard panel?.isVisible == true else { return }
        let point = NSEvent.mouseLocation
        if panel?.frame.contains(point) == true { return }
        if statusButtonFrameOnScreen()?.insetBy(dx: -6, dy: -6).contains(point) == true { return }
        hidePanel()
    }

    private func rebuildStatusMenu() {
        guard let menu = statusMenu else { return }
        menu.removeAllItems()

        let title = NSMenuItem(title: "MenuStat", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let summary = NSMenuItem(
            title: "\(snapshot.menuTitle)  Fans \(snapshot.fans.percentTitle) \(snapshot.fans.statusTitle)",
            action: nil,
            keyEquivalent: ""
        )
        summary.isEnabled = false
        menu.addItem(summary)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Details", action: #selector(openDetails(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.isEnabled = true
        menu.addItem(openItem)

        let launchAtLoginStatus = SMAppService.mainApp.status
        let launchAtLoginItem = NSMenuItem(
            title: launchAtLoginTitle(launchAtLoginStatus),
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled(launchAtLoginStatus) ? .on : .off
        launchAtLoginItem.isEnabled = true
        menu.addItem(launchAtLoginItem)

        let aboutItem = NSMenuItem(title: "About MenuStat", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.isEnabled = true
        menu.addItem(aboutItem)

        let copyrightItem = NSMenuItem(title: copyrightText, action: nil, keyEquivalent: "")
        copyrightItem.isEnabled = false
        menu.addItem(copyrightItem)

        menu.addItem(.separator())

        let cpuHeader = NSMenuItem(title: "Top CPU Apps", action: nil, keyEquivalent: "")
        cpuHeader.isEnabled = false
        menu.addItem(cpuHeader)

        for app in snapshot.apps.topCPU.prefix(5) {
            let item = NSMenuItem(title: "\(app.name)  \(app.cpuDisplay)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MenuStat", action: #selector(quitMenuStat(_:)), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
    }
}

private final class MenuStatStatusPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct MenuStatPanelRoot: View {
    let snapshot: SystemSnapshot
    @ObservedObject var preferences: DisplayPreferences
    let height: CGFloat
    let isVisible: Bool

    var body: some View {
        ZStack(alignment: .top) {
            MenuStatPanelView(snapshot: snapshot, preferences: preferences, isVisible: isVisible)
        }
        .frame(width: 430, height: height - 12, alignment: .top)
        .padding(6)
    }
}

private extension MemoryPressure {
    var shortMenuTitle: String {
        switch self {
        case .normal: "OK"
        case .moderate: "MID"
        case .high: "HI"
        }
    }
}
