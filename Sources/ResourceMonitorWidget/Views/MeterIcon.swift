import AppKit

/// Shared "battery language, different glyph" meter icons.
///
/// Rendered as flat 2D monochrome **template** NSImages (like Apple's own menu
/// icons), so the system tints them automatically: white on a dark menu bar,
/// black on a light one. No state colors, no 3D — the fill level alone conveys
/// pressure, like Battery. Fill is quantized to 10 discrete states so the icon
/// reads at a glance even with the % hidden, and doesn't flicker on tiny changes.
///
/// - CPU: plain rounded-square chip die, fills left-to-right
/// - Memory: wide DIMM stick with a key notch in the bottom wall, fills left-to-right
/// - Storage: flat open-top container (U-shape), fills bottom-up — headroom to
///   the open top always shows how much is left
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
public func makeFallbackImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 13), flipped: false) { _ in
        NSColor.black.set()
        // Sized to sit optically centered: the stroke crowns at y≈11.9 and
        // the gap endpoints land at y≈1.1, mirroring the logo's margins.
        let center = NSPoint(x: 9, y: 6.5)
        let radius: CGFloat = 4.7
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
    let body = NSRect(x: 3, y: 1.5, width: 12, height: 10)
    NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5).withLineWidth(1.3).stroke()
    let inset = body.insetBy(dx: 2, dy: 2)
    let w = inset.width * f
    if w > 0.5 {
        NSBezierPath(rect: NSRect(x: inset.minX, y: inset.minY, width: w, height: inset.height)).fill()
    }
}

private func drawMemoryMeter(in rect: NSRect, fraction f: Double) {
    let bar = NSRect(x: 1, y: 3, width: 16, height: 7)
    NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).withLineWidth(1.3).stroke()
    // DIMM key notch: punch a see-through gap in the bottom wall center.
    if let ctx = NSGraphicsContext.current {
        ctx.saveGraphicsState()
        ctx.compositingOperation = .destinationOut
        NSBezierPath(rect: NSRect(x: 7.5, y: 1.8, width: 3, height: 2.8)).fill()
        ctx.restoreGraphicsState()
    }
    let inset = bar.insetBy(dx: 2, dy: 2)
    let w = inset.width * f
    if w > 0.5 {
        NSBezierPath(rect: NSRect(x: inset.minX, y: inset.minY, width: w, height: inset.height)).fill()
    }
}

private func drawDiskMeter(in rect: NSRect, fraction f: Double) {
    // NOTE: drawing-handler coordinates are flipped:false, i.e. origin is
    // bottom-left, y grows upward.
    let u = NSBezierPath()
    u.lineWidth = 1.3
    u.lineCapStyle = .round
    u.lineJoinStyle = .round
    u.move(to: NSPoint(x: 3, y: 11))
    u.line(to: NSPoint(x: 3, y: 3.5))
    u.line(to: NSPoint(x: 15, y: 3.5))
    u.line(to: NSPoint(x: 15, y: 11))
    u.stroke()
    // Fill bottom-up; at 100% it exactly reaches the wall tops.
    let fillH = 6.2 * f
    if fillH > 0.4 {
        NSBezierPath(rect: NSRect(x: 4.5, y: 4.8, width: 9, height: min(fillH, 6.2))).fill()
    }
}

private extension NSBezierPath {
    func withLineWidth(_ w: CGFloat) -> NSBezierPath {
        lineWidth = w
        return self
    }
}
