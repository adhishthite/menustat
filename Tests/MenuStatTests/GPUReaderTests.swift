import XCTest
@testable import MenuStat

final class GPUReaderTests: XCTestCase {
    func testParsesAGXPerformanceStatistics() {
        let stats = "\"Renderer Utilization %\"=44,\"Tiler Utilization %\"=45,"
            + "\"Device Utilization %\"=46,\"In use system memory\"=417136640"
        let output = """
        +-o AGXAcceleratorG13X
          | {
          |   "PerformanceStatistics" = {\(stats)}
          |   "model" = "Apple M1 Pro"
          |   "gpu-core-count" = 14
          | }
        """

        let snapshot = GPUReader().parseIORegOutput(output)

        XCTAssertEqual(snapshot.utilization ?? 0, 0.46, accuracy: 0.001)
        XCTAssertEqual(snapshot.rendererUtilization ?? 0, 0.44, accuracy: 0.001)
        XCTAssertEqual(snapshot.tilerUtilization ?? 0, 0.45, accuracy: 0.001)
        XCTAssertEqual(snapshot.memoryBytes, 417_136_640)
        XCTAssertEqual(snapshot.coreCount, 14)
        XCTAssertEqual(snapshot.model, "Apple M1 Pro")
        XCTAssertNil(snapshot.message)
    }

    func testParsesPerformanceStatisticsDictionaryDirectly() {
        let snapshot = GPUReader().parseIORegistryProperties([
            "PerformanceStatistics": [
                "Renderer Utilization %": 24,
                "Tiler Utilization %": 25,
                "Device Utilization %": 26,
                "In use system memory": 123_456
            ],
            "model": "Apple M3",
            "gpu-core-count": 10
        ])

        XCTAssertEqual(snapshot.utilization ?? 0, 0.26, accuracy: 0.001)
        XCTAssertEqual(snapshot.rendererUtilization ?? 0, 0.24, accuracy: 0.001)
        XCTAssertEqual(snapshot.tilerUtilization ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(snapshot.memoryBytes, 123_456)
        XCTAssertEqual(snapshot.coreCount, 10)
        XCTAssertEqual(snapshot.model, "Apple M3")
        XCTAssertNil(snapshot.message)
    }

    func testUnavailableWhenAGXEntryMissing() {
        let snapshot = GPUReader().parseIORegOutput("no accelerator here")
        XCTAssertNil(snapshot.utilization)
        XCTAssertEqual(snapshot.statusTitle, "Unavailable")
        XCTAssertNotNil(snapshot.message)
    }
}
