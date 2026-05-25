import XCTest
@testable import MenuStatCore

final class FanSnapshotTests: XCTestCase {
    private func make(speeds: [Int], min: [Int] = [], max: [Int] = []) -> FanSnapshot {
        FanSnapshot(
            speeds: speeds,
            minSpeeds: min.isEmpty ? Array(repeating: 0, count: speeds.count) : min,
            maxSpeeds: max.isEmpty ? Array(repeating: 0, count: speeds.count) : max,
            message: nil,
            source: "test",
            attemptedKeys: []
        )
    }

    func testIsMovingNilWhenNoSpeeds() {
        XCTAssertNil(make(speeds: []).isMoving)
    }

    func testIsMovingFalseBelowThreshold() {
        XCTAssertEqual(make(speeds: [0, 99]).isMoving, false)
    }

    func testIsMovingTrueWhenAnyAboveThreshold() {
        XCTAssertEqual(make(speeds: [0, 150]).isMoving, true)
    }

    func testStatusTitleBuckets() {
        XCTAssertEqual(make(speeds: []).statusTitle, "Unavailable")
        XCTAssertEqual(make(speeds: [0]).statusTitle, "Off")
        XCTAssertEqual(make(speeds: [1500], min: [1200], max: [6000]).statusTitle, "Quiet")
        XCTAssertEqual(make(speeds: [3500], min: [1200], max: [6000]).statusTitle, "Cooling")
        XCTAssertEqual(make(speeds: [5500], min: [1200], max: [6000]).statusTitle, "High")
    }

    func testRangePercentUsesMinMaxWhenAvailable() {
        let snapshot = make(speeds: [3600], min: [1200], max: [6000])
        XCTAssertEqual(snapshot.rangePercent(at: 0), 0.5, accuracy: 0.001)
    }

    func testRangePercentFallsBackToMaxWhenMinMissing() {
        let snapshot = make(speeds: [3000], min: [0], max: [6000])
        XCTAssertEqual(snapshot.rangePercent(at: 0), 0.5, accuracy: 0.001)
    }

    func testRangePercentFinalFallback() {
        let snapshot = make(speeds: [3500])
        XCTAssertEqual(snapshot.rangePercent(at: 0), 3500.0 / 7000.0, accuracy: 0.001)
    }

    func testRangePercentClampedTo01() {
        let high = make(speeds: [99999], min: [1200], max: [6000])
        let negative = make(speeds: [-500], min: [1200], max: [6000])
        XCTAssertEqual(high.rangePercent(at: 0), 1.0)
        XCTAssertEqual(negative.rangePercent(at: 0), 0.0)
    }

    func testAverageSpeedAndPeak() {
        let snapshot = make(speeds: [2000, 4000])
        XCTAssertEqual(snapshot.averageSpeed, 3000)
        XCTAssertEqual(snapshot.peakSpeed, 4000)
    }

    func testRpmTextSingleVsMultiple() {
        XCTAssertEqual(make(speeds: [2300]).rpmText, "2300 RPM")
        XCTAssertEqual(make(speeds: [2300, 2500]).rpmText, "2300 / 2500 RPM")
        XCTAssertEqual(make(speeds: []).rpmText, "No RPM")
    }

    func testRangeTextWithValidBounds() {
        let snapshot = make(speeds: [2300, 2500], min: [1200, 1300], max: [6000, 6200])
        XCTAssertEqual(snapshot.rangeText, "1200-6200 RPM")
    }

    func testRangeTextUnknownWhenBoundsMissing() {
        XCTAssertEqual(make(speeds: [2300]).rangeText, "Unknown")
    }

    func testUnavailableFactory() {
        let snapshot = FanSnapshot.unavailable("nope")
        XCTAssertTrue(snapshot.speeds.isEmpty)
        XCTAssertEqual(snapshot.statusTitle, "Unavailable")
        XCTAssertEqual(snapshot.detail, "nope")
    }
}
