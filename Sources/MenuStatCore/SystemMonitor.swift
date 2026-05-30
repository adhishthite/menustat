import Darwin
import Foundation
import IOKit
import MachO

public struct SystemSnapshot {
    public let cpu: CPUSnapshot
    public let coreCount: Int
    public let memory: MemorySnapshot
    public let gpu: GPUSnapshot
    public let pressure: MemoryPressure
    public let fans: FanSnapshot
    public let apps: AppUsageSnapshot
    public let uptime: TimeInterval
    public let updatedAt: Date

    public var menuTitle: String {
        "CPU \(cpu.total.percentString)  RAM \(memory.usedPercent.percentString)  GPU \(gpu.tileValue)"
    }

    public static let empty = SystemSnapshot(
        cpu: .empty,
        coreCount: ProcessInfo.processInfo.processorCount,
        memory: .unavailable(total: ProcessInfo.processInfo.physicalMemory),
        gpu: .unavailable("Checking GPU counters"),
        pressure: .normal,
        fans: .unavailable("Checking fan sensors"),
        apps: .empty,
        uptime: ProcessInfo.processInfo.systemUptime,
        updatedAt: Date()
    )

    public static let unsupported = SystemSnapshot(
        cpu: .empty,
        coreCount: ProcessInfo.processInfo.processorCount,
        memory: .unavailable(total: ProcessInfo.processInfo.physicalMemory),
        gpu: .unavailable("MenuStat is designed for Apple Silicon Macs only."),
        pressure: .normal,
        fans: .unavailable("MenuStat is designed for Apple Silicon Macs only."),
        apps: .empty,
        uptime: ProcessInfo.processInfo.systemUptime,
        updatedAt: Date()
    )
}

public struct GPUSnapshot {
    public let utilization: Double?
    public let rendererUtilization: Double?
    public let tilerUtilization: Double?
    public let memoryBytes: UInt64?
    public let coreCount: Int?
    public let model: String?
    public let message: String?
    public let source: String

    public var tileValue: String {
        utilization?.percentString ?? "--"
    }

    public var tileCaption: String {
        if let coreCount {
            return "\(coreCount) CORES"
        }
        return "AGX"
    }

    public var statusTitle: String {
        guard let utilization else { return "Unavailable" }
        switch utilization {
        case ..<0.30:
            return "Idle"
        case ..<0.70:
            return "Active"
        default:
            return "Heavy"
        }
    }

    public var detail: String {
        message ?? "AGX accelerator counters"
    }

    public static func unavailable(_ message: String, source: String = "IORegistry") -> GPUSnapshot {
        GPUSnapshot(
            utilization: nil,
            rendererUtilization: nil,
            tilerUtilization: nil,
            memoryBytes: nil,
            coreCount: nil,
            model: nil,
            message: message,
            source: source
        )
    }
}

public struct CPUSnapshot {
    public let total: Double
    public let user: Double
    public let system: Double
    public let idle: Double
    public let nice: Double
    public let perCore: [Double]
    public let coreTypes: [CPUCoreType]

    public init(
        total: Double,
        user: Double,
        system: Double,
        idle: Double,
        nice: Double,
        perCore: [Double],
        coreTypes: [CPUCoreType] = []
    ) {
        self.total = total
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
        self.perCore = perCore
        self.coreTypes = coreTypes
    }

    public var busiestCore: Double {
        perCore.max() ?? total
    }

    public static let empty = CPUSnapshot(total: 0, user: 0, system: 0, idle: 1, nice: 0, perCore: [])
}

public enum CPUCoreType: String {
    case performance
    case efficiency
    case unknown
}

public struct MemorySnapshot {
    public let total: UInt64
    public let used: UInt64
    public let free: UInt64
    public let active: UInt64
    public let inactive: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let speculative: UInt64
    public let pageSize: UInt64

    public var usedPercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }

    public var freePercent: Double {
        guard total > 0 else { return 0 }
        return Double(free + inactive + speculative) / Double(total)
    }

    public static func unavailable(total: UInt64) -> MemorySnapshot {
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

public enum MemoryPressure {
    case normal
    case moderate
    case high

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }

    public var detail: String {
        switch self {
        case .normal: "Plenty of readily available memory."
        case .moderate: "Memory is getting tighter."
        case .high: "Memory pressure is high."
        }
    }

    public var symbolName: String {
        switch self {
        case .normal: "gauge.with.dots.needle.0percent"
        case .moderate: "gauge.with.dots.needle.50percent"
        case .high: "gauge.with.dots.needle.100percent"
        }
    }
}

public struct FanSnapshot {
    private static let stoppedRPMThreshold = 100

    public let speeds: [Int]
    public let minSpeeds: [Int]
    public let maxSpeeds: [Int]
    public let message: String?
    public let source: String
    public let attemptedKeys: [String]

    public var isMoving: Bool? {
        guard !speeds.isEmpty else { return nil }
        return speeds.contains { $0 > Self.stoppedRPMThreshold }
    }

    public var averageRangePercent: Double {
        guard !speeds.isEmpty else { return 0 }
        let total = speeds.indices.reduce(0) { partial, index in
            partial + rangePercent(at: index)
        }
        return total / Double(speeds.count)
    }

    public var averageSpeed: Int {
        guard !speeds.isEmpty else { return 0 }
        return Int((Double(speeds.reduce(0, +)) / Double(speeds.count)).rounded())
    }

    public var peakSpeed: Int {
        speeds.max() ?? 0
    }

    public var percentTitle: String {
        "\(Int((averageRangePercent * 100).rounded()))%"
    }

    public var rpmText: String {
        guard !speeds.isEmpty else { return "No RPM" }
        if speeds.count == 1, let speed = speeds.first {
            return "\(speed) RPM"
        }
        return speeds.map(String.init).joined(separator: " / ") + " RPM"
    }

    public var rangeText: String {
        let validMinimums = minSpeeds.filter { $0 > 0 }
        let validMaximums = maxSpeeds.filter { $0 > 0 }
        guard let minimum = validMinimums.min(), let maximum = validMaximums.max(), maximum > minimum else {
            return "Unknown"
        }
        return "\(minimum)-\(maximum) RPM"
    }

    public var statusTitle: String {
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

    public var detail: String {
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

    public func minSpeed(at index: Int) -> Int? {
        guard minSpeeds.indices.contains(index), minSpeeds[index] > 0 else { return nil }
        return minSpeeds[index]
    }

    public func maxSpeed(at index: Int) -> Int? {
        guard maxSpeeds.indices.contains(index), maxSpeeds[index] > 0 else { return nil }
        return maxSpeeds[index]
    }

    public func rangePercent(at index: Int) -> Double {
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

    public func rangePercentTitle(at index: Int) -> String {
        "\(Int((rangePercent(at: index) * 100).rounded()))%"
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    public static func unavailable(_ message: String) -> FanSnapshot {
        FanSnapshot(speeds: [], minSpeeds: [], maxSpeeds: [], message: message, source: "AppleSMC", attemptedKeys: [])
    }

    public static func unavailable(_ message: String, source: String, attemptedKeys: [String]) -> FanSnapshot {
        FanSnapshot(speeds: [], minSpeeds: [], maxSpeeds: [], message: message, source: source, attemptedKeys: attemptedKeys)
    }
}

public struct AppUsageSnapshot {
    public let topCPU: [AppUsage]
    public let topMemory: [AppUsage]
    public let topHeat: [AppUsage]

    public static let empty = AppUsageSnapshot(topCPU: [], topMemory: [], topHeat: [])
}

public struct AppUsage: Identifiable {
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let heatScore: Double

    public var id: String {
        name
    }

    public var cpuDisplay: String {
        if cpuPercent >= 10 {
            return "\(Int(cpuPercent.rounded()))%"
        }
        return "\(cpuPercent.formatted(.number.precision(.fractionLength(1))))%"
    }

    public var heatDisplay: String {
        "\(Int(heatScore.rounded()))"
    }
}

public final class SystemSampler {
    // Stateful sampler: call only from one serial executor so CPU, process, GPU, and fan baselines stay coherent.
    private var previousCPULoad: host_cpu_load_info?
    private var previousCoreLoads: [host_cpu_load_info] = []
    private var previousProcessUsage: [Int32: ProcessUsageSample] = [:]
    private var previousProcessSampleDate: Date?
    private var latestAppUsage = AppUsageSnapshot.empty
    private var processNameCache: [Int32: String] = [:]
    private let fanReader = SMCFanReader()
    private let gpuReader = GPUReader()
    private let coreTypes: [CPUCoreType]

    public init() {
        coreTypes = Self.readCPUCoreTypes()
    }

    public func sample(includeAppUsage: Bool = true) -> SystemSnapshot {
        let memory = sampleMemory()
        let apps: AppUsageSnapshot
        if includeAppUsage {
            apps = sampleAppUsage(totalMemory: memory.total)
        } else {
            resetProcessUsageBaseline()
            apps = latestAppUsage
        }
        return SystemSnapshot(
            cpu: sampleCPU(),
            coreCount: ProcessInfo.processInfo.processorCount,
            memory: memory,
            gpu: gpuReader.readGPU(),
            pressure: Self.pressure(for: memory),
            fans: fanReader.readFans(),
            apps: apps,
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

        let user = Self.cpuTickDelta(current: cpuLoad.cpu_ticks.0, previous: previous.cpu_ticks.0)
        let system = Self.cpuTickDelta(current: cpuLoad.cpu_ticks.1, previous: previous.cpu_ticks.1)
        let idle = Self.cpuTickDelta(current: cpuLoad.cpu_ticks.2, previous: previous.cpu_ticks.2)
        let nice = Self.cpuTickDelta(current: cpuLoad.cpu_ticks.3, previous: previous.cpu_ticks.3)
        let total = user + system + idle + nice

        guard total > 0 else { return .empty }
        let perCore = samplePerCoreCPU()
        let snapshotCoreTypes = coreTypes.count == perCore.count ? coreTypes : []
        return CPUSnapshot(
            total: max(0, min(1, (total - idle) / total)),
            user: user / total,
            system: system / total,
            idle: idle / total,
            nice: nice / total,
            perCore: perCore,
            coreTypes: snapshotCoreTypes
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
            let user = Self.cpuTickDelta(current: current.cpu_ticks.0, previous: previous.cpu_ticks.0)
            let system = Self.cpuTickDelta(current: current.cpu_ticks.1, previous: previous.cpu_ticks.1)
            let idle = Self.cpuTickDelta(current: current.cpu_ticks.2, previous: previous.cpu_ticks.2)
            let nice = Self.cpuTickDelta(current: current.cpu_ticks.3, previous: previous.cpu_ticks.3)
            let total = user + system + idle + nice
            guard total > 0 else { return 0 }
            return max(0, min(1, (total - idle) / total))
        }
    }

    static func cpuTickDelta(current: UInt32, previous: UInt32) -> Double {
        Double(current &- previous)
    }

    private static func readCPUCoreTypes() -> [CPUCoreType] {
        let ioRegistryTypes = readCPUCoreTypesFromIODeviceTree()
        if !ioRegistryTypes.isEmpty {
            return ioRegistryTypes
        }
        return readCPUCoreTypesFromSysctl()
    }

    private static func readCPUCoreTypesFromIODeviceTree() -> [CPUCoreType] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [] }
        defer { IOObjectRelease(cpus) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var mapped: [(id: Int, type: CPUCoreType)] = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard let logicalID = intProperty(named: "logical-cpu-id", from: child),
                  let clusterType = coreTypeProperty(named: "cluster-type", from: child)
            else { continue }
            mapped.append((logicalID, clusterType))
        }

        return mapped.sorted { $0.id < $1.id }.map(\.type)
    }

    private static func readCPUCoreTypesFromSysctl() -> [CPUCoreType] {
        guard let perfLevels = sysctlInt("hw.nperflevels"), perfLevels > 0 else { return [] }

        var types: [CPUCoreType] = []
        for index in 0..<perfLevels {
            guard let count = sysctlInt("hw.perflevel\(index).logicalcpu"), count > 0 else { continue }
            let name = sysctlString("hw.perflevel\(index).name")?.lowercased() ?? ""
            let type: CPUCoreType = if name.contains("performance") {
                .performance
            } else if name.contains("efficiency") {
                .efficiency
            } else {
                .unknown
            }
            types.append(contentsOf: Array(repeating: type, count: count))
        }
        return types
    }

    private static func intProperty(named name: String, from entry: io_registry_entry_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func coreTypeProperty(named name: String, from entry: io_registry_entry_t) -> CPUCoreType? {
        guard let value = IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        else { return nil }

        let text: String? = if let string = value as? String {
            string
        } else if let data = value as? Data {
            String(data: data, encoding: .utf8)
        } else {
            nil
        }

        switch text?.trimmingCharacters(in: .controlCharacters).uppercased() {
        case "P": return .performance
        case "E": return .efficiency
        default: return .unknown
        }
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value = 0
        var size = MemoryLayout<Int>.stride
        let result = sysctlbyname(name, &value, &size, nil, 0)
        return result == 0 ? value : nil
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = Array(repeating: CChar(0), count: size)
        let result = buffer.withUnsafeMutableBufferPointer {
            sysctlbyname(name, $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(cString: buffer)
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

    static func pressure(for memory: MemorySnapshot) -> MemoryPressure {
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
        let now = Date()
        let previousDate = previousProcessSampleDate
        let previousUsage = previousProcessUsage
        var currentUsage: [Int32: ProcessUsageSample] = [:]

        let processIdentifiers = allProcessIdentifiers()
        var livePIDs = Set<Int32>()
        var records: [ProcessUsageRecord] = []

        for pid in processIdentifiers {
            guard let sample = processUsage(for: pid) else { continue }
            currentUsage[pid] = sample
            livePIDs.insert(pid)

            if let previousSample = previousUsage[pid], sample.totalCPUTime < previousSample.totalCPUTime {
                processNameCache.removeValue(forKey: pid)
            }

            let name = appName(for: pid)
            guard !name.isEmpty else { continue }
            records.append(ProcessUsageRecord(pid: pid, name: name, sample: sample))
        }

        previousProcessUsage = currentUsage
        previousProcessSampleDate = now
        pruneProcessNameCache(livePIDs: livePIDs)

        let snapshot = Self.appUsageSnapshot(
            records: records,
            previousUsage: previousUsage,
            previousDate: previousDate,
            now: now,
            totalMemory: totalMemory
        )
        latestAppUsage = snapshot
        return snapshot
    }

    public func refreshProcessUsageBaseline() {
        let now = Date()
        var currentUsage: [Int32: ProcessUsageSample] = [:]
        var livePIDs = Set<Int32>()

        for pid in allProcessIdentifiers() {
            guard let sample = processUsage(for: pid) else { continue }
            currentUsage[pid] = sample
            livePIDs.insert(pid)
        }

        previousProcessUsage = currentUsage
        previousProcessSampleDate = now
        pruneProcessNameCache(livePIDs: livePIDs)
    }

    private func resetProcessUsageBaseline() {
        guard previousProcessSampleDate != nil || !previousProcessUsage.isEmpty else { return }
        previousProcessUsage.removeAll(keepingCapacity: true)
        previousProcessSampleDate = nil
    }

    private func pruneProcessNameCache(livePIDs: Set<Int32>) {
        let stalePIDs = processNameCache.keys.filter { !livePIDs.contains($0) }
        for pid in stalePIDs {
            processNameCache.removeValue(forKey: pid)
        }
    }

    private func allProcessIdentifiers() -> [Int32] {
        let processCount = proc_listallpids(nil, 0)
        guard processCount > 0 else { return [] }

        var pids = Array(repeating: pid_t(0), count: Int(processCount))
        let bytesWritten = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard bytesWritten > 0 else { return [] }

        let returnedCount = Int(bytesWritten)
        let pidCount = returnedCount <= pids.count ? returnedCount : returnedCount / MemoryLayout<pid_t>.stride
        return pids
            .prefix(pidCount)
            .filter { $0 > 0 }
    }

    private func processUsage(for pid: Int32) -> ProcessUsageSample? {
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: UInt8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
        }
        guard result == Int32(size) else { return nil }

        return ProcessUsageSample(
            totalCPUTime: taskInfo.pti_total_user + taskInfo.pti_total_system,
            memoryBytes: taskInfo.pti_resident_size
        )
    }

    static func appUsageSnapshot(
        records: [ProcessUsageRecord],
        previousUsage: [Int32: ProcessUsageSample],
        previousDate: Date?,
        now: Date,
        totalMemory: UInt64
    ) -> AppUsageSnapshot {
        var grouped: [String: (cpu: Double, memory: UInt64)] = [:]

        for record in records {
            let cpu = cpuPercent(
                for: record.sample,
                previous: previousUsage[record.pid],
                previousDate: previousDate,
                now: now
            )
            let current = grouped[record.name] ?? (cpu: 0, memory: 0)
            grouped[record.name] = (
                cpu: current.cpu + cpu,
                memory: current.memory + record.sample.memoryBytes
            )
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
            topCPU: Array(apps.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(12)),
            topMemory: Array(apps.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(12)),
            topHeat: Array(apps.sorted { $0.heatScore > $1.heatScore }.prefix(12))
        )
    }

    static func cpuPercent(
        for sample: ProcessUsageSample,
        previous: ProcessUsageSample?,
        previousDate: Date?,
        now: Date
    ) -> Double {
        guard let previous,
              let previousDate,
              sample.totalCPUTime >= previous.totalCPUTime
        else { return 0 }

        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0 else { return 0 }

        let cpuSeconds = Double(sample.totalCPUTime - previous.totalCPUTime) / 1_000_000_000
        return max(0, cpuSeconds / elapsed * 100)
    }

    private func appName(for pid: Int32) -> String {
        if let cachedName = processNameCache[pid] {
            return cachedName
        }

        var pathBuffer = Array(repeating: CChar(0), count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            let name = Self.appName(from: path)
            processNameCache[pid] = name
            return name
        }

        var nameBuffer = Array(repeating: CChar(0), count: 2 * Int(MAXCOMLEN))
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard nameLength > 0 else { return "" }
        let name = String(cString: nameBuffer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        processNameCache[pid] = name
        return name
    }

    static func appName(from command: String) -> String {
        let pathName = (command as NSString).lastPathComponent
        let name = pathName.isEmpty ? command : pathName
        if name == "MenuStat" {
            return "MenuStat"
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(".app") else { return trimmed }
        return String(trimmed.dropLast(4))
    }
}

struct ProcessUsageRecord {
    let pid: Int32
    let name: String
    let sample: ProcessUsageSample
}

struct ProcessUsageSample {
    let totalCPUTime: UInt64
    let memoryBytes: UInt64
}

final class GPUReader {
    private var cachedService: io_object_t = 0
    private var cachedModel: String?
    private var cachedCoreCount: Int?

    deinit {
        invalidateCachedService()
    }

    func readGPU() -> GPUSnapshot {
        guard let service = cachedOrDiscoveredService() else {
            return .unavailable("No AGX accelerator entry was found.", source: "AGXAccelerator")
        }

        if let snapshot = fastSnapshot(from: service) {
            return snapshot
        }

        guard let properties = properties(from: service), !properties.isEmpty else {
            invalidateCachedService()
            return .unavailable("GPU counters are not available.", source: "AGXAccelerator")
        }

        return parseIORegistryProperties(properties)
    }

    func parseIORegistryProperties(_ properties: [String: Any]) -> GPUSnapshot {
        parseProperties(properties)
    }

    func parseIORegOutput(_ output: String) -> GPUSnapshot {
        guard output.contains("AGXAccelerator") else {
            return .unavailable("No AGX accelerator entry was found.", source: "AGXAccelerator")
        }

        let utilization = percentValue(named: "Device Utilization %", in: output)
        let renderer = percentValue(named: "Renderer Utilization %", in: output)
        let tiler = percentValue(named: "Tiler Utilization %", in: output)
        let memoryBytes = integerValue(named: "In use system memory", in: output).map(UInt64.init)
        let coreCount = integerValue(named: "gpu-core-count", in: output)
        let model = stringValue(named: "model", in: output)

        guard utilization != nil || renderer != nil || tiler != nil else {
            return .unavailable("AGX counters were found, but utilization is not exposed.", source: "AGXAccelerator")
        }

        return GPUSnapshot(
            utilization: utilization,
            rendererUtilization: renderer,
            tilerUtilization: tiler,
            memoryBytes: memoryBytes,
            coreCount: coreCount,
            model: model,
            message: nil,
            source: "AGXAccelerator"
        )
    }

    private func cachedOrDiscoveredService() -> io_object_t? {
        if cachedService != 0 {
            return cachedService
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AGXAccelerator"),
            &iterator
        )
        guard result == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            guard serviceHasCounters(service) else {
                IOObjectRelease(service)
                continue
            }
            cachedService = service
            return service
        }

        return nil
    }

    private func invalidateCachedService() {
        guard cachedService != 0 else { return }
        IOObjectRelease(cachedService)
        cachedService = 0
    }

    private func serviceHasCounters(_ service: io_object_t) -> Bool {
        if let performanceStatistics = property(named: "PerformanceStatistics", from: service) as? [String: Any],
           percentValue(named: "Device Utilization %", in: performanceStatistics) != nil
           || percentValue(named: "Renderer Utilization %", in: performanceStatistics) != nil
           || percentValue(named: "Tiler Utilization %", in: performanceStatistics) != nil
        {
            return true
        }

        guard let properties = properties(from: service), !properties.isEmpty else { return false }
        return percentValue(named: "Device Utilization %", in: properties) != nil
            || percentValue(named: "Renderer Utilization %", in: properties) != nil
            || percentValue(named: "Tiler Utilization %", in: properties) != nil
    }

    private func fastSnapshot(from service: io_object_t) -> GPUSnapshot? {
        guard let performanceStatistics = property(named: "PerformanceStatistics", from: service) as? [String: Any],
              !performanceStatistics.isEmpty
        else { return nil }

        cachedCoreCount = cachedCoreCount ?? integerValue(from: property(named: "gpu-core-count", from: service))
        cachedModel = cachedModel ?? stringValue(from: property(named: "model", from: service))
        return parseProperties(["PerformanceStatistics": performanceStatistics])
    }

    private func property(named name: String, from service: io_object_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    private func properties(from service: io_object_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS,
              let serviceProperties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
        else { return nil }

        return serviceProperties
    }

    private func parseProperties(_ properties: [String: Any]) -> GPUSnapshot {
        let performanceStatistics = properties["PerformanceStatistics"] as? [String: Any] ?? [:]
        let utilization = percentValue(named: "Device Utilization %", in: performanceStatistics)
            ?? percentValue(named: "Device Utilization %", in: properties)
        let renderer = percentValue(named: "Renderer Utilization %", in: performanceStatistics)
            ?? percentValue(named: "Renderer Utilization %", in: properties)
        let tiler = percentValue(named: "Tiler Utilization %", in: performanceStatistics)
            ?? percentValue(named: "Tiler Utilization %", in: properties)
        let memoryBytes = (integerValue(named: "In use system memory", in: performanceStatistics)
            ?? integerValue(named: "In use system memory", in: properties)).map(UInt64.init)
        cachedCoreCount = cachedCoreCount ?? integerValue(named: "gpu-core-count", in: properties)
        cachedModel = cachedModel ?? stringValue(named: "model", in: properties)

        guard utilization != nil || renderer != nil || tiler != nil else {
            return .unavailable("AGX counters were found, but utilization is not exposed.", source: "AGXAccelerator")
        }

        return GPUSnapshot(
            utilization: utilization,
            rendererUtilization: renderer,
            tilerUtilization: tiler,
            memoryBytes: memoryBytes,
            coreCount: cachedCoreCount,
            model: cachedModel,
            message: nil,
            source: "AGXAccelerator"
        )
    }

    private func percentValue(named name: String, in properties: [String: Any]) -> Double? {
        integerValue(named: name, in: properties).map { max(0, min(1, Double($0) / 100)) }
    }

    private func integerValue(named name: String, in properties: [String: Any]) -> Int? {
        switch value(named: name, in: properties) {
        case let number as NSNumber:
            number.intValue
        case let string as String:
            Int(string)
        default:
            nil
        }
    }

    private func integerValue(from value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            number.intValue
        case let string as String:
            Int(string)
        default:
            nil
        }
    }

    private func stringValue(named name: String, in properties: [String: Any]) -> String? {
        switch value(named: name, in: properties) {
        case let string as String:
            string
        case let data as Data:
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        default:
            nil
        }
    }

    private func stringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            string
        case let data as Data:
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        default:
            nil
        }
    }

    private func value(named name: String, in properties: [String: Any]) -> Any? {
        if let value = properties[name] {
            return value
        }

        for nested in properties.values {
            if let dictionary = nested as? [String: Any],
               let value = dictionary[name]
            {
                return value
            }
        }

        return nil
    }

    private func percentValue(named name: String, in output: String) -> Double? {
        integerValue(named: name, in: output).map { max(0, min(1, Double($0) / 100)) }
    }

    private func integerValue(named name: String, in output: String) -> Int? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: name))\"\\s*=\\s*(\\d+)"
        return firstMatch(pattern: pattern, in: output).flatMap(Int.init)
    }

    private func stringValue(named name: String, in output: String) -> String? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: name))\"\\s*=\\s*\"([^\"]+)\""
        return firstMatch(pattern: pattern, in: output)
    }

    private func firstMatch(pattern: String, in output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output)
        else { return nil }
        return String(output[valueRange])
    }
}

public extension Double {
    var percentString: String {
        formatted(.percent.precision(.fractionLength(0)))
    }
}

public extension TimeInterval {
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

public extension UInt64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }
}
