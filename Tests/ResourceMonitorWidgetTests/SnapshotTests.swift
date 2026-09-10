import AppKit
import SwiftUI
import XCTest
@testable import ResourceMonitorWidget

/// Visual regression layer: renders every popover with fixed fixtures in
/// light and dark appearances, and diffs against checked-in references.
/// Record references with: RMW_RECORD=1 swift test --filter SnapshotTests
/// Review output in Tests/SnapshotResults/gallery.html.
@MainActor
final class SnapshotTests: XCTestCase {
    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            return true
        }
    }

    private static func fixtureProcs() -> ProcessMonitor {
        let procs = ProcessMonitor()
        procs.cpuApps = [
            TopApp(key: "a", name: "Virtual Machine Service for Docker", icon: swatch(.systemBlue),
                   cpuPercent: 105, rssBytes: 2_264_924_160, processCount: 3),
            TopApp(key: "b", name: "OpenCode", icon: nil,
                   cpuPercent: 141, rssBytes: 1_513_560_064, processCount: 1),
            TopApp(key: "c", name: "Google Chrome", icon: nil,
                   cpuPercent: 24, rssBytes: 1_116_536_832, processCount: 9),
        ]
        procs.memApps = [
            TopApp(key: "a", name: "Virtual Machine Service for Docker", icon: swatch(.systemBlue),
                   cpuPercent: 105, rssBytes: 2_264_924_160, processCount: 3),
            TopApp(key: "b", name: "OpenCode", icon: nil,
                   cpuPercent: 141, rssBytes: 1_513_560_064, processCount: 1),
            TopApp(key: "c", name: "Google Chrome", icon: nil,
                   cpuPercent: 24, rssBytes: 1_116_536_832, processCount: 9),
        ]
        return procs
    }

    private static func fixtureCPU() -> CPUMonitor {
        let cpu = CPUMonitor()
        cpu.overall = 0.39
        cpu.perCore = [0.35, 0.29, 0.21, 0.16, 0.12, 0.11, 0.68, 0.66, 0.05, 0.09]
        cpu.history = [0.32, 0.35, 0.31, 0.38, 0.41, 0.36, 0.39, 0.42, 0.37, 0.40,
                       0.33, 0.36, 0.39, 0.41, 0.38, 0.35, 0.37, 0.40, 0.42, 0.39,
                       0.36, 0.38, 0.41, 0.39]
        return cpu
    }

    private static func fixtureMemory() -> MemoryMonitor {
        let mem = MemoryMonitor()
        var snap = MemorySnapshot()
        snap.totalBytes = 17_179_869_184
        snap.usedBytes = 12_025_908_429
        snap.wiredBytes = 2_684_354_560
        snap.compressedBytes = 8_220_835_840
        snap.swapUsedBytes = 8_589_934_592
        mem.snapshot = snap
        return mem
    }

    private static func fixtureDisk() -> DiskMonitor {
        let disk = DiskMonitor()
        var snap = DiskSnapshot()
        snap.totalBytes = 245_110_000_000
        snap.freeBytes = 39_400_000_000
        snap.purgeableBytes = 2_147_483_648
        snap.volumes = [("Macintosh HD", 245_110_000_000, 39_400_000_000)]
        disk.snapshot = snap
        return disk
    }

    private func verifyBothAppearances(_ name: String, _ view: AnyView) throws {
        try SnapshotSupport.verify(name + "-light", view,
                                    appearance: NSAppearance(named: .aqua)!)
        try SnapshotSupport.verify(name + "-dark", view,
                                    appearance: NSAppearance(named: .darkAqua)!)
    }

    func testCPUPopoverSnapshot() throws {
        try verifyBothAppearances("cpu", AnyView(CPUPopover(cpu: Self.fixtureCPU(), procs: Self.fixtureProcs())))
    }

    func testMemoryPopoverSnapshot() throws {
        try verifyBothAppearances("memory", AnyView(MemoryPopover(mem: Self.fixtureMemory(), procs: Self.fixtureProcs())))
    }

    func testDiskPopoverSnapshot() throws {
        try verifyBothAppearances("disk", AnyView(DiskPopover(disk: Self.fixtureDisk())))
    }

    func testFallbackPopoverSnapshot() throws {
        try verifyBothAppearances("fallback", AnyView(FallbackPopover(
            rows: [("CPU", .cpu), ("Memory", .memory), ("Storage", .disk)],
            onTap: { _ in })))
    }

    func testFallbackPopoverHoverSnapshot() throws {
        // Locks the hover geometry: every pill must span the full row so no
        // dead margin survives on the trailing side.
        try verifyBothAppearances("fallback-hover", AnyView(FallbackPopover(
            rows: [("CPU", .cpu), ("Memory", .memory), ("Storage", .disk)],
            onTap: { _ in }, previewHover: true)))
    }

}
