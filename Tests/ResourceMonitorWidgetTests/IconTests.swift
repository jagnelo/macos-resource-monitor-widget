import AppKit
import XCTest
@testable import ResourceMonitorWidget

/// Menu-bar icon contracts: template tinting and the compact 18×13 glyph
/// geometry the bar layout depends on.
final class IconTests: XCTestCase {
    func testGlyphOnlyIconGeometry() {
        for kind in [MeterKind.cpu, .memory, .disk] {
            let image = makeStatusImage(kind: kind, fraction: 0.5, percentText: nil)
            XCTAssertTrue(image.isTemplate, "\(kind) must tint with the menu bar")
            XCTAssertEqual(image.size.height, 13)
            XCTAssertEqual(image.size.width, 18)
        }
    }

    func testPercentageWidensIconWithoutChangingHeight() {
        let plain = makeStatusImage(kind: .cpu, fraction: 0.5, percentText: nil)
        let pct = makeStatusImage(kind: .cpu, fraction: 0.5, percentText: "42%")
        XCTAssertGreaterThan(pct.size.width, plain.size.width)
        XCTAssertEqual(pct.size.height, plain.size.height)
        XCTAssertTrue(pct.isTemplate)
    }

    func testTrioMatchesBatterySpec() {
        // Battery parity contract: 11pt % text, 2pt gap, 18px glyph —
        // measured 52pt per widget / 156pt trio with "100%" on all three.
        // The trio must not fatten beyond that spec.
        var trio: CGFloat = 0
        for kind in [MeterKind.cpu, .memory, .disk] {
            let w = makeStatusImage(kind: kind, fraction: 1, percentText: "100%").size.width
            XCTAssertLessThanOrEqual(w, 52, "\(kind) single widget wider than Battery spec")
            trio += w
        }
        XCTAssertLessThanOrEqual(trio, 157, "trio with 100% wider than Battery-spec baseline")
    }

    func testQuantizedFractionSnapsToTenStates() {
        XCTAssertEqual(quantizedFraction(-0.2), 0)
        XCTAssertEqual(quantizedFraction(0.04), 0)
        XCTAssertEqual(quantizedFraction(0.05), 0.1, accuracy: 0.0001)
        XCTAssertEqual(quantizedFraction(0.55), 0.6, accuracy: 0.0001)
        XCTAssertEqual(quantizedFraction(1.7), 1)
    }
}
