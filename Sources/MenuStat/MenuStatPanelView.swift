import MenuStatCore
import SwiftUI

// MARK: - Brand palette

enum Brand {
    static let bg = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let surface = Color(red: 0.071, green: 0.071, blue: 0.078)
    static let surfaceHi = Color(red: 0.094, green: 0.094, blue: 0.102)
    static let line = Color.white.opacity(0.07)
    static let lineHi = Color.white.opacity(0.14)
    static let text = Color(red: 0.945, green: 0.925, blue: 0.851)
    static let mute = Color(red: 0.945, green: 0.925, blue: 0.851).opacity(0.40)
    static let micro = Color(red: 0.945, green: 0.925, blue: 0.851).opacity(0.22)

    static let cpu = Color(red: 0.302, green: 0.639, blue: 1.000)
    static let mem = Color(red: 0.463, green: 0.941, blue: 0.545)
    static let gpu = Color(red: 0.788, green: 0.553, blue: 1.000)
    static let pressure = Color(red: 1.000, green: 0.702, blue: 0.000)
    static let fan = Color(red: 0.369, green: 0.922, blue: 1.000)
    static let alert = Color(red: 1.000, green: 0.361, blue: 0.302)
}

// MARK: - Section model

private extension MetricKind {
    var fullName: String {
        switch self {
        case .cpu: "SYSTEM CPU"
        case .memory: "MEMORY"
        case .gpu: "GRAPHICS"
        case .pressure: "PRESSURE"
        case .fans: "COOLING"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: Brand.cpu
        case .memory: Brand.mem
        case .gpu: Brand.gpu
        case .pressure: Brand.pressure
        case .fans: Brand.fan
        }
    }
}

// MARK: - Typography modifiers

private enum TypeScale {
    static let pointBump: CGFloat = 2
}

extension View {
    func microLabel(_ tint: Color = Brand.mute) -> some View {
        font(.system(size: 9 + TypeScale.pointBump, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(tint)
            .textCase(.uppercase)
    }

    func bodyMono(_ tint: Color = Brand.text, weight: Font.Weight = .medium) -> some View {
        font(.system(size: 11 + TypeScale.pointBump, weight: weight, design: .monospaced))
            .foregroundStyle(tint)
    }

    func numeric(_ size: CGFloat, weight: Font.Weight = .bold, tint: Color = Brand.text) -> some View {
        font(.system(size: size + TypeScale.pointBump, weight: weight, design: .monospaced))
            .foregroundStyle(tint)
            .monospacedDigit()
    }
}

// MARK: - Root

struct MenuStatPanelView: View {
    let snapshot: SystemSnapshot
    @ObservedObject var preferences: DisplayPreferences
    let isVisible: Bool
    @State private var activeSection: MetricKind = .cpu
    @State private var hoverHelp: String?

    var body: some View {
        VStack(spacing: 0) {
            HeaderRow(snapshot: snapshot, refreshInterval: preferences.refreshInterval, isVisible: isVisible)
            Hairline()
            DisplayControls(preferences: preferences)
            Hairline()
            MetricStrip(snapshot: snapshot, preferences: preferences, active: $activeSection)
            Hairline()
            DetailPane(section: activeSection, snapshot: snapshot, topAppRows: preferences.topAppRows.rawValue)
        }
        .environment(\.setHoverHelp, setHoverHelp)
        .background(panelBackground)
        .overlay(
            Rectangle()
                .stroke(Brand.lineHi, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .bottom) {
            HoverHelpRail(text: hoverHelp)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
                .allowsHitTesting(false)
        }
        .onAppear(perform: ensureActiveSectionVisible)
        .onReceive(preferences.$visibleSections) { _ in
            ensureActiveSectionVisible()
        }
    }

    private var panelBackground: some View {
        ZStack {
            Brand.bg
            ScanlineOverlay()
                .opacity(0.55)
            VignetteOverlay()
        }
    }

    private func ensureActiveSectionVisible() {
        guard !preferences.isVisible(activeSection) else { return }
        activeSection = preferences.visibleSectionsInDisplayOrder().first ?? .cpu
    }

    private func setHoverHelp(_ text: String?) {
        withAnimation(.easeOut(duration: 0.12)) {
            hoverHelp = text
        }
    }
}

private struct HoverHelpActionKey: EnvironmentKey {
    static let defaultValue: (String?) -> Void = { _ in }
}

private extension EnvironmentValues {
    var setHoverHelp: (String?) -> Void {
        get { self[HoverHelpActionKey.self] }
        set { self[HoverHelpActionKey.self] = newValue }
    }
}

private struct HoverHelpModifier: ViewModifier {
    @Environment(\.setHoverHelp) private var setHoverHelp
    let text: String

    func body(content: Content) -> some View {
        content
            .help(text)
            .onHover { isHovering in
                setHoverHelp(isHovering ? text : nil)
            }
            .onDisappear {
                setHoverHelp(nil)
            }
    }
}

extension View {
    func hoverHelp(_ text: String) -> some View {
        modifier(HoverHelpModifier(text: text))
    }
}

private struct HoverHelpRail: View {
    let text: String?

    var body: some View {
        HStack(spacing: 12) {
            Text("INFO")
                .microLabel(Brand.cpu)
            Text(text ?? "HOVER ANY METRIC FOR A PLAIN-ENGLISH DEFINITION")
                .microLabel(text == nil ? Brand.micro : Brand.mute)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface.opacity(0.96))
        .overlay(Rectangle().stroke(Brand.lineHi, lineWidth: 1))
    }
}

// MARK: - Header

private struct HeaderRow: View {
    let snapshot: SystemSnapshot
    let refreshInterval: RefreshInterval
    let isVisible: Bool

    var body: some View {
        if isVisible {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(date: context.date)
            }
        } else {
            content(date: snapshot.updatedAt)
        }
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func content(date: Date) -> some View {
        HStack(alignment: .center, spacing: 16) {
            LiveryBar(tint: Brand.cpu)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("MENUSTAT")
                        .font(.system(size: 13 + TypeScale.pointBump, weight: .black, design: .monospaced))
                        .tracking(2.4)
                        .foregroundStyle(Brand.text)
                    Text("//")
                        .microLabel(Brand.micro)
                    Text("APPLE M-SERIES")
                        .microLabel()
                }
                HStack(spacing: 12) {
                    StatusDot(color: Brand.mem, isActive: isVisible)
                    Text("LIVE")
                        .microLabel(Brand.mute)
                    Text("·")
                        .microLabel(Brand.micro)
                    Text("REFRESH \(refreshInterval.shortTitle)")
                        .microLabel(Brand.mute)
                    Text("·")
                        .microLabel(Brand.micro)
                    Text("UP \(snapshot.uptime.uptimeShortString.uppercased())")
                        .microLabel(Brand.mute)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Text(Self.clockFormatter.string(from: date))
                    .numeric(15, weight: .bold)
                Text("T-\(timeAgo(from: snapshot.updatedAt, now: date))")
                    .microLabel(Brand.mute)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private func timeAgo(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        return seconds < 0 ? "00s" : String(format: "%02ds", seconds)
    }
}

private struct LiveryBar: View {
    let tint: Color

    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(width: 4, height: 42)
    }
}

private struct StatusDot: View {
    let color: Color
    let isActive: Bool
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(pulsing ? 1.0 : 0.35)
            .shadow(color: color.opacity(0.6), radius: pulsing ? 3 : 0)
            .animation(isActive ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: pulsing)
            .onAppear { pulsing = isActive }
            .onChange(of: isActive) { isActive in
                pulsing = isActive
            }
    }
}

// MARK: - Metric strip

private struct DisplayControls: View {
    @ObservedObject var preferences: DisplayPreferences

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                Text("MENU")
                    .microLabel(Brand.micro)
                Picker("", selection: $preferences.primaryMetric) {
                    ForEach(MetricKind.allCases) { section in
                        Text(section.shortTitle).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 20) {
                Text("SHOW")
                    .microLabel(Brand.micro)
                HStack(spacing: 12) {
                    ForEach(MetricKind.allCases) { section in
                        SectionToggle(
                            section: section,
                            isOn: preferences.isVisible(section),
                            action: {
                                preferences.setVisible(!preferences.isVisible(section), for: section)
                            }
                        )
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 20) {
                Text("RATE")
                    .microLabel(Brand.micro)
                Picker("", selection: $preferences.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.shortTitle).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                Text("ROWS")
                    .microLabel(Brand.micro)
                Picker("", selection: $preferences.topAppRows) {
                    ForEach(TopAppRowCount.allCases) { rows in
                        Text(rows.shortTitle).tag(rows)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(Brand.surface.opacity(0.72))
    }
}

private struct SectionToggle: View {
    let section: MetricKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(section.shortTitle)
                .font(.system(size: 9 + TypeScale.pointBump, weight: .bold, design: .monospaced))
                .foregroundStyle(isOn ? Brand.bg : Brand.mute)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: 58, height: 32)
                .background(isOn ? section.tint : Brand.bg)
                .overlay(Rectangle().stroke(isOn ? section.tint : Brand.lineHi, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct MetricStrip: View {
    let snapshot: SystemSnapshot
    @ObservedObject var preferences: DisplayPreferences
    @Binding var active: MetricKind

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(preferences.visibleSectionsInDisplayOrder().enumerated()), id: \.element.id) { index, section in
                MetricTile(
                    section: section,
                    value: section.tileValue(snapshot),
                    progress: section.progress(snapshot),
                    caption: section.tileCaption(snapshot),
                    active: active == section,
                    tint: section == .pressure ? snapshot.pressure.tint : nil,
                    onTap: { active = section }
                )
                if index < preferences.visibleSectionsInDisplayOrder().count - 1 {
                    VRule()
                }
            }
        }
        .frame(height: 156)
    }
}

private struct MetricTile: View {
    let section: MetricKind
    let value: String
    let progress: Double
    let caption: String
    let active: Bool
    var tint: Color?
    let onTap: () -> Void

    private var accent: Color {
        tint ?? section.tint
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(active ? accent : .clear)
                    .frame(height: 2)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(section.shortTitle)
                    .microLabel(active ? accent : Brand.mute)
                    .padding(.top, 8)

                Text(value)
                    .numeric(28, weight: .heavy, tint: active ? Brand.text : Brand.text.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                SegmentedBar(value: progress, tint: accent, segments: 12, lit: active)

                Text(caption)
                    .microLabel(Brand.mute)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            if active {
                CornerBrackets(tint: accent)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .background(active ? Brand.surface : Brand.bg)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .hoverHelp(section.tileHelp)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section.fullName)
        .accessibilityValue("\(value), \(caption)")
    }
}

private struct SegmentedBar: View {
    let value: Double
    let tint: Color
    let segments: Int
    var lit = true

    var body: some View {
        let clamped = max(0, min(1, value))
        let activeSegments = Int((Double(segments) * clamped).rounded())
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(color(for: index, activeCount: activeSegments))
                    .frame(height: 5)
            }
        }
    }

    private func color(for index: Int, activeCount: Int) -> Color {
        guard index < activeCount else { return Brand.line }
        return lit ? tint : tint.opacity(0.45)
    }
}

private struct CornerBrackets: View {
    let tint: Color
    private let length: CGFloat = 8
    private let inset: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                bracket().position(x: inset + length / 2, y: inset + length / 2)
                bracket().rotationEffect(.degrees(90))
                    .position(x: size.width - inset - length / 2, y: inset + length / 2)
                bracket().rotationEffect(.degrees(-90))
                    .position(x: inset + length / 2, y: size.height - inset - length / 2)
                bracket().rotationEffect(.degrees(180))
                    .position(x: size.width - inset - length / 2, y: size.height - inset - length / 2)
            }
        }
    }

    private func bracket() -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint.zero)
            path.addLine(to: CGPoint(x: length, y: 0))
        }
        .stroke(tint, lineWidth: 1)
        .frame(width: length, height: length)
    }
}

// MARK: - Detail pane

private struct DetailPane: View {
    let section: MetricKind
    let snapshot: SystemSnapshot
    let topAppRows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(section: section, snapshot: snapshot)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    switch section {
                    case .cpu:
                        CPUDetail(snapshot: snapshot, topAppRows: topAppRows)
                    case .memory:
                        MemoryDetail(snapshot: snapshot, topAppRows: topAppRows)
                    case .gpu:
                        GPUDetail(snapshot: snapshot, topAppRows: topAppRows)
                    case .pressure:
                        PressureDetail(snapshot: snapshot, topAppRows: topAppRows)
                    case .fans:
                        FanDetail(snapshot: snapshot, topAppRows: topAppRows)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 30)
                .padding(.bottom, 84)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Brand.bg)
    }
}

private struct DetailHeader: View {
    let section: MetricKind
    let snapshot: SystemSnapshot

    private var valueText: String {
        section.tileValue(snapshot)
    }

    private var subtitle: String {
        switch section {
        case .cpu: "LOAD DISTRIBUTION · PER-CORE ACTIVITY"
        case .memory: "UNIFIED MEMORY · PAGE STATE"
        case .gpu: "AGX UTILIZATION · GRAPHICS MEMORY"
        case .pressure: snapshot.pressure.detail.uppercased()
        case .fans: "RPM TELEMETRY · COOLING CURVE"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Rectangle()
                .fill(section.tint)
                .frame(width: 4, height: 42)

            VStack(alignment: .leading, spacing: 10) {
                Text(section.fullName)
                    .microLabel(section.tint)
                Text(subtitle)
                    .microLabel(Brand.mute)
                    .lineLimit(1)
            }

            Spacer()

            Text(valueText)
                .numeric(24, weight: .heavy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .hoverHelp(section.detailHelp)
    }
}

// MARK: - Section details

private struct CPUDetail: View {
    let snapshot: SystemSnapshot
    let topAppRows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            MeterRow(label: "USER", value: snapshot.cpu.user, tint: Brand.cpu, help: "CPU time spent running app and user-space code.")
            MeterRow(
                label: "SYSTEM",
                value: snapshot.cpu.system,
                tint: Brand.pressure,
                help: "CPU time spent inside the macOS kernel and system services."
            )
            MeterRow(
                label: "IDLE",
                value: snapshot.cpu.idle,
                tint: Brand.mute,
                help: "CPU capacity that was not used during the last sample."
            )

            DatumGrid(items: [
                DatumItem(
                    label: "BUSIEST",
                    value: snapshot.cpu.busiestCore.percentString,
                    help: "The highest-loaded individual logical CPU core in this sample."
                ),
                DatumItem(
                    label: "LOGICAL",
                    value: "\(snapshot.coreCount)",
                    help: "Logical CPU cores visible to macOS. On Apple Silicon, these may include performance and efficiency cores."
                ),
                DatumItem(
                    label: "UPTIME",
                    value: snapshot.uptime.uptimeDetailString,
                    help: "How long this Mac has been running since the last boot."
                ),
                DatumItem(
                    label: "NICE",
                    value: snapshot.cpu.nice.percentString,
                    help: "CPU time used by low-priority processes. Usually near zero on macOS."
                )
            ])

            CorePlot(values: snapshot.cpu.perCore, coreTypes: snapshot.cpu.coreTypes)

            TopAppList(
                title: "TOP APPS · CPU",
                apps: snapshot.apps.topCPU,
                kind: .cpu,
                limit: topAppRows,
                note: "SYSTEM TOTAL INCLUDES KERNEL WORK + ALL PROCESSES"
            )
        }
    }
}

private struct MemoryDetail: View {
    let snapshot: SystemSnapshot
    let topAppRows: Int

    private var memory: MemorySnapshot {
        snapshot.memory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            MeterRow(label: "USED", value: memory.usedPercent, tint: Brand.mem, help: "Share of unified memory currently in use.")
            MeterRow(
                label: "AVAILABLE",
                value: memory.freePercent,
                tint: Brand.fan,
                help: "Memory macOS can use without immediately reclaiming active pages."
            )

            DatumGrid(
                items: [
                    DatumItem(label: "TOTAL", value: memory.total.formattedBytesShort, help: "Total unified memory installed in this Mac."),
                    DatumItem(
                        label: "USED",
                        value: memory.used.formattedBytesShort,
                        help: "Memory currently assigned to apps, system services, cache, wired pages, and compressed pages."
                    ),
                    DatumItem(
                        label: "FREE",
                        value: (memory.free + memory.inactive + memory.speculative).formattedBytesShort,
                        help: "Free, inactive, and speculative memory that can be reused quickly."
                    ),
                    DatumItem(
                        label: "ACTIVE",
                        value: memory.active.formattedBytesShort,
                        help: "Memory actively used by running processes."
                    ),
                    DatumItem(
                        label: "WIRED",
                        value: memory.wired.formattedBytesShort,
                        help: "Memory the kernel cannot page out. Drivers, kernel objects, and hardware mappings often live here."
                    ),
                    DatumItem(
                        label: "COMPR",
                        value: memory.compressed.formattedBytesShort,
                        help: "Memory compressed by macOS to avoid slower disk swap."
                    )
                ],
                columns: 3
            )

            TopAppList(title: "TOP PROCESSES · MEM", apps: snapshot.apps.topMemory, kind: .memory, limit: topAppRows)
        }
    }
}

private struct GPUDetail: View {
    let snapshot: SystemSnapshot
    let topAppRows: Int

    private var gpu: GPUSnapshot {
        snapshot.gpu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let utilization = gpu.utilization {
                MeterRow(
                    label: "DEVICE",
                    value: utilization,
                    tint: Brand.gpu,
                    help: "Overall AGX GPU device utilization reported by IORegistry."
                )
                MeterRow(
                    label: "RENDER",
                    value: gpu.rendererUtilization ?? 0,
                    tint: Brand.cpu,
                    help: "GPU renderer workload. Higher values usually mean fragment or compute-heavy graphics work."
                )
                MeterRow(
                    label: "TILER",
                    value: gpu.tilerUtilization ?? 0,
                    tint: Brand.fan,
                    help: "GPU tiler workload. Higher values usually mean geometry or tile setup pressure."
                )

                DatumGrid(
                    items: [
                        DatumItem(
                            label: "STATE",
                            value: gpu.statusTitle.uppercased(),
                            help: "MenuStat's simple activity bucket for the current GPU load."
                        ),
                        DatumItem(
                            label: "CORES",
                            value: gpu.coreCount.map(String.init) ?? "--",
                            help: "GPU core count reported by the Apple AGX device, when exposed."
                        ),
                        DatumItem(
                            label: "MEM",
                            value: gpu.memoryBytes?.formattedBytesShort ?? "--",
                            help: "Unified memory currently attributed to GPU use, when exposed."
                        ),
                        DatumItem(label: "MODEL", value: gpu.model ?? "Apple GPU", help: "GPU model string reported by IORegistry."),
                        DatumItem(label: "SOURCE", value: gpu.source, help: "Telemetry source used for this GPU sample."),
                        DatumItem(label: "LOAD", value: gpu.tileValue, help: "Current total GPU utilization.")
                    ],
                    columns: 3
                )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("NO GPU TELEMETRY")
                        .microLabel(Brand.alert)
                    Text(gpu.detail)
                        .bodyMono(Brand.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("SOURCE · \(gpu.source.uppercased())")
                        .microLabel(Brand.micro)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().stroke(Brand.alert.opacity(0.45), lineWidth: 1))
            }

            TopAppList(title: "TOP PROCESSES · CPU PROXY", apps: snapshot.apps.topCPU, kind: .cpu, limit: topAppRows)
        }
    }
}

private struct PressureDetail: View {
    let snapshot: SystemSnapshot
    let topAppRows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            PressureGauge(pressure: snapshot.pressure, usedPercent: snapshot.memory.usedPercent)

            DatumGrid(items: [
                DatumItem(
                    label: "STATE",
                    value: snapshot.pressure.shortTitle,
                    help: "macOS memory pressure state: normal, moderate, or high."
                ),
                DatumItem(
                    label: "FREE PAGES",
                    value: snapshot.memory.free.formattedBytesShort,
                    help: "Memory pages currently free before macOS reclaims inactive or compressed memory."
                ),
                DatumItem(
                    label: "PAGE SIZE",
                    value: snapshot.memory.pageSize.formattedBytesShort,
                    help: "The byte size of each virtual memory page on this Mac."
                )
            ])

            TopAppList(title: "HEAT PROXY · LIKELY DRIVERS", apps: snapshot.apps.topHeat, kind: .heat, limit: topAppRows)
        }
    }
}

private struct FanDetail: View {
    let snapshot: SystemSnapshot
    let topAppRows: Int

    private var fans: FanSnapshot {
        snapshot.fans
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if fans.speeds.isEmpty {
                EmptyFanReadout(fans: fans)
            } else {
                ForEach(Array(fans.speeds.enumerated()), id: \.offset) { index, speed in
                    FanReadout(
                        index: index,
                        speed: speed,
                        ratio: fans.rangePercent(at: index),
                        minSpeed: fans.minSpeed(at: index),
                        maxSpeed: fans.maxSpeed(at: index)
                    )
                }

                DatumGrid(items: [
                    DatumItem(
                        label: "STATE",
                        value: "\(fans.percentTitle) · \(fans.statusTitle.uppercased())",
                        help: "Fan speed normalized against the fan's reported min and max range."
                    ),
                    DatumItem(label: "CURRENT", value: fans.rpmText, help: "Current fan speed in revolutions per minute."),
                    DatumItem(label: "RANGE", value: fans.rangeText, help: "Reported minimum and maximum fan RPM range from SMC.")
                ])

                Text("SOURCE · \(fans.source.uppercased())")
                    .microLabel(Brand.micro)
            }

            TopAppList(title: "LIKELY THERMAL DRIVERS", apps: snapshot.apps.topHeat, kind: .heat, limit: topAppRows)
        }
    }
}

private struct EmptyFanReadout: View {
    let fans: FanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NO TELEMETRY")
                .microLabel(Brand.alert)
            Text(fans.detail)
                .bodyMono(Brand.mute)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Text("PROBE · \(fans.source.uppercased())")
                    .microLabel(Brand.micro)
                if !fans.attemptedKeys.isEmpty {
                    Text("KEYS · \(fans.attemptedKeys.joined(separator: " "))")
                        .microLabel(Brand.micro)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Brand.alert.opacity(0.45), lineWidth: 1))
    }
}

private struct FanReadout: View {
    let index: Int
    let speed: Int
    let ratio: Double
    let minSpeed: Int?
    let maxSpeed: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Text(String(format: "FAN.%02d", index))
                        .microLabel(Brand.fan)
                    Text("·")
                        .microLabel(Brand.micro)
                    Text(rangeText)
                        .microLabel(Brand.mute)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(speed)")
                        .numeric(16, weight: .heavy)
                    Text("RPM")
                        .microLabel(Brand.mute)
                }
            }
            SegmentedBar(value: ratio, tint: Brand.fan, segments: 24, lit: true)
        }
        .padding(18)
        .background(Brand.surface)
        .hoverHelp("Current fan speed and where it sits inside the fan's reported RPM range.")
    }

    private var rangeText: String {
        switch (minSpeed, maxSpeed) {
        case let (min?, max?): "\(min) → \(max)"
        case let (_, max?): "MAX \(max)"
        case let (min?, _): "MIN \(min)"
        default: "—"
        }
    }
}

// MARK: - Meters and gauges

private struct MeterRow: View {
    let label: String
    let value: Double
    let tint: Color
    var trailing: String?
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .microLabel(Brand.mute)
                Spacer()
                Text(trailing ?? value.percentString)
                    .bodyMono(Brand.text, weight: .bold)
            }
            SegmentedBar(value: value, tint: tint, segments: 28)
        }
        .hoverHelp(help ?? "\(label) percentage for the current sample.")
    }
}

private struct PressureGauge: View {
    let pressure: MemoryPressure
    let usedPercent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PRESSURE INDEX")
                .microLabel(Brand.mute)
            HStack(spacing: 6) {
                ForEach(MemoryPressure.allCases) { level in
                    PressureCell(level: level, active: level == pressure)
                }
            }
            SegmentedBar(value: usedPercent, tint: pressure.tint, segments: 36)
        }
        .padding(18)
        .background(Brand.surface)
        .hoverHelp(
            "macOS memory pressure. Higher pressure means the system is reclaiming, compressing, or paging memory more aggressively."
        )
    }
}

private struct PressureCell: View {
    let level: MemoryPressure
    let active: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(level.shortTitle)
                .microLabel(active ? level.tint : Brand.micro)
            Rectangle()
                .fill(active ? level.tint : Brand.line)
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .hoverHelp(level.helpText)
    }
}

private struct CorePlot: View {
    let values: [Double]
    let coreTypes: [CPUCoreType]

    private var effectiveCoreTypes: [CPUCoreType] {
        values.indices.map { index in
            index < coreTypes.count ? coreTypes[index] : .unknown
        }
    }

    private var topologySummary: String {
        let performanceCount = effectiveCoreTypes.filter { $0 == .performance }.count
        let efficiencyCount = effectiveCoreTypes.filter { $0 == .efficiency }.count
        if performanceCount > 0 || efficiencyCount > 0 {
            return "\(performanceCount)P / \(efficiencyCount)E"
        }
        return "\(values.count) CORES"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PER-CORE ACTIVITY")
                    .microLabel(Brand.mute)
                Spacer()
                Text(topologySummary)
                    .microLabel(Brand.micro)
            }
            if values.isEmpty {
                Rectangle()
                    .fill(Brand.surface)
                    .frame(height: 44)
                    .overlay(Text("WAITING FOR SAMPLE").microLabel(Brand.micro))
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let coreType = effectiveCoreTypes[index]
                        VStack(spacing: 7) {
                            Text(value.percentString)
                                .font(.system(size: 10 + TypeScale.pointBump, weight: .bold, design: .monospaced))
                                .foregroundStyle(coreType.tint)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            CoreBar(value: value, coreType: coreType)
                            Text(coreLabel(for: index, type: coreType))
                                .font(.system(size: 9 + TypeScale.pointBump, weight: .bold, design: .monospaced))
                                .foregroundStyle(coreType.tint.opacity(0.72))
                        }
                        .frame(maxWidth: .infinity)
                        .hoverHelp(coreHelp(for: index, type: coreType, value: value))
                    }
                }
                .frame(height: 104)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Brand.surface)
            }
        }
    }

    private func coreLabel(for index: Int, type: CPUCoreType) -> String {
        switch type {
        case .performance:
            "P\(ordinal(for: index, type: type))"
        case .efficiency:
            "E\(ordinal(for: index, type: type))"
        case .unknown:
            String(format: "%02d", index)
        }
    }

    private func ordinal(for index: Int, type: CPUCoreType) -> Int {
        effectiveCoreTypes.prefix(index).filter { $0 == type }.count
    }

    private func coreHelp(for index: Int, type: CPUCoreType, value: Double) -> String {
        switch type {
        case .performance:
            "Performance core \(ordinal(for: index, type: type)) is at \(value.percentString). " +
                "macOS usually schedules heavier foreground work here."
        case .efficiency:
            "Efficiency core \(ordinal(for: index, type: type)) is at \(value.percentString). " +
                "macOS uses these for lighter or background work."
        case .unknown:
            "Logical CPU core \(index) is at \(value.percentString)."
        }
    }
}

private struct CoreBar: View {
    let value: Double
    let coreType: CPUCoreType

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(1, value))
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Brand.line)
                Rectangle()
                    .fill(barColor(clamped, coreType: coreType))
                    .frame(height: max(2, proxy.size.height * clamped))
            }
        }
        .frame(height: 58)
    }

    private func barColor(_ value: Double, coreType: CPUCoreType) -> Color {
        if value >= 0.88 {
            return Brand.alert
        }
        return coreType.tint
    }
}

private extension CPUCoreType {
    var tint: Color {
        switch self {
        case .performance: Brand.cpu
        case .efficiency: Brand.mem
        case .unknown: Brand.cpu
        }
    }
}
