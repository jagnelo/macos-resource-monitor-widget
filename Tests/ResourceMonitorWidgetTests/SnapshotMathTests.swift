import XCTest
@testable import ResourceMonitorWidget

/// Snapshot-struct math contracts (pressure, fractions, clamping).
final class SnapshotMathTests: XCTestCase {
    func testMemoryPressure() {
        var snap = MemorySnapshot()
        snap.totalBytes = 17_179_869_184
        snap.usedBytes = 8_589_934_592
        XCTAssertEqual(snap.pressure, 0.5, accuracy: 0.0001)
    }

    func testMemoryPressureWithZeroTotal() {
        XCTAssertEqual(MemorySnapshot().pressure, 0)
    }

    func testDiskFractionAndUsedBytes() {
        var snap = DiskSnapshot()
        snap.totalBytes = 245_110_000_000
        snap.freeBytes = 39_400_000_000
        XCTAssertEqual(snap.usedBytes, 205_710_000_000)
        XCTAssertEqual(snap.fraction, Double(205_710_000_000) / Double(245_110_000_000), accuracy: 0.0001)
    }

    func testDiskUsedBytesNeverUnderflows() {
        var snap = DiskSnapshot()
        snap.totalBytes = 100
        snap.freeBytes = 200 // corrupt/stale reading
        XCTAssertEqual(snap.usedBytes, 0)
    }

    func testDiskFractionWithZeroTotal() {
        XCTAssertEqual(DiskSnapshot().fraction, 0)
    }

    func testMeterKindRawValuesAreStable() {
        // Persisted in menu item tags/representedObjects — must not shift.
        XCTAssertEqual(MeterKind.cpu.rawValue, 0)
        XCTAssertEqual(MeterKind.memory.rawValue, 1)
        XCTAssertEqual(MeterKind.disk.rawValue, 2)
        XCTAssertEqual(MeterKind(rawValue: 0), .cpu)
        XCTAssertEqual(MeterKind(rawValue: 1), .memory)
        XCTAssertEqual(MeterKind(rawValue: 2), .disk)
        XCTAssertNil(MeterKind(rawValue: 3))
    }
}
