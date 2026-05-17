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

    func testUnavailableWhenAGXEntryMissing() {
        let snapshot = GPUReader().parseIORegOutput("no accelerator here")
        XCTAssertNil(snapshot.utilization)
        XCTAssertEqual(snapshot.statusTitle, "Unavailable")
        XCTAssertNotNil(snapshot.message)
    }
}
