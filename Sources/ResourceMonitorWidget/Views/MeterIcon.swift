import AppKit

/// Shared "battery language, different glyph" meter icons.
///
/// Rendered as flat 2D monochrome **template** NSImages (like Apple's own menu
/// icons), so the system tints them automatically: white on a dark menu bar,
/// black on a light one. No state colors, no 3D — the fill level alone conveys
/// pressure, like Battery. Fill is quantized to 10 discrete states so the icon
/// reads at a glance even with the % hidden, and doesn't flicker on tiny changes.
///
/// - CPU: pinned chip, fills left-to-right
/// - Memory: toothed stick, fills left-to-right
/// - Storage: wireframe tank, fills bottom-up like a liquid level
///
/// All three share one Battery-matched visual language: 10pt art height in
/// the 18×13 box, 1.2 stroke, 2.2 corner radius, tight fill gaps — measured
/// off the SF battery symbol's outline, rim and fill proportions.
public enum MeterKind: Int, Sendable { case cpu = 0, memory = 1, disk = 2 }

private let meterStates = 10.0

/// Logo-exact gauge geometry (AppKit degrees, y-up), shared by the AppIcon
/// artwork and the fallback glyph so the two can never drift: the track
/// starts at 150° and sweeps 240° clockwise, leaving the gap at the bottom;
/// the needle sits 42% along the sweep (≈49.2°). All other gauge measures
/// are proportions of the track radius: width 92/300, needle length 232/300
/// and width 34/300, hub ring 56/300 with a 32/300 punched center.
let gaugeArcStart: CGFloat = 150
let gaugeArcSweep: CGFloat = 240
let gaugeNeedleT: CGFloat = 0.42

public func quantizedFraction(_ fraction: Double) -> Double {
    (min(max(fraction, 0), 1) * meterStates).rounded() / meterStates
}

public func makeStatusImage(kind: MeterKind, fraction: Double, percentText: String?) -> NSImage {
    // Single template image holding "% + glyph": one image-only status item
    // carries far less button chrome than title+image, which is what keeps
    // the trio right of the notch on crowded menu bars. Text uses the same
    // menu-bar typeface; the template tint applies to text and glyph alike.
    let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    var textSize = NSZeroSize
    if let percentText, !percentText.isEmpty {
        textSize = NSAttributedString(string: percentText, attributes: [.font: font]).size()
    }
    // Same %↔glyph gap as the native Battery widget.
    let gap: CGFloat = textSize.width > 0 ? 2 : 0
    let iconW: CGFloat = 18
    let totalW = ceil(textSize.width) + gap + iconW
    let totalH: CGFloat = 13
    let image = NSImage(size: NSSize(width: totalW, height: totalH), flipped: false) { _ in
        NSColor.black.set()
        if textSize.width > 0, let percentText {
            NSAttributedString(
                string: percentText,
                attributes: [.font: font, .foregroundColor: NSColor.black]
            ).draw(at: NSPoint(x: 0, y: (totalH - textSize.height) / 2))
        }
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.translateBy(x: ceil(textSize.width) + gap, y: 0)
            let iconRect = NSRect(x: 0, y: 0, width: iconW, height: totalH)
            switch kind {
            case .cpu: drawCPUMeter(in: iconRect, fraction: quantizedFraction(fraction))
            case .memory: drawMemoryMeter(in: iconRect, fraction: quantizedFraction(fraction))
            case .disk: drawDiskMeter(in: iconRect, fraction: quantizedFraction(fraction))
            }
            ctx.restoreGState()
        }
        return true
    }
    image.isTemplate = true
    return image
}

/// Launcher glyph shown when all three widgets are hidden: the AppIcon
/// gauge redrawn 1:1 in the monochrome template language — same 150°/240°
/// sweep with the gap at the bottom, same 42%-along needle, same ring hub.
///
/// A standard 18×18pt menu-bar extra (Apple HIG), so it sits next to native
/// extras like Now Playing at the same size and alignment — not the 13pt
/// Battery-style box the %-carrying widgets use.
public func makeFallbackImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.set()
        // Optically centered with native-extra margins: the stroke crowns
        // at y≈16.7 and the gap endpoints land at y≈1.7.
        let center = NSPoint(x: 9, y: 9.2)
        let radius: CGFloat = 6.5
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: gaugeArcStart, endAngle: gaugeArcStart - gaugeArcSweep,
                      clockwise: true)
        arc.lineWidth = radius * 92 / 300
        arc.lineCapStyle = .round
        arc.stroke()
        // Logo-exact needle: 42% along the sweep, 232/300 of the radius.
        let a = Double(gaugeArcStart - gaugeArcSweep * gaugeNeedleT) * Double.pi / 180.0
        let tip = NSPoint(x: center.x + cos(a) * radius * 232 / 300,
                          y: center.y + sin(a) * radius * 232 / 300)
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: tip)
        needle.lineWidth = radius * 34 / 300
        needle.lineCapStyle = .round
        needle.stroke()
        // Ring hub with a punched center, like the logo's white ring.
        let hubR = radius * 56 / 300
        NSBezierPath(ovalIn: NSRect(x: center.x - hubR, y: center.y - hubR,
                                    width: hubR * 2, height: hubR * 2)).fill()
        if let ctx = NSGraphicsContext.current {
            ctx.saveGraphicsState()
            ctx.compositingOperation = .destinationOut
            let holeR = radius * 32 / 300
            NSBezierPath(ovalIn: NSRect(x: center.x - holeR, y: center.y - holeR,
                                        width: holeR * 2, height: holeR * 2)).fill()
            ctx.restoreGraphicsState()
        }
        return true
    }
    image.isTemplate = true
    return image
}

private func drawCPUMeter(in rect: NSRect, fraction f: Double) {
    // Pinned chip on all four sides: the universally-recognizable processor.
    // Same 1.2 stroke and matched art height as its siblings.
    let pins = NSBezierPath()
    pins.lineWidth = 1.2
    pins.lineCapStyle = .round
    for x in [7.0, 9.0, 11.0] {
        pins.move(to: NSPoint(x: x, y: 11.0))
        pins.line(to: NSPoint(x: x, y: 12.1))
        pins.move(to: NSPoint(x: x, y: 2.0))
        pins.line(to: NSPoint(x: x, y: 0.9))
    }
    for y in [4.0, 6.5, 9.0] {
        pins.move(to: NSPoint(x: 3.5, y: y))
        pins.line(to: NSPoint(x: 5.0, y: y))
        pins.move(to: NSPoint(x: 13.0, y: y))
        pins.line(to: NSPoint(x: 14.5, y: y))
    }
    pins.stroke()
    let body = NSRect(x: 5, y: 2, width: 8, height: 9)
    NSBezierPath(roundedRect: body, xRadius: 2, yRadius: 2).withLineWidth(1.2).stroke()
    let inset = body.insetBy(dx: 1.2, dy: 1.2)
    let w = inset.width * f
    if w > 0.4 {
        NSBezierPath(rect: NSRect(x: inset.minX, y: inset.minY, width: w, height: inset.height)).fill()
    }
}

private func drawMemoryMeter(in rect: NSRect, fraction f: Double) {
    // Tall teeth with an off-center key notch read as a memory module; same
    // 1.2 stroke and matched art height as its siblings.
    for x in [2.2, 4.9, 7.6, 13.0] {
        NSBezierPath(rect: NSRect(x: x, y: 1.0, width: 1.9, height: 2.0)).fill()
    }
    let bar = NSRect(x: 1, y: 3, width: 16, height: 8.5)
    NSBezierPath(roundedRect: bar, xRadius: 2.2, yRadius: 2.2).withLineWidth(1.2).stroke()
    let inset = bar.insetBy(dx: 1.2, dy: 1.2)
    let w = inset.width * f
    if w > 0.5 {
        NSBezierPath(rect: NSRect(x: inset.minX, y: inset.minY, width: w, height: inset.height)).fill()
    }
}

private func drawDiskMeter(in rect: NSRect, fraction f: Double) {
    // Wireframe tank: full top rim, straight sides, curved belly; the level
    // rises with use like a liquid. Same 1.2 stroke and matched art height.
    // NOTE: drawing-handler coordinates are flipped:false, i.e. origin is
    // bottom-left, y grows upward.
    let sil = NSBezierPath()
    sil.move(to: NSPoint(x: 3.5, y: 4.0))
    sil.line(to: NSPoint(x: 3.5, y: 9.7))
    sil.curve(to: NSPoint(x: 14.5, y: 9.7),
              controlPoint1: NSPoint(x: 6.0, y: 12.2), controlPoint2: NSPoint(x: 12.0, y: 12.2))
    sil.line(to: NSPoint(x: 14.5, y: 4.0))
    sil.curve(to: NSPoint(x: 3.5, y: 4.0),
              controlPoint1: NSPoint(x: 11.5, y: 0.8), controlPoint2: NSPoint(x: 6.5, y: 0.8))
    sil.close()
    // Liquid level clipped to the full silhouette, deliberately overfilled
    // past the walls so no seam survives at the edges; the strokes drawn
    // over it stay crisp. Full reads fully solid, like Battery at 100%.
    if let ctx = NSGraphicsContext.current {
        ctx.saveGraphicsState()
        sil.addClip()
        let h = 9.7 * f
        if h > 0.4 {
            NSBezierPath(rect: NSRect(x: 3.0, y: 1.0, width: 12, height: 0.6 + min(h, 9.7))).fill()
        }
        ctx.restoreGraphicsState()
    }
    sil.lineWidth = 1.2
    sil.lineCapStyle = .round
    sil.lineJoinStyle = .round
    sil.stroke()
    NSBezierPath(ovalIn: NSRect(x: 3.5, y: 7.9, width: 11, height: 3.6)).withLineWidth(1.2).stroke()
}

private extension NSBezierPath {
    func withLineWidth(_ w: CGFloat) -> NSBezierPath {
        lineWidth = w
        return self
    }
}
