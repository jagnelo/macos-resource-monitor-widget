import Darwin
import XCTest
@testable import ResourceMonitorWidget

/// Live-sampler invariants: tolerant assertions that hold on any machine,
/// guarding the sampling code against API breakage and corrupt readings.
@MainActor
final class MonitorTests: XCTestCase {
    func testCPUSamplingInvariants() {
        let cpu = CPUMonitor()
        cpu.refresh()
        cpu.refresh() // second sample yields real deltas, not the primed zero
        XCTAssertEqual(cpu.perCore.count, ProcessInfo.processInfo.processorCount)
        XCTAssertTrue(cpu.perCore.allSatisfy { (0...1).contains($0) })
        XCTAssertTrue((0...1).contains(cpu.overall))
        XCTAssertLessThanOrEqual(cpu.history.count, 60)
    }

    func testMemorySnapshotInvariants() {
        let mem = MemoryMonitor()
        mem.refresh()
        let snap = mem.snapshot
        XCTAssertGreaterThan(snap.totalBytes, 0)
        XCTAssertLessThanOrEqual(snap.usedBytes, snap.totalBytes)
        XCTAssertTrue((0...1).contains(snap.pressure))
        XCTAssertEqual(snap.wiredBytes + snap.freeBytes <= snap.totalBytes, true)
    }

    func testDiskSnapshotInvariants() {
        let disk = DiskMonitor()
        disk.refresh()
        let snap = disk.snapshot
        XCTAssertGreaterThan(snap.totalBytes, 0)
        XCTAssertLessThanOrEqual(snap.usedBytes, snap.totalBytes)
        XCTAssertTrue((0...1).contains(snap.fraction))
        XCTAssertFalse(snap.volumes.isEmpty)
        // Sorted by used bytes descending, like the popover shows.
        let used = snap.volumes.map { $0.total - $0.free }
        XCTAssertEqual(used, used.sorted(by: >))
    }

    /// Proves values come from the live system, not constants: memory total
    /// must equal an independent hw.memsize read on this machine.
    func testMemoryTotalMatchesSystemHardware() {
        var memSize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        XCTAssertEqual(sysctlbyname("hw.memsize", &memSize, &size, nil, 0), 0)
        XCTAssertGreaterThan(memSize, 0)
        let mem = MemoryMonitor()
        mem.refresh()
        XCTAssertEqual(mem.snapshot.totalBytes, memSize)
    }

    /// Proves disk values come from the live volume, not constants.
    func testDiskTotalMatchesLiveVolume() throws {
        let vals = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey])
        let total = try XCTUnwrap(vals.volumeTotalCapacity.map(UInt64.init))
        let disk = DiskMonitor()
        disk.refresh()
        XCTAssertEqual(disk.snapshot.totalBytes, total)
    }

    func testProcessListsAreBoundedAndSorted() {
        let procs = ProcessMonitor()
        let exp = expectation(description: "ps sample completes")
        Task {
            await procs.sample()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 15)
        XCTAssertLessThanOrEqual(procs.cpuApps.count, 5)
        XCTAssertLessThanOrEqual(procs.memApps.count, 5)
        let cpu = procs.cpuApps.map(\.cpuPercent)
        XCTAssertEqual(cpu, cpu.sorted(by: >))
        let rss = procs.memApps.map(\.rssBytes)
        XCTAssertEqual(rss, rss.sorted(by: >))
        XCTAssertTrue(procs.significantCPUApps.allSatisfy { $0.cpuPercent >= 20 })
        XCTAssertTrue(procs.significantMemApps.allSatisfy { $0.rssBytes >= 500_000_000 })
    }
}
