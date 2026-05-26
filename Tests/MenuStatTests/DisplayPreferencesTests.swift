import XCTest
@testable import MenuStatApp

final class DisplayPreferencesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: "MenuStatTests.\(UUID().uuidString)") else {
            fatalError("Unable to create isolated UserDefaults suite for test")
        }
        return defaults
    }

    func testDefaultsShowAllSectionsAndCPUInMenuBar() {
        let preferences = DisplayPreferences(defaults: makeDefaults())

        XCTAssertEqual(preferences.primaryMetric, .cpu)
        XCTAssertEqual(preferences.visibleSectionsInDisplayOrder(), MetricKind.allCases)
    }

    func testHidesSectionButKeepsAtLeastOneVisible() {
        let preferences = DisplayPreferences(defaults: makeDefaults())

        preferences.setVisible(false, for: .gpu)
        XCTAssertFalse(preferences.isVisible(.gpu))

        for section in MetricKind.allCases where section != .cpu {
            preferences.setVisible(false, for: section)
        }
        preferences.setVisible(false, for: .cpu)

        XCTAssertEqual(preferences.visibleSectionsInDisplayOrder(), [.cpu])
    }
}
