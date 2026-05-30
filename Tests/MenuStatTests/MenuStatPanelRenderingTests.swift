import AppKit
import SwiftUI
import XCTest
@testable import MenuStatApp

@MainActor
final class MenuStatPanelRenderingTests: XCTestCase {
    func testPanelLayoutKeepsRootContentInSyncWithConfiguredPanelSize() {
        XCTAssertEqual(PanelLayout.panelSize.width, 720)
        XCTAssertEqual(PanelLayout.panelSize.height, 820)
        XCTAssertEqual(PanelLayout.contentSize.width, 708)
        XCTAssertEqual(PanelLayout.contentSize.height, 808)
    }

    func testPanelRootRendersAcrossFullConfiguredWidth() throws {
        let preferences = DisplayPreferences(defaults: makeDefaults())
        let root = MenuStatPanelRoot(
            snapshot: TestSnapshots.system(),
            preferences: preferences,
            width: PanelLayout.panelSize.width,
            height: PanelLayout.panelSize.height,
            isVisible: true
        )

        let bitmap = try render(root, size: PanelLayout.panelSize)
        let scale = Double(bitmap.pixelsWide) / PanelLayout.panelSize.width
        let rightRange = Int(PanelLayout.panelSize.width * scale * 0.86)..<Int(PanelLayout.panelSize.width * scale * 0.97)
        let leftRange = Int(PanelLayout.panelSize.width * scale * 0.03)..<Int(PanelLayout.panelSize.width * scale * 0.14)
        let verticalRange = Int(PanelLayout.panelSize.height * scale * 0.05)..<Int(PanelLayout.panelSize.height * scale * 0.95)

        XCTAssertEqual(bitmap.size.width, PanelLayout.panelSize.width)
        XCTAssertEqual(bitmap.size.height, PanelLayout.panelSize.height)
        XCTAssertGreaterThan(meaningfulPixels(in: bitmap, xRange: rightRange, yRange: verticalRange), 60)
        XCTAssertGreaterThan(meaningfulPixels(in: bitmap, xRange: leftRange, yRange: verticalRange), 60)
    }

    func testPanelViewRendersDeepRowsAndLongNamesWithoutBlankOutput() throws {
        let preferences = DisplayPreferences(defaults: makeDefaults())
        preferences.topAppRows = .deep
        preferences.refreshInterval = .live

        let view = MenuStatPanelView(
            snapshot: TestSnapshots.system(apps: TestSnapshots.appUsage(count: 12)),
            preferences: preferences,
            isVisible: true
        )
        .frame(width: PanelLayout.contentSize.width, height: PanelLayout.contentSize.height)

        let bitmap = try render(view, size: PanelLayout.contentSize)

        XCTAssertGreaterThan(meaningfulPixels(in: bitmap, xRange: 0..<bitmap.pixelsWide, yRange: 0..<bitmap.pixelsHigh), 2000)
        XCTAssertGreaterThan(colorVariety(in: bitmap), 12)
    }

    private func makeDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: "MenuStatPanelRenderingTests.\(UUID().uuidString)") else {
            fatalError("Unable to create isolated UserDefaults suite for test")
        }
        return defaults
    }

    private func render(_ view: some View, size: CGSize) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.wantsLayer = true

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        window.contentView = nil
        return bitmap
    }

    private func meaningfulPixels(in bitmap: NSBitmapImageRep, xRange: Range<Int>, yRange: Range<Int>) -> Int {
        var count = 0
        for x in stride(from: max(0, xRange.lowerBound), to: min(bitmap.pixelsWide, xRange.upperBound), by: 4) {
            for y in stride(from: max(0, yRange.lowerBound), to: min(bitmap.pixelsHigh, yRange.upperBound), by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.2
                else { continue }

                let isNearlyWhite = color.redComponent > 0.94
                    && color.greenComponent > 0.94
                    && color.blueComponent > 0.94
                let isNotEmpty = !isNearlyWhite
                if isNotEmpty {
                    count += 1
                }
            }
        }
        return count
    }

    private func colorVariety(in bitmap: NSBitmapImageRep) -> Int {
        var buckets = Set<String>()
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 24) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.2
                else { continue }
                let red = Int((color.redComponent * 8).rounded())
                let green = Int((color.greenComponent * 8).rounded())
                let blue = Int((color.blueComponent * 8).rounded())
                buckets.insert("\(red)-\(green)-\(blue)")
            }
        }
        return buckets.count
    }
}
