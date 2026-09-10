import AppKit
import XCTest
@testable import ResourceMonitorWidget

/// Fallback launcher: when every widget is hidden a gauge-only item stays in
/// the bar as the re-entry point. Docker-style: any click opens the same
/// hosted panel — same menu chrome and hover pills as the widget popovers —
/// with one re-add row per widget.
@MainActor
final class FallbackWidgetTests: XCTestCase {
    private func makeController() -> StatusBarController {
        StatusBarController(cpu: CPUMonitor(), mem: MemoryMonitor(),
                            disk: DiskMonitor(), procs: ProcessMonitor())
    }

    func testFallbackVisibleOnlyWhenAllWidgetsHidden() {
        XCTAssertTrue(StatusBarController.fallbackVisible(cpuVisible: false, memVisible: false, diskVisible: false))
        for (cpu, mem, disk) in [(true, false, false), (false, true, false), (false, false, true),
                                 (true, true, false), (true, false, true), (false, true, true),
                                 (true, true, true)] {
            XCTAssertFalse(StatusBarController.fallbackVisible(cpuVisible: cpu, memVisible: mem, diskVisible: disk),
                           "fallback must stay hidden while any widget shows (\(cpu), \(mem), \(disk))")
        }
    }

    func testFallbackRowsListEveryWidget() {
        let rows = makeController().fallbackRows()
        XCTAssertEqual(rows.map(\.title), ["CPU", "Memory", "Storage"])
        XCTAssertEqual(rows.map { $0.kind }, [.cpu, .memory, .disk])
    }

    func testFallbackSelectorIsHostedPopoverMenu() {
        // Same presentation as the widget panels: one hosted SwiftUI view in
        // standard menu chrome — never a stock menu, never vibrantDark. And
        // sized to its short content, not a 290pt panel.
        let menu = makeController().fallbackSelectorMenu()
        XCTAssertEqual(menu.items.count, 1)
        let width = menu.items[0].view?.frame.width ?? 0
        XCTAssertGreaterThan(width, 80)
        XCTAssertLessThan(width, 290)
        XCTAssertNil(menu.appearance)
    }

    func testFallbackAnchorUsesNarrowMenuWidth() {
        // anchorX keeps the menu's right edge on screen; a narrow fallback
        // panel clamps later than a 316pt widget panel.
        XCTAssertEqual(StatusBarController.anchorX(iconLeft: 1800, visibleMinX: 0, visibleMaxX: 1920, menuWidth: 150),
                       1770)
        XCTAssertEqual(StatusBarController.anchorX(iconLeft: 100, visibleMinX: 0, visibleMaxX: 1920, menuWidth: 150),
                       100)
    }

    func testFallbackRowReAddsWidget() {
        let saved = UserDefaults.standard.object(forKey: "showCPU")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "showCPU") }
            else { UserDefaults.standard.removeObject(forKey: "showCPU") }
        }
        let c = makeController()
        c.start()
        UserDefaults.standard.set(false, forKey: "showCPU")
        c.enableWidget(.cpu)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "showCPU"))
    }

    func testRemovingAllWidgetsShowsFallback() {
        // End-to-end wiring: hide every widget through the real Widgets
        // submenu rows; the launcher must surface, and re-adding any widget
        // through the fallback path must hide it again.
        let keys = ["showCPU", "showMEM", "showDisk"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        defer {
            for (k, v) in saved {
                if let v { UserDefaults.standard.set(v, forKey: k) }
                else { UserDefaults.standard.removeObject(forKey: k) }
            }
        }
        UserDefaults.standard.set(true, forKey: "showCPU")
        UserDefaults.standard.set(true, forKey: "showMEM")
        UserDefaults.standard.set(true, forKey: "showDisk")
        let c = makeController()
        c.start()
        XCTAssertFalse(c.isFallbackShown)
        for kind in [MeterKind.cpu, .memory, .disk] {
            let sub = c.contextMenu(for: kind).items[1].submenu!
            c.toggleWidget(sub.items[kind.rawValue])
        }
        XCTAssertTrue(c.isFallbackShown, "hiding every widget must surface the fallback launcher")
        c.enableWidget(.cpu)
        XCTAssertFalse(c.isFallbackShown)
    }

    func testFallbackToggleSuppressionIsConsumeOnce() {
        let c = makeController()
        XCTAssertFalse(c.shouldSuppressFallbackToggle())
        c.fallbackDismissedAt = Date()
        XCTAssertTrue(c.shouldSuppressFallbackToggle())
        XCTAssertFalse(c.shouldSuppressFallbackToggle(), "suppression must consume after one use")
    }

    func testFallbackToggleSuppressionExpires() {
        let c = makeController()
        let now = Date()
        c.fallbackDismissedAt = now.addingTimeInterval(-0.05)
        XCTAssertTrue(c.shouldSuppressFallbackToggle(now: now))
        c.fallbackDismissedAt = now.addingTimeInterval(-0.2)
        XCTAssertFalse(c.shouldSuppressFallbackToggle(now: now))
    }
}
