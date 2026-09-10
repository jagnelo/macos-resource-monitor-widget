import ServiceManagement
import SwiftUI
import AppKit

/// Menu-bar-only background agent: three NSStatusItem widgets sharing one
/// codebase. No Dock icon, no windows, no Quit — like the Battery widget, it
/// runs while logged in and is managed entirely from the widgets themselves.
/// See StatusBarController for menu-bar behavior; popovers live in Popovers.swift.
@main
struct ResourceMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // No scenes by design: this agent has no windows. (SwiftUI requires at
    // least one scene, so an empty Settings scene stands in; it is never
    // shown — there is no menu bar or key path that can open it.)
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let cpu = CPUMonitor()
    let mem = MemoryMonitor()
    let disk = DiskMonitor()
    let procs = ProcessMonitor()
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy may own the menu bar — a second launch (e.g. an old
        // build in /Applications plus a dev build) would double every icon.
        if let bid = Bundle.main.bundleIdentifier {
            let me = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .filter { $0.processIdentifier != me }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }
        UserDefaults.standard.register(defaults: [
            "showCPU": true, "showMEM": true, "showDisk": true,
            "showCPUPct": false, "showMEMPct": false, "showDiskPct": false,
        ])
        // Battery-style lifecycle: always launch at login unless the user
        // removes it in System Settings → General → Login Items (the only
        // opt-out macOS offers third-party agents — there is intentionally
        // no in-app toggle). Failures (e.g. unsigned dev builds) are silent.
        // A standard packaged install only needs a first launch after the
        // drag-to-Applications copy for this to take effect.
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        // Sweep legacy visibility keys written by the MenuBarExtra era's
        // scene-managed items — they could leave a widget permanently hidden.
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC Item-0")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC Item-1")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC Item-2")
        let controller = StatusBarController(cpu: cpu, mem: mem, disk: disk, procs: procs)
        self.controller = controller
        controller.start()
        // Diagnostics hook: `--show-panel=cpu|memory|disk` opens that panel
        // on launch so panel creation is verifiable without clicking.
        for arg in CommandLine.arguments where arg.hasPrefix("--show-panel=") {
            let name = String(arg.dropFirst("--show-panel=".count))
            let kind: MeterKind?
            switch name {
            case "cpu": kind = .cpu
            case "memory": kind = .memory
            case "disk": kind = .disk
            default: kind = nil
            }
            if let kind {
                controller.showPanelTest(kind: kind)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    /// Reopening the app (Spotlight / Finder) with all widgets removed
    /// restores them — the only re-entry path besides System Settings, now
    /// that there is no Settings window and no Quit.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.restoreAllWidgets()
        return true
    }

}
