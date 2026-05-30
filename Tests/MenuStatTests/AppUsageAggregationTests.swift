import XCTest
@testable import MenuStatCore

final class AppUsageAggregationTests: XCTestCase {
    func testGroupsMultipleProcessesByAppNameAndSumsCPUAndMemory() throws {
        let previousDate = Date(timeIntervalSince1970: 10)
        let now = Date(timeIntervalSince1970: 12)
        let snapshot = SystemSampler.appUsageSnapshot(
            records: [
                ProcessUsageRecord(
                    pid: 10,
                    name: "Browser",
                    sample: ProcessUsageSample(totalCPUTime: 3_000_000_000, memoryBytes: 300)
                ),
                ProcessUsageRecord(
                    pid: 11,
                    name: "Browser",
                    sample: ProcessUsageSample(totalCPUTime: 2_500_000_000, memoryBytes: 700)
                ),
                ProcessUsageRecord(
                    pid: 20,
                    name: "Compiler",
                    sample: ProcessUsageSample(totalCPUTime: 4_000_000_000, memoryBytes: 400)
                )
            ],
            previousUsage: [
                10: ProcessUsageSample(totalCPUTime: 1_000_000_000, memoryBytes: 100),
                11: ProcessUsageSample(totalCPUTime: 1_500_000_000, memoryBytes: 100),
                20: ProcessUsageSample(totalCPUTime: 3_000_000_000, memoryBytes: 100)
            ],
            previousDate: previousDate,
            now: now,
            totalMemory: 2000
        )

        let browser = try XCTUnwrap(snapshot.topCPU.first { $0.name == "Browser" })
        XCTAssertEqual(browser.cpuPercent, 150, accuracy: 0.001)
        XCTAssertEqual(browser.memoryBytes, 1000)
        XCTAssertEqual(browser.heatScore, 167.5, accuracy: 0.001)
    }

    func testMissingBaselineProducesMemoryOnlyHeatWithoutFakeCPU() throws {
        let snapshot = SystemSampler.appUsageSnapshot(
            records: [
                ProcessUsageRecord(
                    pid: 10,
                    name: "New App",
                    sample: ProcessUsageSample(totalCPUTime: 9_000_000_000, memoryBytes: 500)
                )
            ],
            previousUsage: [:],
            previousDate: nil,
            now: Date(timeIntervalSince1970: 1),
            totalMemory: 1000
        )

        let app = try XCTUnwrap(snapshot.topCPU.first)
        XCTAssertEqual(app.cpuPercent, 0)
        XCTAssertEqual(app.heatScore, 17.5, accuracy: 0.001)
    }

    func testWrappedOrResetProcessCPUTimeDoesNotGoNegative() {
        let previousDate = Date(timeIntervalSince1970: 1)
        let now = Date(timeIntervalSince1970: 2)

        XCTAssertEqual(
            SystemSampler.cpuPercent(
                for: ProcessUsageSample(totalCPUTime: 100, memoryBytes: 0),
                previous: ProcessUsageSample(totalCPUTime: 500, memoryBytes: 0),
                previousDate: previousDate,
                now: now
            ),
            0
        )
    }

    func testTopListsAreCappedAtTwelveEntries() {
        let previousDate = Date(timeIntervalSince1970: 1)
        let now = Date(timeIntervalSince1970: 2)
        let records = (0..<20).map { index in
            let pid = Int32(index)
            let cpuTime = UInt64(index + 2) * 1_000_000_000
            let memoryBytes = UInt64(index + 1)
            return ProcessUsageRecord(
                pid: pid,
                name: "App \(index)",
                sample: ProcessUsageSample(totalCPUTime: cpuTime, memoryBytes: memoryBytes)
            )
        }
        let previous = Dictionary(
            uniqueKeysWithValues: (0..<20).map { index in
                (Int32(index), ProcessUsageSample(totalCPUTime: 1_000_000_000, memoryBytes: 0))
            }
        )

        let snapshot = SystemSampler.appUsageSnapshot(
            records: records,
            previousUsage: previous,
            previousDate: previousDate,
            now: now,
            totalMemory: 1000
        )

        XCTAssertEqual(snapshot.topCPU.count, 12)
        XCTAssertEqual(snapshot.topMemory.count, 12)
        XCTAssertEqual(snapshot.topHeat.count, 12)
        XCTAssertEqual(snapshot.topCPU.first?.name, "App 19")
    }
}
