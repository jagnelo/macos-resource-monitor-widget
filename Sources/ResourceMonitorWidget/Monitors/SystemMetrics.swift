import Foundation
import Darwin

// MARK: - Shared formatting

/// Repeating timer that also fires while menus are being tracked
/// (event-tracking runloop mode), so samplers keep updating live content
/// while a popover is open — like the Battery widget. Plain
/// `Timer.scheduledTimer` only fires in the default mode and stalls for the
/// whole time a menu is up.
func scheduleCommonTimer(interval: TimeInterval, repeats: Bool = true, block: @escaping (Timer) -> Void) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
    RunLoop.main.add(timer, forMode: .common)
    return timer
}

/// Decimal GB/MB/KB (disk) or binary GiB/MiB/KiB (RAM, matching Activity
/// Monitor: a "16 GB" machine is 16 GiB). GB values keep one decimal — no
/// whole-number rounding — except exact whole numbers ("16 GB").
public func humanBytes(_ bytes: UInt64, binary: Bool = false) -> String {
    let unit: Double = binary ? 1_073_741_824.0 : 1_000_000_000.0
    let gb = Double(bytes) / unit
    if gb >= 10 {
        let oneDecimal = (gb * 10).rounded() / 10
        if oneDecimal.truncatingRemainder(dividingBy: 1) == 0 { return String(format: "%.0f GB", gb) }
        return String(format: "%.1f GB", gb)
    }
    if gb >= 1 { return String(format: "%.2f GB", gb) }
    let mb = Double(bytes) / (unit / 1_000.0)
    if mb >= 1 { return String(format: "%.0f MB", mb) }
    let kb = Double(bytes) / (unit / 1_000_000.0)
    return String(format: "%.0f KB", kb)
}

public func humanBytesGiB(_ bytes: UInt64) -> String {
    humanBytes(bytes, binary: true)
}

// MARK: - CPU

/// Polls host_processor_info(PROCESSOR_CPU_LOAD_INFO) and computes per-core + overall usage from tick deltas.
/// All public API, no entitlements. ~1-2s polling is cheap (<0.1% CPU).
@MainActor
@Observable
public final class CPUMonitor {
    public internal(set) var overall: Double = 0        // 0...1
    public internal(set) var perCore: [Double] = []     // 0...1 each
    public internal(set) var history: [Double] = []     // last 60 samples of overall

    private var prevTicks: [[UInt32]] = []
    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 1.5) {
        stop()
        // Prime the delta baseline so first real sample isn't a spike.
        _ = sample()
        timer = scheduleCommonTimer(interval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        guard let usage = sample() else { return }
        overall = usage.overall
        perCore = usage.perCore
        history.append(usage.overall)
        if history.count > 60 { history.removeFirst(history.count - 60) }
    }

    private func sample() -> (overall: Double, perCore: [Double])? {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            // host_processor_info allocates via vm_allocate; must free with vm_deallocate.
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let states = Int(CPU_STATE_MAX)
        var perCoreUsage: [Double] = []
        perCoreUsage.reserveCapacity(Int(cpuCount))

        var totalActive: UInt64 = 0
        var totalTicks: UInt64 = 0

        for cpu in 0..<Int(cpuCount) {
            let base = cpu * states
            var ticks: [UInt32] = [0, 0, 0, 0]
            for s in 0..<states {
                // info[] is integer_t; load states are cumulative tick counters.
                ticks[s] = UInt32(bitPattern: info[base + s])
            }
            let user = UInt64(ticks[Int(CPU_STATE_USER)])
            let sys = UInt64(ticks[Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(ticks[Int(CPU_STATE_NICE)])
            let idle = UInt64(ticks[Int(CPU_STATE_IDLE)])
            let active = user + sys + nice
            let total = active + idle

            var usage: Double = 0
            if cpu < prevTicks.count {
                let prev = prevTicks[cpu]
                let pActive = UInt64(prev[Int(CPU_STATE_USER)])
                    + UInt64(prev[Int(CPU_STATE_SYSTEM)])
                    + UInt64(prev[Int(CPU_STATE_NICE)])
                let pIdle = UInt64(prev[Int(CPU_STATE_IDLE)])
                let dActive = active >= pActive ? active - pActive : 0
                let dTotal = total >= (pActive + pIdle) ? total - (pActive + pIdle) : 0
                if dTotal > 0 { usage = Double(dActive) / Double(dTotal) }
            }
            perCoreUsage.append(min(max(usage, 0), 1))
            totalActive += active
            totalTicks += total
        }

        // Overall from summed deltas (more stable than averaging per-core ratios).
        var overallUsage: Double = 0
        if !prevTicks.isEmpty {
            var pActive: UInt64 = 0, pTotal: UInt64 = 0
            for t in prevTicks {
                pActive += UInt64(t[Int(CPU_STATE_USER)])
                    + UInt64(t[Int(CPU_STATE_SYSTEM)])
                    + UInt64(t[Int(CPU_STATE_NICE)])
                pTotal += UInt64(t[Int(CPU_STATE_USER)])
                    + UInt64(t[Int(CPU_STATE_SYSTEM)])
                    + UInt64(t[Int(CPU_STATE_NICE)])
                    + UInt64(t[Int(CPU_STATE_IDLE)])
            }
            let dActive = totalActive >= pActive ? totalActive - pActive : 0
            let dTotal = totalTicks >= pTotal ? totalTicks - pTotal : 0
            if dTotal > 0 { overallUsage = Double(dActive) / Double(dTotal) }
        }

        // Save current ticks for next delta.
        var current: [[UInt32]] = []
        current.reserveCapacity(Int(cpuCount))
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * states
            current.append([
                UInt32(bitPattern: info[base + 0]),
                UInt32(bitPattern: info[base + 1]),
                UInt32(bitPattern: info[base + 2]),
                UInt32(bitPattern: info[base + 3]),
            ])
        }
        prevTicks = current

        return (min(max(overallUsage, 0), 1), perCoreUsage)
    }
}

// MARK: - Memory

public struct MemorySnapshot {
    public var totalBytes: UInt64 = 0
    public var usedBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var activeBytes: UInt64 = 0
    public var inactiveBytes: UInt64 = 0
    public var wiredBytes: UInt64 = 0
    public var compressedBytes: UInt64 = 0
    public var swapUsedBytes: UInt64 = 0
    public var swapTotalBytes: UInt64 = 0
    public var pressure: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

private struct XSwUsage {
    var xsu_total: UInt64 = 0
    var xsu_avail: UInt64 = 0
    var xsu_used: UInt64 = 0
    var xsu_pagesize: Int32 = 0
    var xsu_encrypted: UInt32 = 0
}

public func currentMemorySnapshot() -> MemorySnapshot {
    var snap = MemorySnapshot()

    // Total physical memory.
    var memSize: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &memSize, &size, nil, 0)
    snap.totalBytes = memSize

    // VM stats.
    var vmStats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &vmStats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)

    if kr == KERN_SUCCESS {
        let ps = UInt64(pageSize)
        let active = UInt64(vmStats.active_count) * ps
        let inactive = UInt64(vmStats.inactive_count) * ps
        let wired = UInt64(vmStats.wire_count) * ps
        let compressed = UInt64(vmStats.compressor_page_count) * ps
        let free = UInt64(vmStats.free_count) * ps
        snap.activeBytes = active
        snap.inactiveBytes = inactive
        snap.wiredBytes = wired
        snap.compressedBytes = compressed
        snap.freeBytes = free
        // "Used" in Activity Monitor terms ~= active + wired + compressed.
        snap.usedBytes = min(active + wired + compressed, memSize)
    }

    // Swap via vm.swapusage.
    var sw = XSwUsage()
    var swSize = MemoryLayout<XSwUsage>.size
    sysctlbyname("vm.swapusage", &sw, &swSize, nil, 0)
    snap.swapUsedBytes = sw.xsu_used
    snap.swapTotalBytes = sw.xsu_total

    return snap
}

@MainActor
@Observable
public final class MemoryMonitor {
    public internal(set) var snapshot = MemorySnapshot()
    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 2.0) {
        stop()
        refresh()
        timer = scheduleCommonTimer(interval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        snapshot = currentMemorySnapshot()
    }
}

// MARK: - Disk

public struct DiskSnapshot {
    public var totalBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var purgeableBytes: UInt64 = 0
    public var usedBytes: UInt64 { totalBytes >= freeBytes ? totalBytes - freeBytes : 0 }
    public var fraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
    public var volumes: [(name: String, total: UInt64, free: UInt64)] = []
}

public func currentDiskSnapshot() -> DiskSnapshot {
    var snap = DiskSnapshot()
    let root = URL(fileURLWithPath: "/")
    if let vals = try? root.resourceValues(forKeys: [
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
    ]) {
        if let total = vals.volumeTotalCapacity { snap.totalBytes = UInt64(total) }
        if let avail = vals.volumeAvailableCapacity { snap.freeBytes = UInt64(avail) }
        if let important = vals.volumeAvailableCapacityForImportantUsage,
           let avail = vals.volumeAvailableCapacity {
            // Purgeable ~= reclaimable difference; clamp at zero.
            let diff = Int64(avail) - Int64(important)
            snap.purgeableBytes = UInt64(max(diff, 0))
        }
    }
    // Mounted volumes for the popover (cheap, no recursive scan).
    if let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
    ], options: [.skipHiddenVolumes]) {
        for url in urls {
            guard let vals = try? url.resourceValues(forKeys: [
                .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            ]) else { continue }
            guard let total = vals.volumeTotalCapacity, total > 0 else { continue }
            let free = vals.volumeAvailableCapacity ?? 0
            let name = vals.volumeName ?? url.lastPathComponent
            snap.volumes.append((name, UInt64(total), UInt64(max(free, 0))))
        }
        snap.volumes.sort { ($0.total - $0.free) > ($1.total - $1.free) }
    }
    return snap
}

@MainActor
@Observable
public final class DiskMonitor {
    public internal(set) var snapshot = DiskSnapshot()
    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 15.0) {
        stop()
        refresh()
        timer = scheduleCommonTimer(interval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        snapshot = currentDiskSnapshot()
    }
}
