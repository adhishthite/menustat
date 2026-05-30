import MenuStatCore
import SwiftUI

// MARK: - Tables

struct DatumItem: Identifiable {
    let label: String
    let value: String
    var help: String?
    var id: String {
        label
    }
}

struct DatumGrid: View {
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

struct DatumCell: View {
    let item: DatumItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.label)
                .microLabel(Brand.mute)
            Text(item.value)
                .bodyMono(Brand.text, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverHelp(item.help ?? "\(item.label): \(item.value)")
    }
}

enum TopAppKind {
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

extension TopAppKind {
    var helpText: String {
        switch self {
        case .cpu:
            "Apps grouped by sampled CPU time. This is per-app activity, not the same as total system CPU."
        case .memory:
            "Apps grouped by resident memory. This helps identify which processes are occupying unified memory."
        case .heat:
            "A lightweight driver score combining CPU activity and memory footprint to suggest likely thermal or pressure contributors."
        }
    }

    func rowHelp(_ app: AppUsage) -> String {
        switch self {
        case .cpu:
            "\(app.name) used \(app.cpuDisplay) CPU during the app-usage sample."
        case .memory:
            "\(app.name) is using \(app.memoryBytes.formattedBytesShort) resident memory."
        case .heat:
            "\(app.name) has heat score \(app.heatDisplay), based on CPU activity plus memory footprint."
        }
    }
}

struct TopAppList: View {
    let title: String
    let apps: [AppUsage]
    let kind: TopAppKind
    let limit: Int
    var note: String?

    private var visibleApps: [AppUsage] {
        Array(apps.prefix(max(1, limit)))
    }

    private var maxValue: Double {
        visibleApps.map(value(for:)).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .microLabel(Brand.mute)
                Spacer()
                Text("\(visibleApps.count) ROWS")
                    .microLabel(Brand.micro)
            }
            if visibleApps.isEmpty {
                Text("NO SAMPLE")
                    .microLabel(Brand.micro)
                    .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(visibleApps.enumerated()), id: \.element.id) { index, app in
                        TopAppRow(rank: index + 1, app: app, kind: kind, ratio: value(for: app) / max(maxValue, 1))
                    }
                }
                .background(Brand.surface)
            }
            if let note {
                Text(note)
                    .microLabel(Brand.micro)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .hoverHelp(kind.helpText)
    }

    private func value(for app: AppUsage) -> Double {
        switch kind {
        case .cpu: app.cpuPercent
        case .memory: Double(app.memoryBytes)
        case .heat: app.heatScore
        }
    }
}

struct TopAppRow: View {
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

            HStack(spacing: 12) {
                Text(String(format: "%02d", rank))
                    .microLabel(Brand.micro)
                Text(app.name)
                    .bodyMono(Brand.text, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(trailing)
                    .bodyMono(Brand.text, weight: .bold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(height: 42)
        .hoverHelp(kind.rowHelp(app))
    }
}

extension MemoryPressure {
    var helpText: String {
        switch self {
        case .normal:
            "Normal memory pressure. macOS has enough room without aggressive reclaiming."
        case .moderate:
            "Moderate memory pressure. macOS is working harder to reclaim or compress memory."
        case .high:
            "High memory pressure. Apps may slow down as macOS compresses memory or swaps."
        }
    }
}

// MARK: - Hairlines and overlays

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Brand.line)
            .frame(height: 1)
    }
}

struct VRule: View {
    var body: some View {
        Rectangle()
            .fill(Brand.line)
            .frame(width: 1)
    }
}

struct ScanlineOverlay: View {
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

struct VignetteOverlay: View {
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

extension MetricKind {
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

    var tileHelp: String {
        switch self {
        case .cpu:
            "Total system CPU load across all logical cores. Open CPU for user, system, idle, nice, and per-core detail."
        case .memory:
            "Unified memory currently in use. Open MEM for active, wired, compressed, and available memory."
        case .gpu:
            "Apple AGX GPU utilization, when macOS exposes it. Open GPU for renderer, tiler, memory, and source detail."
        case .pressure:
            "macOS memory pressure state. This tells you whether memory demand is causing reclaim, compression, or paging."
        case .fans:
            "Fan speed normalized against the reported RPM range. Fanless Macs show unavailable telemetry."
        }
    }

    var detailHelp: String {
        switch self {
        case .cpu:
            "CPU detail separates total system load into user, system, idle, nice, per-core activity, and top app contributors."
        case .memory:
            "Memory detail shows how unified memory is split across active, wired, compressed, free, inactive, and speculative pages."
        case .gpu:
            "GPU detail reads AGX counters from IORegistry where available, including device, renderer, and tiler utilization."
        case .pressure:
            "Pressure detail combines macOS memory pressure with likely driver processes."
        case .fans:
            "Fan detail shows current RPM, normalized range, source, and likely thermal driver processes."
        }
    }
}

extension MemoryPressure {
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

extension FanSnapshot {
    var tileValue: String {
        if speeds.isEmpty { return "—" }
        return percentTitle
    }

    var tileCaption: String {
        if speeds.isEmpty { return "OFFLINE" }
        return statusTitle.uppercased()
    }
}

extension UInt64 {
    var formattedBytesShort: String {
        ByteFormatters.shortBytes.string(fromByteCount: Int64(self)).replacingOccurrences(of: " ", with: "")
    }
}

enum ByteFormatters {
    static let shortBytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()
}
