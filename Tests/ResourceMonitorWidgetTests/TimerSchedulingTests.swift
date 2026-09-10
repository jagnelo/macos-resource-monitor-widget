import XCTest
@testable import ResourceMonitorWidget

/// Regression tests for frozen popovers: samplers must keep firing while a
/// menu is being tracked (event-tracking runloop mode), like Battery's live
/// values. Plain `Timer.scheduledTimer` only fires in the default mode.
final class TimerSchedulingTests: XCTestCase {
    func testCommonTimerIsRegisteredInCommonModes() {
        let timer = scheduleCommonTimer(interval: 60) { _ in }
        defer { timer.invalidate() }
        XCTAssertTrue(
            CFRunLoopContainsTimer(CFRunLoopGetMain(), timer as CFRunLoopTimer, .commonModes),
            "scheduleCommonTimer must use common modes or live updates freeze while a menu is open"
        )
    }

    func testCommonTimerRepeats() {
        let timer = scheduleCommonTimer(interval: 60) { _ in }
        defer { timer.invalidate() }
        XCTAssertTrue(timer.isValid)
        XCTAssertEqual(timer.timeInterval, 60)
    }
}
