import XCTest
@testable import MenuStatCore

final class HardwareSupportTests: XCTestCase {
    func testAppleSiliconWhenARM64OptionalFeatureIsPresent() {
        XCTAssertTrue(HardwareSupport.isAppleSiliconMac(optionalARM64Value: 1))
    }

    func testUnsupportedWhenARM64OptionalFeatureIsMissing() {
        XCTAssertFalse(HardwareSupport.isAppleSiliconMac(optionalARM64Value: 0))
        XCTAssertFalse(HardwareSupport.isAppleSiliconMac(optionalARM64Value: nil))
    }
}
