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

    func testFallbackImageIsIdleGaugeOnly() {
        // The all-widgets-hidden launcher must read as off: standard 18×18
        // menu-bar-extra geometry, template tint, empty gauge, no text.
        let image = makeFallbackImage()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }

    func testGaugeGeometryMatchesLogo() {
        // Locks the shared numbers so the glyph and the AppIcon artwork can
        // never drift: 150° start, 240° clockwise sweep (gap at bottom),
        // needle 42% along the sweep (≈49.2°).
        XCTAssertEqual(gaugeArcStart, 150)
        XCTAssertEqual(gaugeArcSweep, 240)
        XCTAssertEqual(gaugeNeedleT, 0.42)
        let needle = Double(gaugeArcStart - gaugeArcSweep * gaugeNeedleT)
        XCTAssertEqual(needle, 49.2, accuracy: 0.0001)
    }

    func testFallbackArcReachesBottomLikeLogo() {
        // The logo sweep runs 240° (150° → -90°); the first fallback draft
        // swept only 120° and left the whole lower half empty. Probe two
        // pixels only the full sweep inks: the crown and the lower-right
        // quadrant. Rendered explicitly 1x so coordinates are exact; the
        // flip-cancel makes the bitmap context behave like the (unflipped)
        // menu-bar context, otherwise the probes would assert mirrored rows.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 18,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.translateBy(x: 0, y: 18)
            ctx.scaleBy(x: 1, y: -1)
        }
        makeFallbackImage().draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        func alpha(_ x: Int, _ y: Int) -> CGFloat {
            rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
        }
        XCTAssertGreaterThan(alpha(9, 16), 0.05, "crown must be inked")
        XCTAssertGreaterThan(alpha(13, 4), 0.05, "240° sweep must reach the lower-right quadrant")
    }
}
