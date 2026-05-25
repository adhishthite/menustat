import XCTest
@testable import MenuStatCore

final class MemorySnapshotTests: XCTestCase {
    private func make(total: UInt64, used: UInt64, free: UInt64 = 0, inactive: UInt64 = 0, speculative: UInt64 = 0) -> MemorySnapshot {
        MemorySnapshot(
            total: total,
            used: used,
            free: free,
            active: 0,
            inactive: inactive,
            wired: 0,
            compressed: 0,
            speculative: speculative,
            pageSize: 16384
        )
    }

    func testUsedPercentZeroWhenTotalZero() {
        XCTAssertEqual(make(total: 0, used: 0).usedPercent, 0)
    }

    func testUsedPercentRatio() {
        let snapshot = make(total: 16_000_000_000, used: 4_000_000_000)
        XCTAssertEqual(snapshot.usedPercent, 0.25, accuracy: 0.0001)
    }

    func testFreePercentSumsFreeInactiveSpeculative() {
        let snapshot = make(
            total: 1000,
            used: 400,
            free: 200,
            inactive: 100,
            speculative: 100
        )
        XCTAssertEqual(snapshot.freePercent, 0.4, accuracy: 0.0001)
    }

    func testUnavailableFactoryPreservesTotal() {
        let snapshot = MemorySnapshot.unavailable(total: 32_000_000_000)
        XCTAssertEqual(snapshot.total, 32_000_000_000)
        XCTAssertEqual(snapshot.used, 0)
        XCTAssertEqual(snapshot.usedPercent, 0)
    }
}

final class CPUSnapshotTests: XCTestCase {
    func testBusiestCoreReturnsMaxPerCore() {
        let snapshot = CPUSnapshot(total: 0.5, user: 0.3, system: 0.2, idle: 0.5, nice: 0, perCore: [0.1, 0.9, 0.4])
        XCTAssertEqual(snapshot.busiestCore, 0.9)
    }

    func testBusiestCoreFallsBackToTotalWhenNoPerCore() {
        let snapshot = CPUSnapshot.empty
        XCTAssertEqual(snapshot.busiestCore, snapshot.total)
    }

    func testCPUTickDeltaWrapsInsteadOfUnderflowing() {
        XCTAssertEqual(SystemSampler.cpuTickDelta(current: 15, previous: 10), 5)
        XCTAssertEqual(SystemSampler.cpuTickDelta(current: 3, previous: UInt32.max - 1), 5)
    }
}

final class AppUsageTests: XCTestCase {
    func testAppNameFromPathAvoidsBundleSuffix() {
        XCTAssertEqual(SystemSampler.appName(from: "/Applications/Foo.app"), "Foo")
        XCTAssertEqual(SystemSampler.appName(from: "/tmp/MenuStat.app/Contents/MacOS/MenuStat"), "MenuStat")
    }

    func testAppNameOnlyStripsTrailingBundleSuffix() {
        XCTAssertEqual(SystemSampler.appName(from: "helper.app.worker"), "helper.app.worker")
        XCTAssertEqual(SystemSampler.appName(from: "Some.app"), "Some")
    }

    func testAppNameFromCommandFallsBackToInput() {
        XCTAssertEqual(SystemSampler.appName(from: "helper"), "helper")
    }
}

final class FormattingTests: XCTestCase {
    func testPercentStringRoundsToInteger() {
        XCTAssertEqual(0.0.percentString, "0%")
        XCTAssertEqual(0.5.percentString, "50%")
        XCTAssertEqual(1.0.percentString, "100%")
    }

    func testFormattedBytesUsesMemoryStyle() {
        let oneGB: UInt64 = 1_073_741_824
        XCTAssertTrue(oneGB.formattedBytes.contains("GB"))
    }

    func testUptimeShortString() {
        XCTAssertEqual(TimeInterval(59).uptimeShortString, "1m")
        XCTAssertEqual(TimeInterval(3899).uptimeShortString, "1h 04m")
        XCTAssertEqual(TimeInterval(183_600).uptimeShortString, "2d 03h")
    }

    func testUptimeDetailString() {
        XCTAssertEqual(TimeInterval(60).uptimeDetailString, "1m")
        XCTAssertEqual(TimeInterval(7500).uptimeDetailString, "2h 05m")
        XCTAssertEqual(TimeInterval(183_900).uptimeDetailString, "2d 3h 05m")
    }
}
