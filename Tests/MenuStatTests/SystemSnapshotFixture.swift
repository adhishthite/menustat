import Foundation
@testable import MenuStatCore

enum TestSnapshots {
    static func system(
        cpu: CPUSnapshot = CPUSnapshot(
            total: 0.42,
            user: 0.30,
            system: 0.12,
            idle: 0.58,
            nice: 0,
            perCore: [0.10, 0.78, 0.32, 0.12, 0.05, 0.08, 0.14, 0.18],
            coreTypes: [.performance, .performance, .performance, .performance, .efficiency, .efficiency, .efficiency, .efficiency]
        ),
        memory: MemorySnapshot = MemorySnapshot(
            total: 16_000_000_000,
            used: 9_600_000_000,
            free: 1_000_000_000,
            active: 5_000_000_000,
            inactive: 3_000_000_000,
            wired: 2_000_000_000,
            compressed: 1_000_000_000,
            speculative: 2_400_000_000,
            pageSize: 16384
        ),
        gpu: GPUSnapshot = GPUSnapshot(
            utilization: 0.31,
            rendererUtilization: 0.22,
            tilerUtilization: 0.18,
            memoryBytes: 2_048_000_000,
            coreCount: 14,
            model: "Apple Test GPU",
            message: nil,
            source: "test"
        ),
        pressure: MemoryPressure = .normal,
        fans: FanSnapshot = FanSnapshot(
            speeds: [3200],
            minSpeeds: [1200],
            maxSpeeds: [5200],
            message: nil,
            source: "test",
            attemptedKeys: ["F0Ac"]
        ),
        apps: AppUsageSnapshot = appUsage(count: 12)
    ) -> SystemSnapshot {
        SystemSnapshot(
            cpu: cpu,
            coreCount: max(cpu.perCore.count, 1),
            memory: memory,
            gpu: gpu,
            pressure: pressure,
            fans: fans,
            apps: apps,
            uptime: 3661,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func appUsage(count: Int) -> AppUsageSnapshot {
        let apps = (0..<count).map { index in
            let name = "Very Long Developer App Name \(index) Helper Renderer Worker"
            let cpuPercent = Double(count - index) * 2.7
            let memoryBytes = UInt64(index + 1) * 512 * 1024 * 1024
            let heatScore = Double(count - index) * 5.0
            return AppUsage(
                name: name,
                cpuPercent: cpuPercent,
                memoryBytes: memoryBytes,
                heatScore: heatScore
            )
        }
        return AppUsageSnapshot(
            topCPU: apps.sorted { $0.cpuPercent > $1.cpuPercent },
            topMemory: apps.sorted { $0.memoryBytes > $1.memoryBytes },
            topHeat: apps.sorted { $0.heatScore > $1.heatScore }
        )
    }
}
