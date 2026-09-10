import AppKit
import ServiceManagement
import XCTest
@testable import ResourceMonitorWidget

/// Right-click menu structure: Battery's item set (toggle, separator,
/// remove) must survive refactors. Read-only — never invokes actions.
@MainActor
final class MenuStructureTests: XCTestCase {
    private func makeController() -> StatusBarController {
        StatusBarController(cpu: CPUMonitor(), mem: MemoryMonitor(),
                            disk: DiskMonitor(), procs: ProcessMonitor())
    }

    func testContextMenuMatchesBatteryItemSet() {
        for kind in [MeterKind.cpu, .memory, .disk] {
            let menu = makeController().contextMenu(for: kind)
            XCTAssertEqual(menu.items.count, 5, "kind \(kind)")
            XCTAssertEqual(menu.items[0].title, "Show Percentage")
            XCTAssertEqual(menu.items[1].title, "Widgets")
            XCTAssertNotNil(menu.items[1].submenu)
            XCTAssertTrue(menu.items[2].isSeparatorItem)
            XCTAssertEqual(menu.items[3].title, "Open at Login")
            XCTAssertEqual(menu.items[4].title, "Remove")
            XCTAssertEqual(menu.items[0].representedObject as? Int, kind.rawValue)
            XCTAssertEqual(menu.items[4].representedObject as? Int, kind.rawValue)
            XCTAssertNotNil(menu.items[0].action)
            XCTAssertNotNil(menu.items[3].action)
            XCTAssertNotNil(menu.items[4].action)
        }
    }

    func testWidgetsSubmenuStaysInSyncAcrossMenus() {
        // Every widget's menu must show identical visibility states.
        let keys = ["showCPU", "showMEM", "showDisk"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        defer {
            for (k, v) in saved {
                if let v { UserDefaults.standard.set(v, forKey: k) }
                else { UserDefaults.standard.removeObject(forKey: k) }
            }
        }
        UserDefaults.standard.set(true, forKey: "showCPU")
        UserDefaults.standard.set(false, forKey: "showMEM")
        UserDefaults.standard.set(true, forKey: "showDisk")
        for kind in [MeterKind.cpu, .memory, .disk] {
            let sub = makeController().contextMenu(for: kind).items[1].submenu!
            XCTAssertEqual(sub.items.map(\.title), ["CPU", "Memory", "Storage"])
            XCTAssertEqual(sub.items.map { $0.state }, [.on, .off, .on], "kind \(kind)")
            XCTAssertEqual(sub.items.map { $0.representedObject as? Int }, [0, 1, 2] as [Int?])
        }
    }

    func testWidgetsSubmenuTogglesVisibility() {
        let saved = UserDefaults.standard.object(forKey: "showMEM")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "showMEM") }
            else { UserDefaults.standard.removeObject(forKey: "showMEM") }
        }
        let c = makeController()
        c.start()
        UserDefaults.standard.set(true, forKey: "showMEM")
        let item = c.contextMenu(for: .cpu).items[1].submenu!.items[1]
        c.toggleWidget(item)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "showMEM"))
        c.toggleWidget(item)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "showMEM"))
    }

    func testOpenAtLoginReflectsServiceStatus() {
        let expected: NSControl.StateValue = SMAppService.mainApp.status == .enabled ? .on : .off
        for kind in [MeterKind.cpu, .memory, .disk] {
            XCTAssertEqual(makeController().contextMenu(for: kind).items[3].state, expected)
        }
    }

    func testContextMenuUsesVibrantDarkAppearance() {
        // Regression: the menu rendered with the light app appearance instead
        // of the Battery reference's dark vibrant menu-bar menu.
        for kind in [MeterKind.cpu, .memory, .disk] {
            XCTAssertEqual(makeController().contextMenu(for: kind).appearance?.name, .vibrantDark)
        }
    }

    func testContextMenuGapMatchesBattery() {
        // Regression: the menu spawned flush under the bar; Battery floats it
        // ~10pt below. Locks the anchor offset.
        XCTAssertEqual(StatusBarController.contextMenuTopGap, 10)
    }

    func testMenuHostsAreCachedPerWidget() {
        // Regression: rebuilding the hosting view on every open made opens
        // feel sluggish; each widget must reuse one host.
        let c = makeController()
        for kind in [MeterKind.cpu, .memory, .disk] {
            XCTAssertTrue(c.menuHost(for: kind) === c.menuHost(for: kind),
                          "\(kind) menu host must be reused for instant opens")
        }
        XCTAssertFalse(c.menuHost(for: .cpu) === c.menuHost(for: .memory))
    }

    func testHeightReportsResizeMenuContent() {
        // Regression: grown content (new significant app while open) was
        // cropped top and bottom because the menu item kept its open-time
        // height. Growing must resize the live hosting view.
        let c = makeController()
        let host = c.menuHost(for: .cpu)
        host.setFrameSize(NSSize(width: 290, height: 200))
        c.refitOpenMenu(kind: .cpu, height: 350)
        XCTAssertEqual(host.frame.height, 350)
        c.refitOpenMenu(kind: .cpu, height: 0.5) // degenerate reports ignored
        XCTAssertEqual(host.frame.height, 350)
    }

    func testShowPercentageReflectsStoredPreference() {
        let key = "showCPUPct"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertEqual(makeController().contextMenu(for: .cpu).items[0].state, .on)
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertEqual(makeController().contextMenu(for: .cpu).items[0].state, .off)
    }
}
