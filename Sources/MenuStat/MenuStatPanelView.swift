import SwiftUI

private enum MetricSection: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case pressure = "Pressure"
    case fans = "Fans"

    var id: String {
        rawValue
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .pressure: "gauge.with.dots.needle.50percent"
        case .fans: "fan"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: .blue
        case .memory: .green
        case .pressure: .orange
        case .fans: .cyan
        }
    }
}

struct MenuStatPanelView: View {
    let snapshot: SystemSnapshot
    @State private var hoveredSection: MetricSection? = .cpu

    private var activeSection: MetricSection {
        hoveredSection ?? .cpu
    }

    var body: some View {
        VStack(spacing: 12) {
            HeaderLayer(snapshot: snapshot)

            MetricStrip(
                snapshot: snapshot,
                activeSection: activeSection,
                hoveredSection: $hoveredSection
            )

            DetailLayer(section: activeSection, snapshot: snapshot)
                .frame(height: 248, alignment: .top)
                .animation(.snappy(duration: 0.18), value: activeSection.id)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
        }
    }
}

private struct HeaderLayer: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("MenuStat")
                    .font(.system(size: 21, weight: .bold, design: .rounded))

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Apple M-series")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Refreshes every 5s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(snapshot.updatedAt, style: .time)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                HealthPill(title: "CPU", value: snapshot.cpu.total.percentString, tint: .blue)
                HealthPill(title: "RAM", value: snapshot.memory.usedPercent.percentString, tint: .green)
                HealthPill(title: "Fans", value: snapshot.fans.compactStatus, tint: .cyan)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.blue, .green, .cyan], startPoint: .leading, endPoint: .trailing)
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.horizontal, 14)
        }
    }
}

private struct HealthPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct MetricStrip: View {
    let snapshot: SystemSnapshot
    let activeSection: MetricSection
    @Binding var hoveredSection: MetricSection?

    var body: some View {
        HStack(spacing: 7) {
            MetricTile(
                section: .cpu,
                value: snapshot.cpu.total.percentString,
                caption: "\(snapshot.coreCount) cores",
                progress: snapshot.cpu.total,
                tint: .blue,
                isActive: activeSection == .cpu,
                hoveredSection: $hoveredSection
            )

            MetricTile(
                section: .memory,
                value: snapshot.memory.usedPercent.percentString,
                caption: snapshot.memory.used.formattedBytes,
                progress: snapshot.memory.usedPercent,
                tint: .green,
                isActive: activeSection == .memory,
                hoveredSection: $hoveredSection
            )

            MetricTile(
                section: .pressure,
                value: snapshot.pressure.title,
                caption: "RAM state",
                progress: snapshot.memory.usedPercent,
                tint: snapshot.pressure.tint,
                isActive: activeSection == .pressure,
                hoveredSection: $hoveredSection
            )

            MetricTile(
                section: .fans,
                value: snapshot.fans.statusTitle,
                caption: snapshot.fans.shortDetail,
                progress: snapshot.fans.averageRangePercent,
                tint: .cyan,
                isActive: activeSection == .fans,
                hoveredSection: $hoveredSection
            )
        }
    }
}

private struct MetricTile: View {
    let section: MetricSection
    let value: String
    let caption: String
    let progress: Double
    let tint: Color
    let isActive: Bool
    @Binding var hoveredSection: MetricSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 17)

                Text(section.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .monospacedDigit()

            Text(caption)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            ProgressBar(value: progress, tint: tint, height: 4)
                .opacity(isActive ? 1 : 0.62)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isActive ? .regularMaterial : .thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isActive ? tint.opacity(0.55) : .white.opacity(0.06), lineWidth: 1)
                }
        }
        .shadow(color: isActive ? tint.opacity(0.12) : .clear, radius: 12, y: 5)
        .scaleEffect(isActive ? 1.015 : 1)
        .onHover { hovering in
            if hovering {
                hoveredSection = section
            }
        }
        .onTapGesture {
            hoveredSection = section
        }
        .help("Show detailed \(section.rawValue.lowercased()) metrics")
    }
}

private struct DetailLayer: View {
    let section: MetricSection
    let snapshot: SystemSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DetailHeader(section: section, snapshot: snapshot)

                Divider()
                    .opacity(0.35)

                Group {
                    switch section {
                    case .cpu:
                        CPUDetail(snapshot: snapshot)
                    case .memory:
                        MemoryDetail(snapshot: snapshot)
                    case .pressure:
                        PressureDetail(snapshot: snapshot)
                    case .fans:
                        FanDetail(snapshot: snapshot)
                    }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.never)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
        }
    }
}

private struct DetailHeader: View {
    let section: MetricSection
    let snapshot: SystemSnapshot

    private var value: String {
        switch section {
        case .cpu: snapshot.cpu.total.percentString
        case .memory: snapshot.memory.usedPercent.percentString
        case .pressure: snapshot.pressure.title
        case .fans: snapshot.fans.compactStatus
        }
    }

    private var subtitle: String {
        switch section {
        case .cpu: "Load split and per-core activity"
        case .memory: "Unified memory pressure and page state"
        case .pressure: snapshot.pressure.detail
        case .fans: "Fan RPM and cooling level"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle()
                    .fill(section.tint.opacity(0.16))
                Image(systemName: section.symbolName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(section.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.rawValue)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct CPUDetail: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Meter(label: "User", value: snapshot.cpu.user, tint: .blue)
            Meter(label: "System", value: snapshot.cpu.system, tint: .orange)
            Meter(label: "Idle", value: snapshot.cpu.idle, tint: .gray)

            HStack(spacing: 10) {
                DetailDatum(title: "Busiest core", value: snapshot.cpu.busiestCore.percentString)
                DetailDatum(title: "Logical cores", value: "\(snapshot.coreCount)")
                DetailDatum(title: "Nice", value: snapshot.cpu.nice.percentString)
            }

            CoreGrid(values: snapshot.cpu.perCore)

            TopAppsList(title: "Top CPU apps", apps: snapshot.apps.topCPU, metric: .cpu)
        }
    }
}

private struct MemoryDetail: View {
    let snapshot: SystemSnapshot

    private var memory: MemorySnapshot {
        snapshot.memory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Meter(label: "Used", value: memory.usedPercent, tint: .green)
            Meter(label: "Available", value: memory.freePercent, tint: .mint)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                DetailDatum(title: "Total", value: memory.total.formattedBytes)
                DetailDatum(title: "Used", value: memory.used.formattedBytes)
                DetailDatum(title: "Available", value: (memory.free + memory.inactive + memory.speculative).formattedBytes)
                DetailDatum(title: "Active", value: memory.active.formattedBytes)
                DetailDatum(title: "Wired", value: memory.wired.formattedBytes)
                DetailDatum(title: "Compressed", value: memory.compressed.formattedBytes)
            }

            TopAppsList(title: "Top memory apps", apps: snapshot.apps.topMemory, metric: .memory)
        }
    }
}

private struct PressureDetail: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Meter(label: "RAM used", value: snapshot.memory.usedPercent, tint: snapshot.pressure.tint)
            Meter(label: "Available", value: snapshot.memory.freePercent, tint: .mint)

            HStack(spacing: 10) {
                DetailDatum(title: "Pressure", value: snapshot.pressure.title)
                DetailDatum(title: "Free pages", value: snapshot.memory.free.formattedBytes)
                DetailDatum(title: "Page size", value: snapshot.memory.pageSize.formattedBytes)
            }

            TopAppsList(title: "Heat proxy", apps: snapshot.apps.topHeat, metric: .heat)
        }
    }
}

private struct FanDetail: View {
    let snapshot: SystemSnapshot

    private var fans: FanSnapshot {
        snapshot.fans
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if fans.speeds.isEmpty {
                Text(fans.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                DetailDatum(title: "Probe source", value: fans.source)
                if !fans.attemptedKeys.isEmpty {
                    DetailDatum(title: "SMC keys tried", value: fans.attemptedKeys.joined(separator: ", "))
                }
            } else {
                ForEach(Array(fans.speeds.enumerated()), id: \.offset) { index, speed in
                    Meter(
                        label: "Fan \(index)",
                        value: fans.rangePercent(at: index),
                        tint: .cyan,
                        trailing: "\(speed) RPM • \(fans.rangePercentTitle(at: index))"
                    )
                }

                HStack(spacing: 10) {
                    DetailDatum(title: "State", value: "\(fans.percentTitle) • \(fans.statusTitle)")
                    DetailDatum(title: "Current", value: fans.rpmText)
                    DetailDatum(title: "Range", value: fans.rangeText)
                }

                DetailDatum(title: "Source", value: fans.source)
            }

            TopAppsList(title: "Likely fan drivers", apps: snapshot.apps.topHeat, metric: .heat)
        }
    }
}

private enum AppMetricKind {
    case cpu
    case memory
    case heat

    var tint: Color {
        switch self {
        case .cpu: .blue
        case .memory: .green
        case .heat: .orange
        }
    }
}

private struct TopAppsList: View {
    let title: String
    let apps: [AppUsage]
    let metric: AppMetricKind

    private var maxValue: Double {
        let values = apps.map(value(for:))
        return max(values.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            if apps.isEmpty {
                Text("No app samples")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        AppUsageRow(
                            rank: index + 1,
                            app: app,
                            metric: metric,
                            value: value(for: app),
                            maxValue: maxValue
                        )
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func value(for app: AppUsage) -> Double {
        switch metric {
        case .cpu:
            app.cpuPercent
        case .memory:
            Double(app.memoryBytes)
        case .heat:
            app.heatScore
        }
    }
}

private struct AppUsageRow: View {
    let rank: Int
    let app: AppUsage
    let metric: AppMetricKind
    let value: Double
    let maxValue: Double

    private var trailing: String {
        switch metric {
        case .cpu:
            app.cpuDisplay
        case .memory:
            app.memoryBytes.formattedBytes
        case .heat:
            app.heatDisplay
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer()

                    Text(trailing)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                }

                ProgressBar(value: value / maxValue, tint: metric.tint, height: 4)
            }
        }
        .padding(7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct DetailDatum: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct Meter: View {
    let label: String
    let value: Double
    let tint: Color
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .fontWeight(.semibold)
                Spacer()
                Text(trailing ?? value.percentString)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .font(.system(size: 12))

            ProgressBar(value: value, tint: tint, height: 7)
        }
    }
}

private struct ProgressBar: View {
    let value: Double
    let tint: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, proxy.size.width * max(0, min(1, value))))
            }
        }
        .frame(height: height)
    }
}

private struct CoreGrid: View {
    let values: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if values.isEmpty {
                EmptyView()
            } else {
                Text("Per-core activity")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 4) {
                            GeometryReader { proxy in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(.quaternary)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.blue.gradient)
                                        .frame(height: max(3, proxy.size.height * max(0, min(1, value))))
                                }
                            }
                            .frame(height: 32)

                            Text("\(index)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .help("Core \(index): \(value.percentString)")
                    }
                }
            }
        }
    }
}

private extension MemoryPressure {
    var tint: Color {
        switch self {
        case .normal: .green
        case .moderate: .yellow
        case .high: .red
        }
    }
}

private extension FanSnapshot {
    var shortDetail: String {
        if !speeds.isEmpty {
            if speeds.count == 1 {
                return "\(percentTitle) • \(rpmText)"
            }
            return "\(percentTitle) • \(speeds.count) fans"
        }
        return "Probe"
    }

    var compactStatus: String {
        if !speeds.isEmpty {
            return "\(percentTitle) • \(statusTitle)"
        }
        return statusTitle
    }
}
