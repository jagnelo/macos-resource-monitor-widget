import XCTest
@testable import ResourceMonitorWidget

/// Layout-math contracts: the per-core grid must show every core in balanced
/// rows without widening the popover.
final class LayoutLogicTests: XCTestCase {
    func testSmallCoreCountsUseOneRow() {
        XCTAssertEqual(popoverGridColumns(count: 1), 1)
        XCTAssertEqual(popoverGridColumns(count: 2), 2)
        XCTAssertEqual(popoverGridColumns(count: 4), 4)
        XCTAssertEqual(popoverGridColumns(count: 8), 8)
    }

    func testLargeCoreCountsRebalanceIntoEvenRows() {
        XCTAssertEqual(popoverGridColumns(count: 10), 5)   // 5+5, not 8+2
        XCTAssertEqual(popoverGridColumns(count: 12), 6)   // 6+6
        XCTAssertEqual(popoverGridColumns(count: 14), 7)   // 7+7
        XCTAssertEqual(popoverGridColumns(count: 16), 8)   // 8+8
        XCTAssertEqual(popoverGridColumns(count: 20), 7)   // 7+7+6
    }

    func testEmptyCountFallsBackToOneColumn() {
        XCTAssertEqual(popoverGridColumns(count: 0), 1)
    }

    func testEveryCoreFitsWithoutTruncation() {
        // For a range of realistic core counts, rows × columns covers all
        // cores and no row is left with a single straggler while a fuller
        // balanced layout exists.
        for n in [2, 4, 6, 8, 10, 12, 14, 16, 20, 24] {
            let cols = popoverGridColumns(count: n)
            XCTAssertGreaterThanOrEqual(cols * Int(ceil(Double(n) / Double(cols))), n,
                                        "n=\(n) cols=\(cols) must fit all cores")
            XCTAssertLessThanOrEqual(cols, 8, "n=\(n) must respect the column cap")
        }
    }
}
