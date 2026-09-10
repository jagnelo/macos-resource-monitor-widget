import XCTest
@testable import ResourceMonitorWidget

/// Widget switching + toggle-suppression logic. The system swallows the click
/// that opens a second widget while one is showing, so the controller opens
/// the targeted widget directly; toggle actions arriving right after a
/// dismissal belong to the dismissing click, not to a new one.
@MainActor
final class WidgetSwitchTests: XCTestCase {
    private func makeController() -> StatusBarController {
        StatusBarController(cpu: CPUMonitor(), mem: MemoryMonitor(),
                            disk: DiskMonitor(), procs: ProcessMonitor())
    }

    func testClickOnDifferentWidgetOpensIt() {
        let c = makeController()
        XCTAssertEqual(c.autoOpenTarget(closed: .cpu, mouseKind: .memory), .memory)
        XCTAssertEqual(c.autoOpenTarget(closed: .cpu, mouseKind: .disk), .disk)
        XCTAssertEqual(c.autoOpenTarget(closed: .memory, mouseKind: .cpu), .cpu)
        XCTAssertEqual(c.autoOpenTarget(closed: .memory, mouseKind: .disk), .disk)
        XCTAssertEqual(c.autoOpenTarget(closed: .disk, mouseKind: .cpu), .cpu)
        XCTAssertEqual(c.autoOpenTarget(closed: .disk, mouseKind: .memory), .memory)
    }

    func testClickOnSameWidgetDoesNotReopen() {
        let c = makeController()
        XCTAssertNil(c.autoOpenTarget(closed: .cpu, mouseKind: .cpu))
        XCTAssertNil(c.autoOpenTarget(closed: .memory, mouseKind: .memory))
        XCTAssertNil(c.autoOpenTarget(closed: .disk, mouseKind: .disk))
    }

    func testClickOutsideWidgetsOpensNothing() {
        let c = makeController()
        XCTAssertNil(c.autoOpenTarget(closed: .cpu, mouseKind: nil))
        XCTAssertNil(c.autoOpenTarget(closed: .memory, mouseKind: nil))
        XCTAssertNil(c.autoOpenTarget(closed: .disk, mouseKind: nil))
    }

    func testFreshDismissalWindow() {
        // A 0.5s suppression window swallowed legitimate fast re-clicks
        // (fastest human re-click measured at 376ms); genuine duplicates land
        // within ~10-50ms of close. 150ms splits the difference.
        XCTAssertEqual(StatusBarController.toggleFreshnessWindow, 0.15, accuracy: 0.0001)
        let now = Date()
        XCTAssertTrue(StatusBarController.isFreshDismissal(
            closedKind: .cpu, closedAt: now.addingTimeInterval(-0.05), kind: .cpu, now: now))
        XCTAssertFalse(StatusBarController.isFreshDismissal(
            closedKind: .cpu, closedAt: now.addingTimeInterval(-0.2), kind: .cpu, now: now))
        XCTAssertFalse(StatusBarController.isFreshDismissal(
            closedKind: .cpu, closedAt: now.addingTimeInterval(-0.376), kind: .cpu, now: now))
        XCTAssertFalse(StatusBarController.isFreshDismissal(
            closedKind: .cpu, closedAt: now.addingTimeInterval(-0.01), kind: .memory, now: now))
    }

    func testHighlightFollowsOpenMenu() {
        // After switching widgets, the pressed look must move to the newly
        // opened widget instead of staying stuck on the first one.
        let c = makeController()
        c.start()
        for kind in [MeterKind.cpu, .memory, .disk] {
            c.setWidgetHighlight(true, for: kind)
            XCTAssertTrue(c.isWidgetHighlighted(kind), "\(kind) should look pressed while open")
            for other in [MeterKind.cpu, .memory, .disk] where other != kind {
                XCTAssertFalse(c.isWidgetHighlighted(other), "\(other) must not look pressed")
            }
            c.setWidgetHighlight(false, for: kind)
            XCTAssertFalse(c.isWidgetHighlighted(kind), "\(kind) should release on close")
        }
    }
}
