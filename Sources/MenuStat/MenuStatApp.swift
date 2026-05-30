import AppKit
import Combine
import MenuStatCore
import OSLog
import ServiceManagement
import SwiftUI

private var retainedAppDelegate: MenuStatAppDelegate?

enum PanelLayout {
    static let panelSize = NSSize(width: 720, height: 820)
    static let outerPadding: CGFloat = 6

    static var contentSize: CGSize {
        CGSize(
            width: panelSize.width - outerPadding * 2,
            height: panelSize.height - outerPadding * 2
        )
    }
}

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

        guard HardwareSupport.isAppleSiliconMac else {
            showUnsupportedAlertAndQuit()
        }

        let app = NSApplication.shared
        let delegate = MenuStatAppDelegate()
        retainedAppDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private func showUnsupportedAlertAndQuit() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = HardwareSupport.unsupportedTitle
    alert.informativeText = HardwareSupport.unsupportedMessage
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Quit")
    alert.runModal()

    app.terminate(nil)
    exit(1)
}

final class MenuStatAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let samplingLogger = Logger(subsystem: "com.adhishthite.MenuStat", category: "sampling")

    private let sampler = SystemSampler()
    private let samplingQueue = DispatchQueue(label: "com.adhishthite.MenuStat.sampling", qos: .utility)
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
    private var shouldClosePanelFromStatusItemClick = false
    private var isSampling = false
    private var pendingSampleIncludesAppUsage = false
    private var pendingSampleNeedsFreshAppUsage = false
    private let panelGap: CGFloat = -8

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        item.button?.title = "▍MS"
        item.button?.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
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

        scheduleRefreshTimer()

        setupPanel()
        installPanelEventMonitors()
        preferencesCancellable = displayPreferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleRefreshTimer()
                self?.refreshStatusItem()
                if self?.isPanelVisible == true {
                    self?.refreshPanel()
                }
            }
        }
        refreshSnapshot(includeAppUsage: false, freshAppUsage: false)
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
            shouldClosePanelFromStatusItemClick = false
            showStatusMenu()
            return
        }

        if shouldClosePanelFromStatusItemClick || panel?.isVisible == true {
            shouldClosePanelFromStatusItemClick = false
            hidePanel()
            return
        }

        shouldClosePanelFromStatusItemClick = false
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
        let description = "Apple Silicon system monitor for CPU, memory, pressure, fans, and top-consuming apps."
        alert.informativeText = "\(versionDisplay)\n\(copyrightText)\n\n\(description)"
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
    func setRefreshInterval(_ sender: NSMenuItem) {
        guard let rawValue = (sender.representedObject as? NSNumber)?.doubleValue,
              let interval = RefreshInterval(rawValue: rawValue)
        else { return }
        displayPreferences.refreshInterval = interval
        scheduleRefreshTimer()
        rebuildStatusMenu()
    }

    @objc
    func setTopAppRows(_ sender: NSMenuItem) {
        guard let rawValue = (sender.representedObject as? NSNumber)?.intValue,
              let rows = TopAppRowCount(rawValue: rawValue)
        else { return }
        displayPreferences.topAppRows = rows
        refreshPanel()
        rebuildStatusMenu()
    }

    @objc
    func setPrimaryMetric(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let metric = MetricKind(rawValue: rawValue)
        else { return }
        displayPreferences.primaryMetric = metric
        refreshStatusItem()
        rebuildStatusMenu()
    }

    @objc
    func toggleVisibleSection(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let metric = MetricKind(rawValue: rawValue)
        else { return }
        displayPreferences.setVisible(!displayPreferences.isVisible(metric), for: metric)
        refreshPanel()
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
        refreshSnapshotSoon(includeAppUsage: true, freshAppUsage: true)
    }

    private func hidePanel() {
        isPanelVisible = false
        refreshPanel()
        panel?.orderOut(nil)
    }

    private func showStatusMenu() {
        guard let menu = statusMenu, let button = statusItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 2), in: button)
        refreshSnapshotSoon(includeAppUsage: true, freshAppUsage: true)
    }

    private func refreshSnapshotSoon(includeAppUsage: Bool, freshAppUsage: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshSnapshot(includeAppUsage: includeAppUsage, freshAppUsage: freshAppUsage)
        }
    }

    private func scheduleRefreshTimer() {
        let interval = displayPreferences.refreshInterval.rawValue
        if refreshTimer?.timeInterval == interval {
            return
        }

        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            refreshSnapshot(includeAppUsage: isPanelVisible, freshAppUsage: false)
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshSnapshot(includeAppUsage: Bool, freshAppUsage: Bool) {
        // Keep one sampler call in flight. Hidden-panel ticks can drop; app-usage requests coalesce into one follow-up.
        if isSampling {
            pendingSampleIncludesAppUsage = pendingSampleIncludesAppUsage || includeAppUsage
            pendingSampleNeedsFreshAppUsage = pendingSampleNeedsFreshAppUsage || freshAppUsage
            return
        }

        isSampling = true
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let startedAt = DispatchTime.now().uptimeNanoseconds
            if freshAppUsage {
                sampler.refreshProcessUsageBaseline()
                Thread.sleep(forTimeInterval: 0.25)
            }
            let nextSnapshot = sampler.sample(includeAppUsage: includeAppUsage)
            let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            Self.samplingLogger.debug(
                """
                sample includeAppUsage=\(includeAppUsage, privacy: .public) \
                freshAppUsage=\(freshAppUsage, privacy: .public) \
                durationMs=\(durationMs, privacy: .public)
                """
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                snapshot = nextSnapshot
                isSampling = false
                refreshStatusItem()
                if isPanelVisible {
                    refreshPanel()
                }

                let shouldRunPendingSample = pendingSampleIncludesAppUsage
                let shouldRunFreshAppUsage = pendingSampleNeedsFreshAppUsage
                pendingSampleIncludesAppUsage = false
                pendingSampleNeedsFreshAppUsage = false
                if shouldRunPendingSample {
                    refreshSnapshot(includeAppUsage: true, freshAppUsage: shouldRunFreshAppUsage)
                }
            }
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

    private var versionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?):
            return "Version \(version) (\(build))"
        case let (version?, nil):
            return "Version \(version)"
        case let (nil, build?):
            return "Build \(build)"
        case (nil, nil):
            return "Version unavailable"
        }
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
                width: PanelLayout.panelSize.width,
                height: PanelLayout.panelSize.height,
                isVisible: isPanelVisible
            )
        )
        hosting.view.frame = NSRect(origin: .zero, size: PanelLayout.panelSize)

        let panel = MenuStatStatusPanel(
            contentRect: NSRect(origin: .zero, size: PanelLayout.panelSize),
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
            width: PanelLayout.panelSize.width,
            height: PanelLayout.panelSize.height,
            isVisible: isPanelVisible
        )
    }

    private func panelFrame() -> NSRect {
        guard let buttonFrame = statusButtonFrameOnScreen() else {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
            return NSRect(
                x: screen.maxX - PanelLayout.panelSize.width - 12,
                y: screen.maxY - PanelLayout.panelSize.height - 12,
                width: PanelLayout.panelSize.width,
                height: PanelLayout.panelSize.height
            )
        }

        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? buttonFrame
        let x = min(
            max(buttonFrame.midX - PanelLayout.panelSize.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - PanelLayout.panelSize.width - 8
        )
        let y = max(
            visibleFrame.minY + 8,
            buttonFrame.minY - PanelLayout.panelSize.height - panelGap
        )

        return NSRect(x: x, y: y, width: PanelLayout.panelSize.width, height: PanelLayout.panelSize.height)
    }

    private func statusButtonFrameOnScreen() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func installPanelEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePanelIfClickIsOutside(event)
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePanelIfClickIsOutside(event)
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

    private func closePanelIfClickIsOutside(_ event: NSEvent) {
        guard panel?.isVisible == true else { return }
        let point = NSEvent.mouseLocation
        if panel?.frame.contains(point) == true { return }
        if statusButtonFrameOnScreen()?.insetBy(dx: -6, dy: -6).contains(point) == true {
            shouldClosePanelFromStatusItemClick = event.type == .leftMouseDown
            return
        }
        shouldClosePanelFromStatusItemClick = false
        hidePanel()
    }
}

private extension MenuStatAppDelegate {
    func rebuildStatusMenu() {
        guard let menu = statusMenu else { return }
        menu.removeAllItems()
        addHeaderItems(to: menu)
        addPreferenceItems(to: menu)
        addUtilityItems(to: menu)
        addTopCPUItems(to: menu)
        addQuitItem(to: menu)
    }

    func addHeaderItems(to menu: NSMenu) {
        addDisabledItem(title: "MenuStat", to: menu)
        addDisabledItem(title: versionDisplay, to: menu)
        addDisabledItem(
            title: "\(snapshot.menuTitle)  Fans \(snapshot.fans.percentTitle) \(snapshot.fans.statusTitle)",
            to: menu
        )
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Details", action: #selector(openDetails(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.isEnabled = true
        menu.addItem(openItem)
    }

    func addPreferenceItems(to menu: NSMenu) {
        menu.addItem(submenuItem(title: "Refresh Rate", submenu: refreshRateMenu()))
        menu.addItem(submenuItem(title: "Top App Rows", submenu: topAppRowsMenu()))
        menu.addItem(submenuItem(title: "Menu Bar Metric", submenu: menuBarMetricMenu()))
        menu.addItem(submenuItem(title: "Visible Sections", submenu: visibleSectionsMenu()))
    }

    func addUtilityItems(to menu: NSMenu) {
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

        addDisabledItem(title: copyrightText, to: menu)
        menu.addItem(.separator())
    }

    func addTopCPUItems(to menu: NSMenu) {
        addDisabledItem(title: "Top CPU Apps", to: menu)
        for app in snapshot.apps.topCPU.prefix(5) {
            addDisabledItem(title: "\(app.name)  \(app.cpuDisplay)", to: menu)
        }
        menu.addItem(.separator())
    }

    func addQuitItem(to menu: NSMenu) {
        let quitItem = NSMenuItem(title: "Quit MenuStat", action: #selector(quitMenuStat(_:)), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
    }

    func refreshRateMenu() -> NSMenu {
        let menu = NSMenu()
        for interval in RefreshInterval.allCases {
            let item = NSMenuItem(title: interval.menuTitle, action: #selector(setRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval.rawValue
            item.state = displayPreferences.refreshInterval == interval ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    func topAppRowsMenu() -> NSMenu {
        let menu = NSMenu()
        for rows in TopAppRowCount.allCases {
            let item = NSMenuItem(title: rows.menuTitle, action: #selector(setTopAppRows(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rows.rawValue
            item.state = displayPreferences.topAppRows == rows ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    func menuBarMetricMenu() -> NSMenu {
        let menu = NSMenu()
        for metric in MetricKind.allCases {
            let item = NSMenuItem(title: metric.shortTitle, action: #selector(setPrimaryMetric(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = metric.rawValue
            item.state = displayPreferences.primaryMetric == metric ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    func visibleSectionsMenu() -> NSMenu {
        let menu = NSMenu()
        for section in MetricKind.allCases {
            let item = NSMenuItem(title: section.shortTitle, action: #selector(toggleVisibleSection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = section.rawValue
            item.state = displayPreferences.isVisible(section) ? .on : .off
            item.isEnabled = displayPreferences.isVisible(section) ? displayPreferences.visibleSections.count > 1 : true
            menu.addItem(item)
        }
        return menu
    }

    func submenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    func addDisabledItem(title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
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

struct MenuStatPanelRoot: View {
    let snapshot: SystemSnapshot
    @ObservedObject var preferences: DisplayPreferences
    let width: CGFloat
    let height: CGFloat
    let isVisible: Bool

    var body: some View {
        ZStack(alignment: .top) {
            MenuStatPanelView(snapshot: snapshot, preferences: preferences, isVisible: isVisible)
        }
        .frame(width: width - 12, height: height - 12, alignment: .top)
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
