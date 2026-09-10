import SwiftUI
import AppKit

/// Menu-bar-only app: three NSStatusItem icons sharing one codebase.
/// See StatusBarController for menu-bar behavior; popovers live in Popovers.swift.
@main
struct ResourceMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
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
        // Sweep legacy visibility keys written by the MenuBarExtra era's
        // scene-managed items — they could leave a widget permanently hidden.
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC Item-0")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC Item-1")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC Item-2")
        let controller = StatusBarController(cpu: cpu, mem: mem, disk: disk, procs: procs)
        self.controller = controller
        controller.start()
        // Diagnostics hook: `--show-settings` opens Settings on launch so the
        // window path is verifiable without clicking.
        if CommandLine.arguments.contains("--show-settings") {
            showSettings()
        }
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

    func showSettings() {
        SettingsWindowController.shared.show()
    }

    /// Reopening the app (Spotlight / Finder) while all widgets are removed
    /// offers Settings so widgets can be re-added.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
}

/// Owns the Settings window directly. (SwiftUI's showSettingsWindow: action
/// needs a main-menu responder chain, which menu-bar-only apps don't have,
/// so "…Settings…" menu entries route here instead — guaranteed to open.)
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: host)
            w.title = "ResourceMonitorWidget Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            // Deterministic size: an auto-sized hosting view can start at
            // zero and leave users staring at nothing.
            w.setContentSize(NSSize(width: 340, height: 400))
            w.center()
            // Floating + activate: must land visibly in front, never buried.
            w.level = .floating
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
