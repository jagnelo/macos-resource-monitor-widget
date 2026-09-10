import XCTest
@testable import ResourceMonitorWidget

/// Byte formatting contracts shared by all three popovers.
/// Decimal (disk/Finder style) is the default; binary (Activity Monitor
/// style) is opt-in per call.
final class FormattingTests: XCTestCase {
    // MARK: - Decimal (disk)

    func testDecimalGigabyteThresholds() {
        XCTAssertEqual(humanBytes(245_110_000_000), "245.1 GB")
        XCTAssertEqual(humanBytes(205_700_000_000), "205.7 GB")
        XCTAssertEqual(humanBytes(39_400_000_000), "39.4 GB")
        // Exact whole GB values carry no trailing decimal…
        XCTAssertEqual(humanBytes(245_000_000_000), "245 GB")
        // …but non-whole values are never rounded to integers.
        XCTAssertEqual(humanBytes(17_200_000_000), "17.2 GB")
        XCTAssertEqual(humanBytes(17_240_000_000), "17.2 GB")
    }

    func testDecimalSubGigabyteUnits() {
        XCTAssertEqual(humanBytes(9_860_000_000), "9.86 GB")
        XCTAssertEqual(humanBytes(988_000_000), "988 MB")
        XCTAssertEqual(humanBytes(12_000), "12 KB")
        XCTAssertEqual(humanBytes(0), "0 KB")
    }

    // MARK: - Binary (memory)

    func testBinaryMatchesActivityMonitor() {
        // A "16 GB" machine is 16 GiB — no trailing decimal.
        XCTAssertEqual(humanBytes(17_179_869_184, binary: true), "16 GB")
        XCTAssertEqual(humanBytes(2_684_354_560, binary: true), "2.50 GB")
        XCTAssertEqual(humanBytes(1_035_831_296, binary: true), "965 MB")
    }

    func testHumanBytesGiBDelegatesToBinary() {
        XCTAssertEqual(humanBytesGiB(17_179_869_184), humanBytes(17_179_869_184, binary: true))
        XCTAssertNotEqual(humanBytesGiB(17_179_869_184), humanBytes(17_179_869_184))
    }
}
