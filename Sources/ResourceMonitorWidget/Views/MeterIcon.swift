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

/// Launcher glyph shown when all three widgets are hidden: a miniature
/// gauge in the same monochrome template language as the meters.
public func makeFallbackImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 13), flipped: false) { _ in
        NSColor.black.set()
        let center = NSPoint(x: 9, y: 5)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: 5.2, startAngle: 150, endAngle: 30, clockwise: true)
        arc.lineWidth = 1.6
        arc.lineCapStyle = .round
        arc.stroke()
        let a = 54.0 * Double.pi / 180.0
        let tip = NSPoint(x: center.x + cos(a) * 3.9, y: center.y + sin(a) * 3.9)
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: tip)
        needle.lineWidth = 1.4
        needle.lineCapStyle = .round
        needle.stroke()
        NSBezierPath(ovalIn: NSRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4)).fill()
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
