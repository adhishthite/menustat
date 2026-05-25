import ArgumentParser
import Foundation
import MenuStatCore

enum TopSort: String, CaseIterable, ExpressibleByArgument {
    case cpu
    case memory
    case heat
}

enum CLIRenderer {
    static func dashboard(snapshot: SystemSnapshot, interval: Double, width: Int = 88) -> String {
        let ruler = String(repeating: "-", count: max(44, min(width, 110)))
        let cpuLine = "CPU      \(snapshot.cpu.total.percentString)  user \(snapshot.cpu.user.percentString)  "
            + "system \(snapshot.cpu.system.percentString)  busiest \(snapshot.cpu.busiestCore.percentString)"
        let memoryLine = "Memory   \(snapshot.memory.used.formattedBytes) / \(snapshot.memory.total.formattedBytes)  "
            + "used \(snapshot.memory.usedPercent.percentString)  available \(snapshot.memory.availableBytes.formattedBytes)"
        let gpuLine = "GPU      \(snapshot.gpu.tileValue)  renderer \(snapshot.gpu.rendererUtilization?.percentString ?? "--")  "
            + "tiler \(snapshot.gpu.tilerUtilization?.percentString ?? "--")  "
            + "mem \(snapshot.gpu.memoryBytes?.formattedBytes ?? "--")"
        return [
            "MenuStat \(snapshot.updatedAt.cliTimestamp)    refresh \(interval.cleanSeconds)s    press q to quit",
            ruler,
            cpuLine,
            memoryLine,
            gpuLine,
            "Pressure \(snapshot.pressure.title)  \(snapshot.pressure.detail)",
            "Fans     \(snapshot.fans.statusTitle)  \(snapshot.fans.rpmText)  range \(snapshot.fans.rangeText)",
            "Uptime   \(snapshot.uptime.uptimeDetailString)",
            "",
            top(snapshot: snapshot, sort: .heat, limit: 6)
        ].joined(separator: "\n")
    }

    static func plainSnapshot(snapshot: SystemSnapshot) -> String {
        let cpuLine = "CPU: \(snapshot.cpu.total.percentString) total, \(snapshot.cpu.user.percentString) user, "
            + "\(snapshot.cpu.system.percentString) system, busiest core \(snapshot.cpu.busiestCore.percentString)"
        let memoryLine = "Memory: \(snapshot.memory.used.formattedBytes) used of \(snapshot.memory.total.formattedBytes) "
            + "(\(snapshot.memory.usedPercent.percentString)); \(snapshot.memory.availableBytes.formattedBytes) available"
        let gpuLine = "GPU: \(snapshot.gpu.tileValue) device, renderer \(snapshot.gpu.rendererUtilization?.percentString ?? "--"), "
            + "tiler \(snapshot.gpu.tilerUtilization?.percentString ?? "--"), "
            + "memory \(snapshot.gpu.memoryBytes?.formattedBytes ?? "--")"
        return [
            "MenuStat snapshot \(snapshot.updatedAt.cliTimestamp)",
            cpuLine,
            memoryLine,
            gpuLine,
            "Pressure: \(snapshot.pressure.title) - \(snapshot.pressure.detail)",
            "Fans: \(snapshot.fans.statusTitle), \(snapshot.fans.rpmText), range \(snapshot.fans.rangeText), \(snapshot.fans.detail)",
            "Uptime: \(snapshot.uptime.uptimeDetailString)",
            top(snapshot: snapshot, sort: .heat, limit: 5)
        ].joined(separator: "\n")
    }

    static func top(snapshot: SystemSnapshot, sort: TopSort, limit: Int) -> String {
        let apps = topApps(snapshot: snapshot, sort: sort, limit: limit)
        let title = "Top apps by \(sort.rawValue)"
        guard !apps.isEmpty else {
            return "\(title)\n  No app usage yet."
        }

        let rows = apps.enumerated().map { index, app in
            let name = app.name.truncated(to: 24).padding(toLength: 24, withPad: " ", startingAt: 0)
            let rank = "\(index + 1).".leftPadded(to: 3)
            return "\(rank) \(name)  "
                + "cpu \(app.cpuDisplay.leftPadded(to: 7))  "
                + "mem \(app.memoryBytes.formattedBytes.leftPadded(to: 9))  "
                + "heat \(app.heatDisplay.leftPadded(to: 5))"
        }
        return ([title] + rows).joined(separator: "\n")
    }

    static func fans(snapshot: SystemSnapshot) -> String {
        let fans = snapshot.fans
        return [
            "Fans: \(fans.statusTitle)",
            "Source: \(fans.source)",
            "RPM: \(fans.rpmText)",
            "Range: \(fans.rangeText) (\(fans.percentTitle))",
            "Detail: \(fans.detail)"
        ].joined(separator: "\n")
    }

    static func topApps(snapshot: SystemSnapshot, sort: TopSort, limit: Int) -> [AppUsage] {
        let apps: [AppUsage] = switch sort {
        case .cpu:
            snapshot.apps.topCPU
        case .memory:
            snapshot.apps.topMemory
        case .heat:
            snapshot.apps.topHeat
        }
        return Array(apps.prefix(limit))
    }
}

private extension MemorySnapshot {
    var availableBytes: UInt64 {
        free + inactive + speculative
    }
}

private extension Date {
    var cliTimestamp: String {
        CLIFormatters.timestamp.string(from: self)
    }
}

private extension String {
    func truncated(to length: Int) -> String {
        guard count > length else { return self }
        guard length > 3 else { return String(prefix(length)) }
        return String(prefix(length - 3)) + "..."
    }

    func leftPadded(to length: Int) -> String {
        guard count < length else { return self }
        return String(repeating: " ", count: length - count) + self
    }
}

private extension Double {
    var cleanSeconds: String {
        if rounded() == self {
            return String(Int(self))
        }
        return formatted(.number.precision(.fractionLength(1)))
    }
}

private enum CLIFormatters {
    static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
