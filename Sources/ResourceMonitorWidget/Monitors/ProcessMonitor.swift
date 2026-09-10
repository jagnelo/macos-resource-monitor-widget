import Foundation
import AppKit
import Darwin

/// Lightweight top-process sampler.
///
/// Uses `/bin/ps -Aceo pid,pcpu,rss,comm` every few seconds — no entitlements,
/// no Full Disk Access, negligible overhead. Precision is ± a few % which is
/// fine for a "Using Significant Energy"-style list.
public struct TopProcess: Identifiable, Hashable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var cpuPercent: Double
    public var rssBytes: UInt64
    public var name: String
}

/// Processes rolled up to their parent app (like Battery's app list):
/// helper processes inside `Foo.app` count toward Foo, matched by executable
/// path, falling back to name matching and then the bare process with its
/// file icon.
public struct TopApp: Identifiable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var icon: NSImage?
    public var cpuPercent: Double   // summed across the app's processes
    public var rssBytes: UInt64     // summed across the app's processes
    public var processCount: Int
}

@MainActor
@Observable
public final class ProcessMonitor {
    public internal(set) var topCPU: [TopProcess] = []
    public internal(set) var topMem: [TopProcess] = []
    public internal(set) var cpuApps: [TopApp] = []
    public internal(set) var memApps: [TopApp] = []
    public internal(set) var lastUpdated = Date.distantPast

    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 5.0) {
        stop()
        Task { await self.sample() }
        timer = scheduleCommonTimer(interval: interval, repeats: true) { [weak self] _ in
            Task { await self?.sample() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Battery's "Significant Energy" is private (CPU+GPU+disk+net+wakeups via
    /// powermetrics). We approximate per scope: CPU ≥ 20% total, footprint ≥
    /// 500 MB total, aggregated per app.
    public var significantCPUApps: [TopApp] { cpuApps.filter { $0.cpuPercent >= 20 } }
    public var significantMemApps: [TopApp] { memApps.filter { $0.rssBytes >= 500_000_000 } }

    func sample() async {
        let procs = await runPS()
        topCPU = Array(procs.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        topMem = Array(procs.sorted { $0.rssBytes > $1.rssBytes }.prefix(5))
        let apps = Self.aggregate(procs, runningApps: NSWorkspace.shared.runningApplications)
        cpuApps = Array(apps.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        memApps = Array(apps.sorted { $0.rssBytes > $1.rssBytes }.prefix(5))
        lastUpdated = Date()
    }

    // MARK: - App roll-up

    private static func aggregate(_ procs: [TopProcess], runningApps: [NSRunningApplication]) -> [TopApp] {
        struct Acc {
            var name: String
            var icon: NSImage?
            var cpu = 0.0
            var rss: UInt64 = 0
            var count = 0
        }
        var accs: [String: Acc] = [:]
        var order: [String] = []
        for p in procs {
            let path = pathForPid(p.pid)
            let key: String
            let name: String
            let icon: NSImage?
            if let path, let app = runningApps.first(where: { bundleContains($0, path: path) }) {
                key = "bundle:" + (app.bundleIdentifier ?? app.bundleURL?.absoluteString ?? path)
                name = app.localizedName ?? p.name
                icon = app.icon
            } else if let app = matchApp(named: p.name, in: runningApps) {
                key = "bundle:" + (app.bundleIdentifier ?? app.bundleURL?.absoluteString ?? p.name)
                name = app.localizedName ?? p.name
                icon = app.icon
            } else {
                key = "pid:\(p.pid)"
                name = p.name
                icon = path.map { NSWorkspace.shared.icon(forFile: $0) }
            }
            if accs[key] == nil {
                accs[key] = Acc(name: name, icon: icon)
                order.append(key)
            }
            accs[key]!.cpu += p.cpuPercent
            accs[key]!.rss += p.rssBytes
            accs[key]!.count += 1
        }
        return order.compactMap { k in
            guard let a = accs[k] else { return nil }
            return TopApp(key: k, name: a.name, icon: a.icon,
                          cpuPercent: a.cpu, rssBytes: a.rss, processCount: a.count)
        }
    }

    private static func bundleContains(_ app: NSRunningApplication, path: String) -> Bool {
        guard let b = app.bundleURL?.path else { return false }
        return path == b || path.hasPrefix(b + "/")
    }

    /// Catches "Google Chrome Helper" -> Google Chrome and similar when the
    /// helper lives outside the .app bundle. Longest app-name prefix wins.
    private static func matchApp(named procName: String, in apps: [NSRunningApplication]) -> NSRunningApplication? {
        let lower = procName.lowercased()
        var best: NSRunningApplication?
        var bestLen = 0
        for app in apps {
            guard let an = app.localizedName, !an.isEmpty else { continue }
            let a = an.lowercased()
            if lower == a || lower.hasPrefix(a + " ") || lower.hasPrefix(a + "(") || lower.hasPrefix(a + "-") {
                if a.count > bestLen { bestLen = a.count; best = app }
            }
        }
        return best
    }

    private static func pathForPid(_ pid: Int32) -> String? {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = buf.withUnsafeMutableBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            return base.withMemoryRebound(to: CChar.self, capacity: ptr.count) { cptr in
                proc_pidpath(pid, cptr, UInt32(ptr.count))
            }
        }
        guard n > 0 else { return nil }
        let end = buf.firstIndex(of: 0) ?? buf.endIndex
        let path = String(decoding: buf[..<end], as: UTF8.self)
        return path.isEmpty ? nil : path
    }

    // MARK: - ps sampling

    private func runPS() async -> [TopProcess] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/ps")
                task.arguments = ["-Aceo", "pid,pcpu,rss,comm"]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                } catch {
                    cont.resume(returning: [])
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                guard let text = String(data: data, encoding: .utf8) else {
                    cont.resume(returning: [])
                    return
                }
                var out: [TopProcess] = []
                out.reserveCapacity(256)
                for line in text.split(separator: "\n").dropFirst() { // skip header
                    // Columns: PID %CPU RSS COMM — COMM has no spaces from ps comm.
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    guard parts.count >= 4,
                          let pid = Int32(parts[0]),
                          let cpu = Double(parts[1]),
                          let rssKB = UInt64(parts[2]) else { continue }
                    let name = String(parts[3...].joined(separator: " "))
                    if name == "idle" || name.hasPrefix("(ps)") { continue }
                    out.append(TopProcess(
                        pid: pid,
                        cpuPercent: cpu,
                        rssBytes: rssKB * 1024,
                        name: (name as NSString).lastPathComponent
                    ))
                }
                cont.resume(returning: out)
            }
        }
    }
}
