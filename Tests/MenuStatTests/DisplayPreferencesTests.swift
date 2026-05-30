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
        XCTAssertEqual(preferences.refreshInterval, .balanced)
        XCTAssertEqual(preferences.topAppRows, .standard)
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

    func testPersistsRefreshIntervalAndTopAppRows() {
        let defaults = makeDefaults()
        var preferences = DisplayPreferences(defaults: defaults)

        preferences.refreshInterval = .live
        preferences.topAppRows = .deep

        preferences = DisplayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.refreshInterval, .live)
        XCTAssertEqual(preferences.topAppRows, .deep)
    }

    func testInvalidPersistedValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set("not-a-metric", forKey: "display.primaryMetric")
        defaults.set(["missing", "also-missing"], forKey: "display.visibleSections")
        defaults.set(2.5, forKey: "display.refreshInterval")
        defaults.set(99, forKey: "display.topAppRows")

        let preferences = DisplayPreferences(defaults: defaults)

        XCTAssertEqual(preferences.primaryMetric, .cpu)
        XCTAssertEqual(preferences.visibleSectionsInDisplayOrder(), MetricKind.allCases)
        XCTAssertEqual(preferences.refreshInterval, .balanced)
        XCTAssertEqual(preferences.topAppRows, .standard)
    }

    func testHidingPrimaryMetricMovesMenuBarMetricToFirstVisibleSection() {
        let preferences = DisplayPreferences(defaults: makeDefaults())
        preferences.primaryMetric = .gpu

        preferences.setVisible(false, for: .gpu)

        XCTAssertFalse(preferences.isVisible(.gpu))
        XCTAssertEqual(preferences.primaryMetric, .cpu)
    }

    func testVisibleSectionsStayInDisplayOrderAfterPersistence() {
        let defaults = makeDefaults()
        defaults.set(["fans", "cpu", "memory"], forKey: "display.visibleSections")

        let preferences = DisplayPreferences(defaults: defaults)

        XCTAssertEqual(preferences.visibleSectionsInDisplayOrder(), [.cpu, .memory, .fans])
    }
}
