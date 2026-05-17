import Darwin
import Foundation
import MachO

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.empty

    private let sampler = SystemSampler()
    private var timer: Timer?

    init() {
        #if !arch(arm64)
        snapshot = SystemSnapshot.unsupported
        return
        #endif

        snapshot = sampler.sample()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                snapshot = sampler.sample()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}

struct SystemSnapshot {
    let cpu: CPUSnapshot
    let coreCount: Int
    let memory: MemorySnapshot
    let pressure: MemoryPressure
    let fans: FanSnapshot
    let apps: AppUsageSnapshot
    let uptime: TimeInterval
    let updatedAt: Date

    var menuTitle: String {
        "CPU \(cpu.total.percentString)  RAM \(memory.usedPercent.percentString)"
    }

    static let empty = SystemSnapshot(
        cpu: .empty,
        coreCount: ProcessInfo.processInfo.processorCount,
        memory: .unavailable(total: ProcessInfo.processInfo.physicalMemory),
        pressure: .normal,
        fans: .unavailable("Checking fan sensors"),
        apps: .empty,
        uptime: ProcessInfo.processInfo.systemUptime,
        updatedAt: Date()
    )

    static let unsupported = SystemSnapshot(
        cpu: .empty,
        coreCount: ProcessInfo.processInfo.processorCount,
        memory: .unavailable(total: ProcessInfo.processInfo.physicalMemory),
        pressure: .normal,
        fans: .unavailable("MenuStat is designed for Apple Silicon Macs only."),
        apps: .empty,
        uptime: ProcessInfo.processInfo.systemUptime,
        updatedAt: Date()
    )
}

struct CPUSnapshot {
    let total: Double
    let user: Double
    let system: Double
    let idle: Double
    let nice: Double
    let perCore: [Double]

    var busiestCore: Double {
        perCore.max() ?? total
    }

    static let empty = CPUSnapshot(total: 0, user: 0, system: 0, idle: 1, nice: 0, perCore: [])
}

struct MemorySnapshot {
    let total: UInt64
    let used: UInt64
    let free: UInt64
    let active: UInt64
    let inactive: UInt64
    let wired: UInt64
    let compressed: UInt64
    let speculative: UInt64
    let pageSize: UInt64

    var usedPercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }

    var freePercent: Double {
        guard total > 0 else { return 0 }
        return Double(free + inactive + speculative) / Double(total)
    }

    static func unavailable(total: UInt64) -> MemorySnapshot {
        MemorySnapshot(
            total: total,
            used: 0,
            free: 0,
            active: 0,
            inactive: 0,
            wired: 0,
            compressed: 0,
            speculative: 0,
            pageSize: UInt64(vm_kernel_page_size)
        )
    }
}

enum MemoryPressure {
    case normal
    case moderate
    case high

    var title: String {
        switch self {
        case .normal: "Normal"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }

    var detail: String {
        switch self {
        case .normal: "Plenty of readily available memory."
        case .moderate: "Memory is getting tighter."
        case .high: "Memory pressure is high."
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "gauge.with.dots.needle.0percent"
        case .moderate: "gauge.with.dots.needle.50percent"
        case .high: "gauge.with.dots.needle.100percent"
        }
    }
}

struct FanSnapshot {
    private static let stoppedRPMThreshold = 100

    let speeds: [Int]
    let minSpeeds: [Int]
    let maxSpeeds: [Int]
    let message: String?
    let source: String
    let attemptedKeys: [String]

    var isMoving: Bool? {
        guard !speeds.isEmpty else { return nil }
        return speeds.contains { $0 > Self.stoppedRPMThreshold }
    }

    var averageRangePercent: Double {
        guard !speeds.isEmpty else { return 0 }
        let total = speeds.indices.reduce(0) { partial, index in
            partial + rangePercent(at: index)
        }
        return total / Double(speeds.count)
    }

    var averageSpeed: Int {
        guard !speeds.isEmpty else { return 0 }
        return Int((Double(speeds.reduce(0, +)) / Double(speeds.count)).rounded())
    }

    var peakSpeed: Int {
        speeds.max() ?? 0
    }

    var percentTitle: String {
        "\(Int((averageRangePercent * 100).rounded()))%"
    }

    var rpmText: String {
        guard !speeds.isEmpty else { return "No RPM" }
        if speeds.count == 1, let speed = speeds.first {
            return "\(speed) RPM"
        }
        return speeds.map(String.init).joined(separator: " / ") + " RPM"
    }

    var rangeText: String {
        let validMinimums = minSpeeds.filter { $0 > 0 }
        let validMaximums = maxSpeeds.filter { $0 > 0 }
        guard let minimum = validMinimums.min(), let maximum = validMaximums.max(), maximum > minimum else {
            return "Unknown"
        }
        return "\(minimum)-\(maximum) RPM"
    }

    var statusTitle: String {
        guard !speeds.isEmpty else { return "Unavailable" }
        guard isMoving == true else { return "Off" }
        switch averageRangePercent {
        case ..<0.30:
            return "Quiet"
        case ..<0.70:
            return "Cooling"
        default:
            return "High"
        }
    }

    var detail: String {
        if !speeds.isEmpty {
            return speeds.enumerated().map { index, speed in
                let minimum = minSpeed(at: index).map { ", min \($0)" } ?? ""
                let maximum = maxSpeed(at: index).map { ", max \($0)" } ?? ""
                return "Fan \(index): \(speed) RPM\(minimum)\(maximum)"
            }
            .joined(separator: ", ")
        }
        return message ?? "This Apple Silicon Mac does not expose fan RPM sensors."
    }

    func minSpeed(at index: Int) -> Int? {
        guard minSpeeds.indices.contains(index), minSpeeds[index] > 0 else { return nil }
        return minSpeeds[index]
    }

    func maxSpeed(at index: Int) -> Int? {
        guard maxSpeeds.indices.contains(index), maxSpeeds[index] > 0 else { return nil }
        return maxSpeeds[index]
    }

    func rangePercent(at index: Int) -> Double {
        guard speeds.indices.contains(index) else { return 0 }
        let speed = speeds[index]
        if let minimum = minSpeed(at: index), let maximum = maxSpeed(at: index), maximum > minimum {
            return Self.clamped(Double(speed - minimum) / Double(maximum - minimum))
        }
        if let maximum = maxSpeed(at: index), maximum > 0 {
            return Self.clamped(Double(speed) / Double(maximum))
        }
        return Self.clamped(Double(speed) / 7000)
    }

    func rangePercentTitle(at index: Int) -> String {
        "\(Int((rangePercent(at: index) * 100).rounded()))%"
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func unavailable(_ message: String) -> FanSnapshot {
        FanSnapshot(speeds: [], minSpeeds: [], maxSpeeds: [], message: message, source: "AppleSMC", attemptedKeys: [])
    }

    static func unavailable(_ message: String, source: String, attemptedKeys: [String]) -> FanSnapshot {
        FanSnapshot(speeds: [], minSpeeds: [], maxSpeeds: [], message: message, source: source, attemptedKeys: attemptedKeys)
    }
}

struct AppUsageSnapshot {
    let topCPU: [AppUsage]
    let topMemory: [AppUsage]
    let topHeat: [AppUsage]

    static let empty = AppUsageSnapshot(topCPU: [], topMemory: [], topHeat: [])
}

struct AppUsage: Identifiable {
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let heatScore: Double

    var id: String {
        name
    }

    var cpuDisplay: String {
        if cpuPercent >= 10 {
            return "\(Int(cpuPercent.rounded()))%"
        }
        return "\(cpuPercent.formatted(.number.precision(.fractionLength(1))))%"
    }

    var heatDisplay: String {
        "\(Int(heatScore.rounded()))"
    }
}

final class SystemSampler {
    private var previousCPULoad: host_cpu_load_info?
    private var previousCoreLoads: [host_cpu_load_info] = []
    private let fanReader = SMCFanReader()

    func sample() -> SystemSnapshot {
        let memory = sampleMemory()
        return SystemSnapshot(
            cpu: sampleCPU(),
            coreCount: ProcessInfo.processInfo.processorCount,
            memory: memory,
            pressure: pressure(for: memory),
            fans: fanReader.readFans(),
            apps: sampleAppUsage(totalMemory: memory.total),
            uptime: ProcessInfo.processInfo.systemUptime,
            updatedAt: Date()
        )
    }

    private func sampleCPU() -> CPUSnapshot {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return .empty }
        defer { previousCPULoad = cpuLoad }
        guard let previous = previousCPULoad else { return .empty }

        let user = Double(cpuLoad.cpu_ticks.0 - previous.cpu_ticks.0)
        let system = Double(cpuLoad.cpu_ticks.1 - previous.cpu_ticks.1)
        let idle = Double(cpuLoad.cpu_ticks.2 - previous.cpu_ticks.2)
        let nice = Double(cpuLoad.cpu_ticks.3 - previous.cpu_ticks.3)
        let total = user + system + idle + nice

        guard total > 0 else { return .empty }
        let perCore = samplePerCoreCPU()
        return CPUSnapshot(
            total: max(0, min(1, (total - idle) / total)),
            user: user / total,
            system: system / total,
            idle: idle / total,
            nice: nice / total,
            perCore: perCore
        )
    }

    private func samplePerCoreCPU() -> [Double] {
        var processorInfo: processor_info_array_t?
        var processorMsgCount = mach_msg_type_number_t(0)
        var processorCount = natural_t(0)

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )

        guard result == KERN_SUCCESS, let processorInfo else { return [] }
        defer {
            let byteCount = vm_size_t(processorMsgCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: processorInfo), byteCount)
        }

        let ticksPerCore = Int(CPU_STATE_MAX)
        let loads = (0..<Int(processorCount)).map { coreIndex in
            let base = coreIndex * ticksPerCore
            return host_cpu_load_info(cpu_ticks: (
                UInt32(processorInfo[base + Int(CPU_STATE_USER)]),
                UInt32(processorInfo[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(processorInfo[base + Int(CPU_STATE_IDLE)]),
                UInt32(processorInfo[base + Int(CPU_STATE_NICE)])
            ))
        }

        defer { previousCoreLoads = loads }
        guard previousCoreLoads.count == loads.count else { return [] }

        return loads.enumerated().map { index, current in
            let previous = previousCoreLoads[index]
            let user = Double(current.cpu_ticks.0 - previous.cpu_ticks.0)
            let system = Double(current.cpu_ticks.1 - previous.cpu_ticks.1)
            let idle = Double(current.cpu_ticks.2 - previous.cpu_ticks.2)
            let nice = Double(current.cpu_ticks.3 - previous.cpu_ticks.3)
            let total = user + system + idle + nice
            guard total > 0 else { return 0 }
            return max(0, min(1, (total - idle) / total))
        }
    }

    private func sampleMemory() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return .unavailable(total: total)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let readilyAvailable = free + inactive + speculative
        let used = total > readilyAvailable ? total - readilyAvailable : 0

        return MemorySnapshot(
            total: total,
            used: used,
            free: free,
            active: active,
            inactive: inactive,
            wired: wired,
            compressed: compressed,
            speculative: speculative,
            pageSize: pageSize
        )
    }

    private func pressure(for memory: MemorySnapshot) -> MemoryPressure {
        switch memory.usedPercent {
        case 0..<0.70:
            .normal
        case 0.70..<0.88:
            .moderate
        default:
            .high
        }
    }

    private func sampleAppUsage(totalMemory: UInt64) -> AppUsageSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return .empty
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return .empty }

        var grouped: [String: (cpu: Double, memory: UInt64)] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  Double(parts[1]) != nil,
                  let cpu = Double(parts[1]),
                  let rssKilobytes = UInt64(parts[2])
            else { continue }

            let rawCommand = String(parts[3])
            let name = appName(from: rawCommand)
            guard !name.isEmpty else { continue }

            let memoryBytes = rssKilobytes * 1024
            let current = grouped[name] ?? (cpu: 0, memory: 0)
            grouped[name] = (cpu: current.cpu + cpu, memory: current.memory + memoryBytes)
        }

        let apps = grouped.map { name, usage in
            let memoryContribution = totalMemory > 0 ? (Double(usage.memory) / Double(totalMemory)) * 100 : 0
            let heatScore = usage.cpu + (memoryContribution * 0.35)
            return AppUsage(
                name: name,
                cpuPercent: usage.cpu,
                memoryBytes: usage.memory,
                heatScore: heatScore
            )
        }

        return AppUsageSnapshot(
            topCPU: Array(apps.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(10)),
            topMemory: Array(apps.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(10)),
            topHeat: Array(apps.sorted { $0.heatScore > $1.heatScore }.prefix(10))
        )
    }

    private func appName(from command: String) -> String {
        let pathName = URL(fileURLWithPath: command).lastPathComponent
        let name = pathName.isEmpty ? command : pathName
        if name == "MenuStat" {
            return "MenuStat"
        }
        return name
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Double {
    var percentString: String {
        formatted(.percent.precision(.fractionLength(0)))
    }
}

extension TimeInterval {
    var uptimeShortString: String {
        let seconds = max(0, Int(rounded(.down)))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(String(format: "%02dh", hours))"
        }
        if hours > 0 {
            return "\(hours)h \(String(format: "%02dm", minutes))"
        }
        return "\(max(1, minutes))m"
    }

    var uptimeDetailString: String {
        let seconds = max(0, Int(rounded(.down)))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(String(format: "%02dm", minutes))"
        }
        if hours > 0 {
            return "\(hours)h \(String(format: "%02dm", minutes))"
        }
        return "\(max(1, minutes))m"
    }
}

extension UInt64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }
}
