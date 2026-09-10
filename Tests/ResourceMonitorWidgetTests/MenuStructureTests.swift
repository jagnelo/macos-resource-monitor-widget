import AppKit
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
            XCTAssertEqual(menu.items.count, 3, "kind \(kind)")
            XCTAssertEqual(menu.items[0].title, "Show Percentage")
            XCTAssertTrue(menu.items[1].isSeparatorItem)
            XCTAssertEqual(menu.items[2].title, "Remove")
            XCTAssertEqual(menu.items[0].representedObject as? Int, kind.rawValue)
            XCTAssertEqual(menu.items[2].representedObject as? Int, kind.rawValue)
            XCTAssertNotNil(menu.items[0].action)
            XCTAssertNotNil(menu.items[2].action)
        }
    }

    func testContextMenuUsesVibrantDarkAppearance() {
        // Regression: the menu rendered with the light app appearance instead
        // of the Battery reference's dark vibrant menu-bar menu.
        for kind in [MeterKind.cpu, .memory, .disk] {
            XCTAssertEqual(makeController().contextMenu(for: kind).appearance?.name, .vibrantDark)
        }
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
