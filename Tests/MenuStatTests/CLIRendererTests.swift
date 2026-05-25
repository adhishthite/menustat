import ArgumentParser
import XCTest
@testable import MenuStatCLIKit
@testable import MenuStatCore

final class CLIRendererTests: XCTestCase {
    func testDashboardContainsPrimarySections() {
        let output = CLIRenderer.dashboard(snapshot: makeSnapshot(), interval: 2, width: 80)

        XCTAssertTrue(output.contains("MenuStat"))
        XCTAssertTrue(output.contains("CPU"))
        XCTAssertTrue(output.contains("Memory"))
        XCTAssertTrue(output.contains("GPU"))
        XCTAssertTrue(output.contains("Pressure"))
        XCTAssertTrue(output.contains("Fans"))
        XCTAssertTrue(output.contains("Top apps by heat"))
    }

    func testPlainSnapshotShowsUnavailableTelemetry() {
        let snapshot = makeSnapshot(
            gpu: .unavailable("no gpu"),
            fans: .unavailable("no fans")
        )
        let output = CLIRenderer.plainSnapshot(snapshot: snapshot)

        XCTAssertTrue(output.contains("GPU: --"))
        XCTAssertTrue(output.contains("Fans: Unavailable"))
        XCTAssertTrue(output.contains("no fans"))
    }

    func testTopSortsFromRequestedSnapshotBucket() {
        let snapshot = makeSnapshot()

        XCTAssertTrue(CLIRenderer.top(snapshot: snapshot, sort: .cpu, limit: 1).contains("Compiler"))
        XCTAssertTrue(CLIRenderer.top(snapshot: snapshot, sort: .memory, limit: 1).contains("Browser"))
        XCTAssertTrue(CLIRenderer.top(snapshot: snapshot, sort: .heat, limit: 1).contains("Editor"))
    }

    func testSnapshotJSONUsesSnakeCaseFieldsAndPercentValues() throws {
        let json = try CLIJSON.snapshot(makeSnapshot())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let cpu = try XCTUnwrap(object["cpu"] as? [String: Any])
        let memory = try XCTUnwrap(object["memory"] as? [String: Any])

        XCTAssertNotNil(object["updated_at"])
        XCTAssertEqual(object["uptime_seconds"] as? Int, 3661)
        XCTAssertEqual(cpu["total_percent"] as? Double, 42)
        XCTAssertEqual(memory["total_bytes"] as? Int, 16000)
    }

    func testFansJSONUsesStableNames() throws {
        let json = try CLIJSON.fans(makeSnapshot().fans)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

        XCTAssertEqual(object["status"] as? String, "Cooling")
        XCTAssertEqual(object["speeds_rpm"] as? [Int], [3200])
        XCTAssertEqual(object["range_percent"] as? Double, 50)
    }
}

final class CLIArgumentTests: XCTestCase {
    func testDefaultCommandIsDashboard() throws {
        let command = try MenuStatCommand.parseAsRoot([])
        XCTAssertTrue(command is Dashboard)
    }

    func testParsesSnapshotJSON() throws {
        let command = try MenuStatCommand.parseAsRoot(["snapshot", "--json"])
        let snapshot = try XCTUnwrap(command as? Snapshot)
        XCTAssertTrue(snapshot.json)
        XCTAssertFalse(snapshot.instant)
    }

    func testParsesTopOptions() throws {
        let command = try MenuStatCommand.parseAsRoot(["top", "--by", "memory", "--limit", "5", "--json"])
        let top = try XCTUnwrap(command as? Top)
        XCTAssertEqual(top.by, .memory)
        XCTAssertEqual(top.limit, 5)
        XCTAssertTrue(top.json)
    }

    func testRejectsInvalidTopLimit() throws {
        XCTAssertThrowsError(try Top.parse(["--limit", "0"]))
    }

    func testRejectsInvalidDashboardInterval() throws {
        XCTAssertThrowsError(try Dashboard.parse(["--interval", "0"]))
    }
}

private func makeSnapshot(
    gpu: GPUSnapshot = GPUSnapshot(
        utilization: 0.31,
        rendererUtilization: 0.22,
        tilerUtilization: 0.18,
        memoryBytes: 2048,
        coreCount: 14,
        model: "Apple Test GPU",
        message: nil,
        source: "test"
    ),
    fans: FanSnapshot = FanSnapshot(
        speeds: [3200],
        minSpeeds: [1200],
        maxSpeeds: [5200],
        message: nil,
        source: "test",
        attemptedKeys: ["F0Ac"]
    )
) -> SystemSnapshot {
    SystemSnapshot(
        cpu: CPUSnapshot(total: 0.42, user: 0.30, system: 0.12, idle: 0.58, nice: 0, perCore: [0.10, 0.78]),
        coreCount: 2,
        memory: MemorySnapshot(
            total: 16000,
            used: 8000,
            free: 2000,
            active: 4000,
            inactive: 3000,
            wired: 1000,
            compressed: 500,
            speculative: 1000,
            pageSize: 16
        ),
        gpu: gpu,
        pressure: .normal,
        fans: fans,
        apps: AppUsageSnapshot(
            topCPU: [
                AppUsage(name: "Compiler", cpuPercent: 38, memoryBytes: 1024, heatScore: 44)
            ],
            topMemory: [
                AppUsage(name: "Browser", cpuPercent: 12, memoryBytes: 4096, heatScore: 31)
            ],
            topHeat: [
                AppUsage(name: "Editor", cpuPercent: 18, memoryBytes: 2048, heatScore: 52)
            ]
        ),
        uptime: 3661,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
