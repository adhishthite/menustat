import Foundation
import MenuStatCore

enum CLIJSON {
    static func snapshot(_ snapshot: SystemSnapshot) throws -> String {
        try encode(SnapshotPayload(snapshot: snapshot))
    }

    static func top(_ snapshot: SystemSnapshot, sort: TopSort, limit: Int) throws -> String {
        try encode(TopPayload(
            sort: sort.rawValue,
            apps: CLIRenderer.topApps(snapshot: snapshot, sort: sort, limit: limit).map(AppPayload.init)
        ))
    }

    static func fans(_ fans: FanSnapshot) throws -> String {
        try encode(FanPayload(fans: fans))
    }

    private static func encode(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct SnapshotPayload: Encodable {
    let updatedAt: Date
    let uptimeSeconds: Int
    let cpu: CPUPayload
    let memory: MemoryPayload
    let gpu: GPUPayload
    let pressure: PressurePayload
    let fans: FanPayload
    let apps: AppsPayload

    init(snapshot: SystemSnapshot) {
        updatedAt = snapshot.updatedAt
        uptimeSeconds = Int(snapshot.uptime.rounded(.down))
        cpu = CPUPayload(cpu: snapshot.cpu, coreCount: snapshot.coreCount)
        memory = MemoryPayload(memory: snapshot.memory)
        gpu = GPUPayload(gpu: snapshot.gpu)
        pressure = PressurePayload(pressure: snapshot.pressure)
        fans = FanPayload(fans: snapshot.fans)
        apps = AppsPayload(apps: snapshot.apps)
    }
}

private struct CPUPayload: Encodable {
    let totalPercent: Double
    let userPercent: Double
    let systemPercent: Double
    let idlePercent: Double
    let nicePercent: Double
    let busiestCorePercent: Double
    let perCorePercent: [Double]
    let coreCount: Int

    init(cpu: CPUSnapshot, coreCount: Int) {
        totalPercent = cpu.total.percentValue
        userPercent = cpu.user.percentValue
        systemPercent = cpu.system.percentValue
        idlePercent = cpu.idle.percentValue
        nicePercent = cpu.nice.percentValue
        busiestCorePercent = cpu.busiestCore.percentValue
        perCorePercent = cpu.perCore.map(\.percentValue)
        self.coreCount = coreCount
    }
}

private struct MemoryPayload: Encodable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let freeBytes: UInt64
    let availableBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let speculativeBytes: UInt64
    let usedPercent: Double
    let freePercent: Double
    let pageSizeBytes: UInt64

    init(memory: MemorySnapshot) {
        totalBytes = memory.total
        usedBytes = memory.used
        freeBytes = memory.free
        availableBytes = memory.free + memory.inactive + memory.speculative
        activeBytes = memory.active
        inactiveBytes = memory.inactive
        wiredBytes = memory.wired
        compressedBytes = memory.compressed
        speculativeBytes = memory.speculative
        usedPercent = memory.usedPercent.percentValue
        freePercent = memory.freePercent.percentValue
        pageSizeBytes = memory.pageSize
    }
}

private struct GPUPayload: Encodable {
    let utilizationPercent: Double?
    let rendererUtilizationPercent: Double?
    let tilerUtilizationPercent: Double?
    let memoryBytes: UInt64?
    let coreCount: Int?
    let model: String?
    let status: String
    let detail: String
    let source: String

    init(gpu: GPUSnapshot) {
        utilizationPercent = gpu.utilization?.percentValue
        rendererUtilizationPercent = gpu.rendererUtilization?.percentValue
        tilerUtilizationPercent = gpu.tilerUtilization?.percentValue
        memoryBytes = gpu.memoryBytes
        coreCount = gpu.coreCount
        model = gpu.model
        status = gpu.statusTitle
        detail = gpu.detail
        source = gpu.source
    }
}

private struct PressurePayload: Encodable {
    let title: String
    let detail: String

    init(pressure: MemoryPressure) {
        title = pressure.title
        detail = pressure.detail
    }
}

private struct FanPayload: Encodable {
    let status: String
    let speedsRpm: [Int]
    let minSpeedsRpm: [Int]
    let maxSpeedsRpm: [Int]
    let rangePercent: Double
    let rangeText: String
    let rpmText: String
    let source: String
    let detail: String
    let attemptedKeys: [String]

    init(fans: FanSnapshot) {
        status = fans.statusTitle
        speedsRpm = fans.speeds
        minSpeedsRpm = fans.minSpeeds
        maxSpeedsRpm = fans.maxSpeeds
        rangePercent = fans.averageRangePercent.percentValue
        rangeText = fans.rangeText
        rpmText = fans.rpmText
        source = fans.source
        detail = fans.detail
        attemptedKeys = fans.attemptedKeys
    }
}

private struct AppsPayload: Encodable {
    let topCpu: [AppPayload]
    let topMemory: [AppPayload]
    let topHeat: [AppPayload]

    init(apps: AppUsageSnapshot) {
        topCpu = apps.topCPU.map(AppPayload.init)
        topMemory = apps.topMemory.map(AppPayload.init)
        topHeat = apps.topHeat.map(AppPayload.init)
    }
}

private struct TopPayload: Encodable {
    let sort: String
    let apps: [AppPayload]
}

private struct AppPayload: Encodable {
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let heatScore: Double

    init(app: AppUsage) {
        name = app.name
        cpuPercent = app.cpuPercent
        memoryBytes = app.memoryBytes
        heatScore = app.heatScore
    }
}

private extension Double {
    var percentValue: Double {
        (self * 1000).rounded() / 10
    }
}
