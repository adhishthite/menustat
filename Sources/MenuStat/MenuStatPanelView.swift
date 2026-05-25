import MenuStatCore
import SwiftUI

// MARK: - Brand palette

private enum Brand {
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
        case .cpu: "PROCESSOR"
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

private extension View {
    func microLabel(_ tint: Color = Brand.mute) -> some View {
        font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(tint)
            .textCase(.uppercase)
    }

    func bodyMono(_ tint: Color = Brand.text, weight: Font.Weight = .medium) -> some View {
        font(.system(size: 11, weight: weight, design: .monospaced))
            .foregroundStyle(tint)
    }

    func numeric(_ size: CGFloat, weight: Font.Weight = .bold, tint: Color = Brand.text) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
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

    var body: some View {
        VStack(spacing: 0) {
            HeaderRow(snapshot: snapshot, isVisible: isVisible)
            Hairline()
            DisplayControls(preferences: preferences)
            Hairline()
            MetricStrip(snapshot: snapshot, preferences: preferences, active: $activeSection)
            Hairline()
            DetailPane(section: activeSection, snapshot: snapshot)
        }
        .background(panelBackground)
        .overlay(
            Rectangle()
                .stroke(Brand.lineHi, lineWidth: 1)
                .allowsHitTesting(false)
        )
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
}

// MARK: - Header

private struct HeaderRow: View {
    let snapshot: SystemSnapshot
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
        HStack(alignment: .center, spacing: 10) {
            LiveryBar(tint: Brand.cpu)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("MENUSTAT")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(2.4)
                        .foregroundStyle(Brand.text)
                    Text("//")
                        .microLabel(Brand.micro)
                    Text("APPLE M-SERIES")
                        .microLabel()
                }
                HStack(spacing: 8) {
                    StatusDot(color: Brand.mem, isActive: isVisible)
                    Text("LIVE")
                        .microLabel(Brand.mute)
                    Text("·")
                        .microLabel(Brand.micro)
                    Text("REFRESH 5s")
                        .microLabel(Brand.mute)
                    Text("·")
                        .microLabel(Brand.micro)
                    Text("UP \(snapshot.uptime.uptimeShortString.uppercased())")
                        .microLabel(Brand.mute)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(Self.clockFormatter.string(from: date))
                    .numeric(15, weight: .bold)
                Text("T-\(timeAgo(from: snapshot.updatedAt, now: date))")
                    .microLabel(Brand.mute)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
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
            .frame(width: 3, height: 32)
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
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                Text("MENU")
                    .microLabel(Brand.micro)
                Picker("", selection: $preferences.primaryMetric) {
                    ForEach(MetricKind.allCases) { section in
                        Text(section.shortTitle).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: 12) {
                Text("SHOW")
                    .microLabel(Brand.micro)
                HStack(spacing: 6) {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isOn ? Brand.bg : Brand.mute)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: 38, height: 24)
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
        .frame(height: 112)
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

            VStack(alignment: .leading, spacing: 9) {
                Text(section.shortTitle)
                    .microLabel(active ? accent : Brand.mute)
                    .padding(.top, 6)

                Text(value)
                    .numeric(22, weight: .heavy, tint: active ? Brand.text : Brand.text.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                SegmentedBar(value: progress, tint: accent, segments: 12, lit: active)

                Text(caption)
                    .microLabel(Brand.mute)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 11)

            if active {
                CornerBrackets(tint: accent)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .background(active ? Brand.surface : Brand.bg)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(section: section, snapshot: snapshot)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .cpu:
                        CPUDetail(snapshot: snapshot)
                    case .memory:
                        MemoryDetail(snapshot: snapshot)
                    case .gpu:
                        GPUDetail(snapshot: snapshot)
                    case .pressure:
                        PressureDetail(snapshot: snapshot)
                    case .fans:
                        FanDetail(snapshot: snapshot)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
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
        HStack(alignment: .center, spacing: 12) {
            Rectangle()
                .fill(section.tint)
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(section.fullName)
                    .microLabel(section.tint)
                Text(subtitle)
                    .microLabel(Brand.mute)
                    .lineLimit(1)
            }

            Spacer()

            Text(valueText)
                .numeric(18, weight: .heavy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }
}

// MARK: - Section details

private struct CPUDetail: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MeterRow(label: "USER", value: snapshot.cpu.user, tint: Brand.cpu)
            MeterRow(label: "SYSTEM", value: snapshot.cpu.system, tint: Brand.pressure)
            MeterRow(label: "IDLE", value: snapshot.cpu.idle, tint: Brand.mute)

            DatumGrid(items: [
                DatumItem(label: "BUSIEST", value: snapshot.cpu.busiestCore.percentString),
                DatumItem(label: "LOGICAL", value: "\(snapshot.coreCount)"),
                DatumItem(label: "UPTIME", value: snapshot.uptime.uptimeDetailString),
                DatumItem(label: "NICE", value: snapshot.cpu.nice.percentString)
            ])

            CorePlot(values: snapshot.cpu.perCore)

            TopAppList(title: "TOP PROCESSES · CPU", apps: snapshot.apps.topCPU, kind: .cpu)
        }
    }
}

private struct MemoryDetail: View {
    let snapshot: SystemSnapshot

    private var memory: MemorySnapshot {
        snapshot.memory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MeterRow(label: "USED", value: memory.usedPercent, tint: Brand.mem)
            MeterRow(label: "AVAILABLE", value: memory.freePercent, tint: Brand.fan)

            DatumGrid(
                items: [
                    DatumItem(label: "TOTAL", value: memory.total.formattedBytesShort),
                    DatumItem(label: "USED", value: memory.used.formattedBytesShort),
                    DatumItem(label: "FREE", value: (memory.free + memory.inactive + memory.speculative).formattedBytesShort),
                    DatumItem(label: "ACTIVE", value: memory.active.formattedBytesShort),
                    DatumItem(label: "WIRED", value: memory.wired.formattedBytesShort),
                    DatumItem(label: "COMPR", value: memory.compressed.formattedBytesShort)
                ],
                columns: 3
            )

            TopAppList(title: "TOP PROCESSES · MEM", apps: snapshot.apps.topMemory, kind: .memory)
        }
    }
}

private struct GPUDetail: View {
    let snapshot: SystemSnapshot

    private var gpu: GPUSnapshot {
        snapshot.gpu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let utilization = gpu.utilization {
                MeterRow(label: "DEVICE", value: utilization, tint: Brand.gpu)
                MeterRow(label: "RENDER", value: gpu.rendererUtilization ?? 0, tint: Brand.cpu)
                MeterRow(label: "TILER", value: gpu.tilerUtilization ?? 0, tint: Brand.fan)

                DatumGrid(
                    items: [
                        DatumItem(label: "STATE", value: gpu.statusTitle.uppercased()),
                        DatumItem(label: "CORES", value: gpu.coreCount.map(String.init) ?? "--"),
                        DatumItem(label: "MEM", value: gpu.memoryBytes?.formattedBytesShort ?? "--"),
                        DatumItem(label: "MODEL", value: gpu.model ?? "Apple GPU"),
                        DatumItem(label: "SOURCE", value: gpu.source),
                        DatumItem(label: "LOAD", value: gpu.tileValue)
                    ],
                    columns: 3
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("NO GPU TELEMETRY")
                        .microLabel(Brand.alert)
                    Text(gpu.detail)
                        .bodyMono(Brand.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("SOURCE · \(gpu.source.uppercased())")
                        .microLabel(Brand.micro)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().stroke(Brand.alert.opacity(0.45), lineWidth: 1))
            }

            TopAppList(title: "TOP PROCESSES · CPU PROXY", apps: snapshot.apps.topCPU, kind: .cpu)
        }
    }
}

private struct PressureDetail: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PressureGauge(pressure: snapshot.pressure, usedPercent: snapshot.memory.usedPercent)

            DatumGrid(items: [
                DatumItem(label: "STATE", value: snapshot.pressure.shortTitle),
                DatumItem(label: "FREE PAGES", value: snapshot.memory.free.formattedBytesShort),
                DatumItem(label: "PAGE SIZE", value: snapshot.memory.pageSize.formattedBytesShort)
            ])

            TopAppList(title: "HEAT PROXY · LIKELY DRIVERS", apps: snapshot.apps.topHeat, kind: .heat)
        }
    }
}

private struct FanDetail: View {
    let snapshot: SystemSnapshot

    private var fans: FanSnapshot {
        snapshot.fans
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                    DatumItem(label: "STATE", value: "\(fans.percentTitle) · \(fans.statusTitle.uppercased())"),
                    DatumItem(label: "CURRENT", value: fans.rpmText),
                    DatumItem(label: "RANGE", value: fans.rangeText)
                ])

                Text("SOURCE · \(fans.source.uppercased())")
                    .microLabel(Brand.micro)
            }

            TopAppList(title: "LIKELY THERMAL DRIVERS", apps: snapshot.apps.topHeat, kind: .heat)
        }
    }
}

private struct EmptyFanReadout: View {
    let fans: FanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(11)
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
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(10)
        .background(Brand.surface)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .microLabel(Brand.mute)
                Spacer()
                Text(trailing ?? value.percentString)
                    .bodyMono(Brand.text, weight: .bold)
            }
            SegmentedBar(value: value, tint: tint, segments: 28)
        }
    }
}

private struct PressureGauge: View {
    let pressure: MemoryPressure
    let usedPercent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESSURE INDEX")
                .microLabel(Brand.mute)
            HStack(spacing: 6) {
                ForEach(MemoryPressure.allCases) { level in
                    PressureCell(level: level, active: level == pressure)
                }
            }
            SegmentedBar(value: usedPercent, tint: pressure.tint, segments: 36)
        }
        .padding(11)
        .background(Brand.surface)
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
    }
}

private struct CorePlot: View {
    let values: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PER-CORE ACTIVITY")
                    .microLabel(Brand.mute)
                Spacer()
                Text("\(values.count) CH")
                    .microLabel(Brand.micro)
            }
            if values.isEmpty {
                Rectangle()
                    .fill(Brand.surface)
                    .frame(height: 44)
                    .overlay(Text("WAITING FOR SAMPLE").microLabel(Brand.micro))
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 4) {
                            CoreBar(value: value)
                            Text(String(format: "%02d", index))
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(Brand.micro)
                        }
                    }
                }
                .frame(height: 56)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Brand.surface)
            }
        }
    }
}

private struct CoreBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(1, value))
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Brand.line)
                Rectangle()
                    .fill(barColor(clamped))
                    .frame(height: max(2, proxy.size.height * clamped))
            }
        }
        .frame(height: 40)
    }

    private func barColor(_ value: Double) -> Color {
        switch value {
        case 0.85...: Brand.alert
        case 0.55..<0.85: Brand.pressure
        default: Brand.cpu
        }
    }
}

// MARK: - Tables

private struct DatumItem: Identifiable {
    let label: String
    let value: String
    var id: String {
        label
    }
}

private struct DatumGrid: View {
    let items: [DatumItem]
    var columns = 3

    private var rows: [[DatumItem]] {
        stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { colIndex, item in
                        DatumCell(item: item)
                        if colIndex < row.count - 1 {
                            VRule()
                        }
                    }
                }
                if rowIndex < rows.count - 1 {
                    Hairline()
                }
            }
        }
        .overlay(Rectangle().stroke(Brand.line, lineWidth: 1))
    }
}

private struct DatumCell: View {
    let item: DatumItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label)
                .microLabel(Brand.mute)
            Text(item.value)
                .bodyMono(Brand.text, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum TopAppKind {
    case cpu
    case memory
    case heat

    var tint: Color {
        switch self {
        case .cpu: Brand.cpu
        case .memory: Brand.mem
        case .heat: Brand.pressure
        }
    }
}

private struct TopAppList: View {
    let title: String
    let apps: [AppUsage]
    let kind: TopAppKind

    private var maxValue: Double {
        apps.map(value(for:)).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .microLabel(Brand.mute)
                Spacer()
                Text("\(apps.count) ROWS")
                    .microLabel(Brand.micro)
            }
            if apps.isEmpty {
                Text("NO SAMPLE")
                    .microLabel(Brand.micro)
                    .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(apps.prefix(8).enumerated()), id: \.element.id) { index, app in
                        TopAppRow(rank: index + 1, app: app, kind: kind, ratio: value(for: app) / max(maxValue, 1))
                    }
                }
                .background(Brand.surface)
            }
        }
    }

    private func value(for app: AppUsage) -> Double {
        switch kind {
        case .cpu: app.cpuPercent
        case .memory: Double(app.memoryBytes)
        case .heat: app.heatScore
        }
    }
}

private struct TopAppRow: View {
    let rank: Int
    let app: AppUsage
    let kind: TopAppKind
    let ratio: Double

    private var trailing: String {
        switch kind {
        case .cpu: app.cpuDisplay
        case .memory: app.memoryBytes.formattedBytesShort
        case .heat: app.heatDisplay
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(kind.tint.opacity(0.13))
                    .frame(width: proxy.size.width * max(0, min(1, ratio)))
            }

            HStack(spacing: 8) {
                Text(String(format: "%02d", rank))
                    .microLabel(Brand.micro)
                Text(app.name)
                    .bodyMono(Brand.text, weight: .semibold)
                    .lineLimit(1)
                Spacer()
                Text(trailing)
                    .bodyMono(Brand.text, weight: .bold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 30)
    }
}

// MARK: - Hairlines and overlays

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Brand.line)
            .frame(height: 1)
    }
}

private struct VRule: View {
    var body: some View {
        Rectangle()
            .fill(Brand.line)
            .frame(width: 1)
    }
}

private struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 3
            let line = Path { path in
                var y: CGFloat = 0
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
            }
            context.stroke(line, with: .color(.white.opacity(0.022)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private struct VignetteOverlay: View {
    var body: some View {
        RadialGradient(
            colors: [.clear, .black.opacity(0.35)],
            center: .center,
            startRadius: 80,
            endRadius: 420
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Snapshot helpers

private extension MetricKind {
    func tileValue(_ snapshot: SystemSnapshot) -> String {
        switch self {
        case .cpu: snapshot.cpu.total.percentString
        case .memory: snapshot.memory.usedPercent.percentString
        case .gpu: snapshot.gpu.tileValue
        case .pressure: snapshot.pressure.shortTitle
        case .fans: snapshot.fans.tileValue
        }
    }

    func progress(_ snapshot: SystemSnapshot) -> Double {
        switch self {
        case .cpu: snapshot.cpu.total
        case .memory: snapshot.memory.usedPercent
        case .gpu: snapshot.gpu.utilization ?? 0
        case .pressure: snapshot.memory.usedPercent
        case .fans: snapshot.fans.averageRangePercent
        }
    }

    func tileCaption(_ snapshot: SystemSnapshot) -> String {
        switch self {
        case .cpu: "\(snapshot.coreCount) CORES"
        case .memory: snapshot.memory.used.formattedBytesShort
        case .gpu: snapshot.gpu.tileCaption
        case .pressure: "RAM STATE"
        case .fans: snapshot.fans.tileCaption
        }
    }
}

private extension MemoryPressure {
    var tint: Color {
        switch self {
        case .normal: Brand.mem
        case .moderate: Brand.pressure
        case .high: Brand.alert
        }
    }

    var shortTitle: String {
        switch self {
        case .normal: "NORMAL"
        case .moderate: "ELEVATED"
        case .high: "CRITICAL"
        }
    }
}

extension MemoryPressure: CaseIterable, Identifiable {
    public static var allCases: [MemoryPressure] {
        [.normal, .moderate, .high]
    }

    public var id: String {
        shortTitle
    }
}

private extension FanSnapshot {
    var tileValue: String {
        if speeds.isEmpty { return "—" }
        return percentTitle
    }

    var tileCaption: String {
        if speeds.isEmpty { return "OFFLINE" }
        return statusTitle.uppercased()
    }
}

private extension UInt64 {
    var formattedBytesShort: String {
        ByteFormatters.shortBytes.string(fromByteCount: Int64(self)).replacingOccurrences(of: " ", with: "")
    }
}

private enum ByteFormatters {
    static let shortBytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()
}
