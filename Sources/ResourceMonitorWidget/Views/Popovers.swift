import SwiftUI
import AppKit

extension Notification.Name {
    static let dismissWidgetMenu = Notification.Name("ResourceMonitorWidget.dismissWidgetMenu")
    static let panelContentHeight = Notification.Name("ResourceMonitorWidget.panelContentHeight")
}

struct PanelHeightReporter: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func reportPanelHeight() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: PanelHeightReporter.self, value: geo.size.height)
        })
        .onPreferenceChange(PanelHeightReporter.self) { height in
            NotificationCenter.default.post(name: .panelContentHeight, object: nil, userInfo: ["height": height])
        }
    }
}

// MARK: - Battery-widget popover visuals
//
// Content for a standard transient NSPopover anchored to the status item, so
// chrome, material and dismissal are AppKit's own. Typography follows the
// native Battery popover: 13pt bold title, 11pt secondary sublines and
// section labels, 13pt rows with 16pt app icons, hairline dividers between
// sections, rounded hover pills ending a few points from the popover edge.
// Sizing is native — the hosting controller reports its preferred content
// size, so the popover grows/shrinks with the content on its own.

struct PanelHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct PanelSparkline: View {
    let values: [Double]
    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = size.width * Double(i) / Double(max(values.count - 1, 1))
                let y = size.height * (1 - min(max(v, 0), 1))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(.secondary), lineWidth: 1.2)
        }
        .frame(height: 30)
    }
}

struct PanelSectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// Column count for the adaptive per-core grid: every core stays visible and
/// columns rebalance into even rows up to a fixed cap (10 cores → 5+5,
/// 12 → 6+6), so 4-core and 20-core machines both fill the width.
func popoverGridColumns(count: Int, maxColumns: Int = 8) -> Int {
    guard count > 0 else { return 1 }
    guard count > maxColumns else { return count }
    let rows = Int(ceil(Double(count) / Double(maxColumns)))
    return Int(ceil(Double(count) / Double(rows)))
}

/// Adaptive per-core grid: every core gets the same live meter icon the menu
/// bar widget uses, plus its load %.
struct PanelCoresGrid: View {
    let perCore: [Double]

    private var columns: Int { popoverGridColumns(count: perCore.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelSectionLabel(title: "Cores")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(Array(perCore.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 3) {
                        Image(nsImage: makeStatusImage(kind: .cpu, fraction: v, percentText: nil))
                        Text("\(Int((v * 100).rounded()))%")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("Core \(i)")
                }
            }
        }
    }
}

struct PanelTextRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct PanelAppRow: View {
    let icon: NSImage?
    let name: String
    let detail: String
    @State private var hovering = false

    var body: some View {
        Button(action: openActivityMonitor) {
            HStack(spacing: 8) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(hovering ? RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)) : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Stretch the hover pill past the content padding, so it ends a few
        // pt from the popover edge like the native Battery popover's rows.
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
    }

    private func openActivityMonitor() {
        // Clicks on custom menu-item views don't end menu tracking on their
        // own — dismiss first, then act.
        NotificationCenter.default.post(name: .dismissWidgetMenu, object: nil)
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}

/// Toggle row for the fallback launcher: same Battery-style hover pill as
/// PanelAppRow (8pt gray pill bleeding past the content padding to end near
/// the popover edge) — keep the two in sync. No checkmark: the launcher only
/// ever shows while every widget is hidden, so each row is a re-add action.
struct PanelToggleRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: {
            // Clicks on custom menu-item views don't end menu tracking on
            // their own — dismiss first, then act (same as PanelAppRow).
            NotificationCenter.default.post(name: .dismissWidgetMenu, object: nil)
            action()
        }) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(hovering ? RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)) : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
    }
}

/// Launcher panel: the same menu chrome, width, padding and hover pills as
/// the widget popovers — one re-add row per widget.
struct FallbackPopover: View {
    let rows: [(title: String, kind: MeterKind)]
    let onTap: (MeterKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                PanelToggleRow(title: row.title) { onTap(row.kind) }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 1)
        .frame(alignment: .leading)
    }
}

struct CPUPopover: View {
    let cpu: CPUMonitor
    let procs: ProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(title: "CPU",
                        subtitle: "\(Int((cpu.overall * 100).rounded()))% · \(ProcessInfo.processInfo.processorCount) cores")
            PanelSparkline(values: cpu.history.isEmpty ? [cpu.overall] : cpu.history)
            Divider()
            if !cpu.perCore.isEmpty {
                PanelCoresGrid(perCore: cpu.perCore)
                Divider()
            }
            VStack(alignment: .leading, spacing: 4) {
                PanelSectionLabel(title: "Using Significant CPU")
                if procs.significantCPUApps.isEmpty {
                    Text("No Apps Using Significant CPU")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(procs.significantCPUApps.prefix(5).enumerated()), id: \.offset) { _, app in
                        PanelAppRow(icon: app.icon, name: app.name, detail: String(format: "%.0f%%", app.cpuPercent))
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 1)
        .frame(width: 290, alignment: .leading)
        .reportPanelHeight()
    }
}

struct MemoryPopover: View {
    let mem: MemoryMonitor
    let procs: ProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(title: "Memory",
                        subtitle: "\(humanBytes(mem.snapshot.usedBytes, binary: true)) of \(humanBytes(mem.snapshot.totalBytes, binary: true)) used")
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                PanelTextRow(label: "Wired", value: humanBytes(mem.snapshot.wiredBytes, binary: true))
                PanelTextRow(label: "Compressed", value: humanBytes(mem.snapshot.compressedBytes, binary: true))
                PanelTextRow(label: "Swap used", value: mem.snapshot.swapUsedBytes > 0 ? humanBytes(mem.snapshot.swapUsedBytes, binary: true) : "None")
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                PanelSectionLabel(title: "Using Significant Memory")
                if procs.significantMemApps.isEmpty {
                    Text("No Apps Using Significant Memory")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(procs.significantMemApps.prefix(5).enumerated()), id: \.offset) { _, app in
                        PanelAppRow(icon: app.icon, name: app.name, detail: humanBytes(app.rssBytes, binary: true))
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 1)
        .frame(width: 290, alignment: .leading)
        .reportPanelHeight()
    }
}

struct DiskPopover: View {
    let disk: DiskMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(title: "Storage",
                        subtitle: "\(humanBytes(disk.snapshot.usedBytes)) of \(humanBytes(disk.snapshot.totalBytes)) used")
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                PanelTextRow(label: "Available", value: humanBytes(disk.snapshot.freeBytes))
                if disk.snapshot.purgeableBytes > 0 {
                    PanelTextRow(label: "Purgeable", value: humanBytes(disk.snapshot.purgeableBytes))
                }
            }
            if !disk.snapshot.volumes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    PanelSectionLabel(title: "Volumes")
                    ForEach(Array(disk.snapshot.volumes.prefix(5).enumerated()), id: \.offset) { _, v in
                        PanelTextRow(label: v.name, value: "\(humanBytes(v.total - v.free)) / \(humanBytes(v.total))")
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 1)
        .frame(width: 290, alignment: .leading)
        .reportPanelHeight()
    }
}
