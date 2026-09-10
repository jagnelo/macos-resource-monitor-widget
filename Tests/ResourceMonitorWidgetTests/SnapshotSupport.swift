import AppKit
import SwiftUI
@testable import ResourceMonitorWidget

/// Errors raised by snapshot verification, with actionable messages.
enum SnapshotError: Error, CustomStringConvertible {
    case renderFailed(String)
    case missingReference(String)
    case sizeMismatch(String, NSSize, NSSize)
    case pixelsDiffer(String, fraction: Double, actualPath: String)

    var description: String {
        switch self {
        case .renderFailed(let name):
            return "snapshot '\(name)': offscreen render produced no image"
        case .missingReference(let name):
            return "snapshot '\(name)': no reference image — record one with RMW_RECORD=1 swift test --filter SnapshotTests"
        case .sizeMismatch(let name, let actual, let ref):
            return "snapshot '\(name)': size \(Int(actual.width))x\(Int(actual.height)) != reference \(Int(ref.width))x\(Int(ref.height))"
        case .pixelsDiffer(let name, let fraction, let actualPath):
            return String(format: "snapshot '%@': %.2f%% of pixels differ — see %@", name, fraction * 100, actualPath)
        }
    }
}

/// Offscreen renderer + record/compare harness for the popover views.
/// Renders at 1x in an offscreen window (no screen-recording permission
/// needed — the window never appears on screen).
enum SnapshotSupport {
    /// Max fraction of pixels allowed to differ beyond channel tolerance.
    static let maxDiffFraction = 0.005
    /// Per-channel tolerance (0-255) absorbing antialiasing noise.
    static let channelTolerance = 12

    static var moduleDir: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent() }
    static var referenceDir: URL { moduleDir.appendingPathComponent("ReferenceImages", isDirectory: true) }
    static var resultsDir: URL {
        moduleDir.deletingLastPathComponent().appendingPathComponent("SnapshotResults", isDirectory: true)
    }
    static var recordMode: Bool { ProcessInfo.processInfo.environment["RMW_RECORD"] == "1" }

    @MainActor private static var galleryStarted = false

    @MainActor
    static func render<V: View>(_ view: V, appearance: NSAppearance) -> NSImage? {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.appearance = appearance
        let size = hosting.fittingSize
        guard size.width > 1, size.height > 1 else { return nil }
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.orderFrontRegardless()
        window.display()
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Fraction of pixels differing beyond channel tolerance, or nil when
    /// the bitmaps are incomparable.
    static func diffFraction(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double? {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
              a.bitsPerPixel == 32, b.bitsPerPixel == 32,
              let da = a.bitmapData, let db = b.bitmapData else { return nil }
        let w = a.pixelsWide, h = a.pixelsHigh
        let sa = a.bytesPerRow, sb = b.bytesPerRow
        var different = 0
        for y in 0..<h {
            for x in 0..<w {
                let oa = y * sa + x * 4, ob = y * sb + x * 4
                var hit = false
                for c in 0..<4 {
                    let d = Int(da[oa + c]) - Int(db[ob + c])
                    if d > channelTolerance || d < -channelTolerance { hit = true; break }
                }
                if hit { different += 1 }
            }
        }
        return Double(different) / Double(w * h)
    }

    /// Renders `view`, saves the actual PNG for the review gallery, and
    /// either records the reference (RMW_RECORD=1) or compares against it.
    @MainActor
    static func verify<V: View>(_ name: String, _ view: V, appearance: NSAppearance) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: resultsDir, withIntermediateDirectories: true)
        guard let image = render(view, appearance: appearance),
              let actual = pngData(image),
              let actualRep = NSBitmapImageRep(data: actual) else {
            throw SnapshotError.renderFailed(name)
        }
        let actualURL = resultsDir.appendingPathComponent("\(name).png")
        try actual.write(to: actualURL)
        let refURL = referenceDir.appendingPathComponent("\(name).png")
        if recordMode {
            try fm.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try actual.write(to: refURL)
            appendGallery(name: name, status: "RECORDED", actual: actualURL.lastPathComponent, reference: nil)
            return
        }
        guard fm.fileExists(atPath: refURL.path) else { throw SnapshotError.missingReference(name) }
        guard let refData = try? Data(contentsOf: refURL),
              let refRep = NSBitmapImageRep(data: refData) else {
            throw SnapshotError.renderFailed(name + " (reference undecodable)")
        }
        guard let fraction = diffFraction(actualRep, refRep) else {
            throw SnapshotError.sizeMismatch(name, actualRep.size, refRep.size)
        }
        if fraction > maxDiffFraction {
            appendGallery(name: name, status: String(format: "FAIL %.2f%%", fraction * 100),
                          actual: actualURL.lastPathComponent, reference: "../ResourceMonitorWidgetTests/ReferenceImages/\(name).png")
            throw SnapshotError.pixelsDiffer(name, fraction: fraction, actualPath: actualURL.path)
        }
        appendGallery(name: name, status: "PASS", actual: actualURL.lastPathComponent,
                      reference: "../ResourceMonitorWidgetTests/ReferenceImages/\(name).png")
    }

    @MainActor
    private static func appendGallery(name: String, status: String, actual: String, reference: String?) {
        let gallery = resultsDir.appendingPathComponent("gallery.html")
        if !galleryStarted {
            galleryStarted = true
            let head = """
                <html><head><meta charset="utf-8"><title>Popover snapshots</title>
                <style>body{background:#222;color:#ddd;font:13px system-ui}table{border-collapse:collapse}td,th{border:1px solid #444;padding:8px;vertical-align:top}img{background:repeating-conic-gradient(#333 0 25%,#222 0 50%) 0 0/16px 16px;max-width:420px}</style>
                </head><body><h1>Popover snapshots</h1><table><tr><th>name</th><th>status</th><th>actual</th><th>reference</th></tr>
                """
            try? head.write(to: gallery, atomically: true, encoding: .utf8)
        }
        let ref = reference.map { "<a href=\"\($0)\"><img src=\"\($0)\"></a>" } ?? "(recorded this run)"
        let row = "<tr><td>\(name)</td><td>\(status)</td><td><a href=\"\(actual)\"><img src=\"\(actual)\"></a></td><td>\(ref)</td></tr>\n"
        if let handle = try? FileHandle(forWritingTo: gallery) {
            defer { try? handle.close() }
            _ = try? handle.seekToEndOfFile()
            handle.write(Data(row.utf8))
        }
    }
}
