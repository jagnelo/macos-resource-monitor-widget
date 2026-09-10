import AppKit
import XCTest
@testable import ResourceMonitorWidget

/// Fallback launcher: when every widget is hidden a gauge-only item stays in
/// the bar as the re-entry point. Left-click lists all three widgets with
/// live checkmarks; right-click offers the same Widgets submenu without
/// Show Percentage (nothing to show it on) or Remove (it IS the re-entry).
@MainActor
final class FallbackWidgetTests: XCTestCase {
    private func makeController() -> StatusBarController {
        StatusBarController(cpu: CPUMonitor(), mem: MemoryMonitor(),
                            disk: DiskMonitor(), procs: ProcessMonitor())
    }

    private func withVisibility(cpu: Bool, mem: Bool, disk: Bool, _ body: () -> Void) {
        let keys = ["showCPU": cpu, "showMEM": mem, "showDisk": disk]
        let saved = Dictionary(uniqueKeysWithValues: keys.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        defer {
            for (k, v) in saved {
                if let v { UserDefaults.standard.set(v, forKey: k) }
                else { UserDefaults.standard.removeObject(forKey: k) }
            }
        }
        UserDefaults.standard.set(cpu, forKey: "showCPU")
        UserDefaults.standard.set(mem, forKey: "showMEM")
        UserDefaults.standard.set(disk, forKey: "showDisk")
        body()
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

    func testFallbackSelectorListsEveryWidgetWithLiveCheckmarks() {
        withVisibility(cpu: true, mem: false, disk: true) {
            let c = makeController()
            let menu = c.fallbackSelectorMenu()
            XCTAssertEqual(menu.items.map(\.title), ["CPU", "Memory", "Storage"])
            XCTAssertEqual(menu.items.map { $0.state }, [.on, .off, .on])
            XCTAssertEqual(menu.items.map { $0.representedObject as? Int }, [0, 1, 2] as [Int?])
            for item in menu.items {
                XCTAssertNotNil(item.action)
                XCTAssertNotNil(item.target)
            }
            XCTAssertEqual(menu.appearance?.name, .vibrantDark)
        }
    }

    func testFallbackSelectorTogglesVisibility() {
        let saved = UserDefaults.standard.object(forKey: "showCPU")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "showCPU") }
            else { UserDefaults.standard.removeObject(forKey: "showCPU") }
        }
        let c = makeController()
        c.start()
        UserDefaults.standard.set(false, forKey: "showCPU")
        c.toggleWidget(c.fallbackSelectorMenu().items[0])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "showCPU"))
        c.toggleWidget(c.fallbackSelectorMenu().items[0])
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "showCPU"))
    }

    func testFallbackContextMenuOmitsPercentageAndRemove() {
        let c = makeController()
        let menu = c.fallbackContextMenu()
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items[0].title, "Widgets")
        let sub = menu.items[0].submenu!
        XCTAssertEqual(sub.items.map(\.title), ["CPU", "Memory", "Storage"])
        for item in sub.items {
            XCTAssertNotNil(item.action)
        }
        XCTAssertFalse(menu.items.contains { $0.title == "Show Percentage" })
        XCTAssertFalse(menu.items.contains { $0.title == "Remove" })
        XCTAssertEqual(menu.appearance?.name, .vibrantDark)
    }

    func testRemovingAllWidgetsShowsFallback() {
        // End-to-end wiring: drive the real selector rows like a user
        // removing every widget; the launcher must surface, and re-adding
        // any widget must hide it again.
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
        for item in c.fallbackSelectorMenu().items {
            c.toggleWidget(item)
        }
        XCTAssertTrue(c.isFallbackShown, "hiding every widget must surface the fallback launcher")
        c.toggleWidget(c.fallbackSelectorMenu().items[0])
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
