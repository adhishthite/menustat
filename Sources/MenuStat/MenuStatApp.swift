import AppKit
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
    private var snapshot = SystemSnapshot.empty
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var panel: MenuStatStatusPanel?
    private var hostingController: NSHostingController<MenuStatPanelRoot>?
    private var refreshTimer: Timer?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private let panelSize = NSSize(width: 442, height: 560)
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
        appendStatusLog("status item created; button=\(String(describing: item.button))")

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshSnapshot()
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        setupPanel()
        installPanelEventMonitors()
        refreshSnapshot()
        appendStatusLog("initial snapshot complete; menuItems=\(menu.items.count)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        removePanelEventMonitors()
    }

    func menuWillOpen(_ menu: NSMenu) {
        appendClickLog("status menu will open")
        rebuildStatusMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        appendClickLog("status menu needs update")
        rebuildStatusMenu()
    }

    @objc
    func statusItemClicked(_ sender: Any?) {
        let eventType = NSApp.currentEvent.map { "\($0.type.rawValue)" } ?? "none"
        appendClickLog("status item action fired; eventType=\(eventType)")

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
        appendClickLog("open details selected")
        showPanel()
    }

    @objc
    func quitMenuStat(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func showPanel() {
        guard let panel else { return }
        refreshPanel()
        let frame = panelFrame()
        appendClickLog("show panel frame=\(frame)")
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        appendClickLog("panel visible=\(panel.isVisible); key=\(panel.isKeyWindow)")
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func showStatusMenu() {
        guard let menu = statusMenu, let button = statusItem?.button else { return }
        rebuildStatusMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 2), in: button)
    }

    private func refreshSnapshot() {
        snapshot = sampler.sample()
        let cpu = Int((snapshot.cpu.total * 100).rounded())
        statusItem?.button?.title = String(format: "▍%02d%%", cpu)
        statusItem?.button?.toolTip = "MenuStat — \(snapshot.menuTitle)"
        refreshPanel()
        rebuildStatusMenu()
    }

    private func setupPanel() {
        let hosting = NSHostingController(
            rootView: MenuStatPanelRoot(snapshot: snapshot, height: panelSize.height)
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
        hostingController?.rootView = MenuStatPanelRoot(snapshot: snapshot, height: panelSize.height)
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

    private func appendStatusLog(_ message: String) {
        append(message, to: "/tmp/menustat-status.log")
    }

    private func appendClickLog(_ message: String) {
        append(message, to: "/tmp/menustat-click.log")
    }

    private func append(_ message: String, to path: String) {
        let line = "\(message) at \(Date())\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let file = FileHandle(forWritingAtPath: path) else { return }
        file.seekToEndOfFile()
        file.write(data)
        try? file.close()
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
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            MenuStatPanelView(snapshot: snapshot)
        }
        .frame(width: 430, height: height - 12, alignment: .top)
        .padding(6)
    }
}
