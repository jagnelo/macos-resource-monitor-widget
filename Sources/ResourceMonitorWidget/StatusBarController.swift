import AppKit
import Foundation
import SwiftUI

/// Owns the three menu-bar widgets as classic NSStatusItems with
/// Battery-proportioned monochrome template icons (optional % drawn into the
/// image, left of the glyph).
///
/// Left-click presents the widget's content as a real `NSMenu` — the same
/// element third-party widgets like Docker use: no arrow, system chrome and
/// material, instant appearance, glued under the menu bar, and fully native
/// dismissal (menu tracking is exclusive by OS design, so clicking another
/// widget swaps popovers, Escape/⌘⌃⇧4 behave exactly like every other menu).
/// The whole popover content (header, sparkline, cores, app rows, settings)
/// is hosted as one custom menu-item view; rows and the settings link dismiss
/// the menu themselves before acting.
///
/// Right-click opens Battery's exact context menu: "Show Percentage"
/// (checkmark) and "Remove". Quit lives in Settings only.
@MainActor
final class StatusBarController: NSObject {
    /// Content width inside the menu; the menu adds its own system insets.
    private let menuContentWidth: CGFloat = 290
    /// Bottom edge of the menu-bar strip (bar height is 33pt on Tahoe).
    private let menuBarHeight: CGFloat = 33

    private let cpu: CPUMonitor
    private let mem: MemoryMonitor
    private let disk: DiskMonitor
    private let procs: ProcessMonitor

    private var cpuItem: NSStatusItem!
    private var memItem: NSStatusItem!
    private var diskItem: NSStatusItem!
    /// Shown only when all three widgets are hidden: the re-entry point.
    private var fallbackItem: NSStatusItem!
    var fallbackDismissedAt: Date?
    /// Test hook: whether the fallback launcher is currently visible.
    var isFallbackShown: Bool { fallbackItem.isVisible }

    private var refreshTimer: Timer?
    /// Whether samplers are currently running. With every widget removed the
    /// agent idles without sampling; reopening any widget restarts them.
    var monitoringActive = false
    private var defaultsToken: NSObjectProtocol?
    private var dismissToken: NSObjectProtocol?
    private var heightToken: NSObjectProtocol?
    private var stripMonitor: Any?
    var openMenu: NSMenu?
    private var openKind: MeterKind?

    /// Hosting views are expensive to build on first open; cache one per
    /// widget and pre-warm after launch so every open is instant.
    private var menuHosts: [MeterKind: NSHostingView<AnyView>] = [:]

    /// The click that dismissed a menu can still deliver its button action
    /// right after (toggle-off). A dismissal this fresh counts as already
    /// handled — never close-then-reopen.
    private var justClosed: (kind: MeterKind, at: Date)?

    /// Toggle actions arriving this soon after a dismissal belong to the click
    /// that dismissed (toggle-off double delivery), not to a new click.
    /// Measured: genuine duplicates land within ~10-50ms of close; the
    /// fastest legitimate human re-click observed is 376ms — 150ms splits
    /// the difference with margin on both sides.
    static let toggleFreshnessWindow: TimeInterval = 0.15

    /// Pure freshness check for the toggle guard. Covered by WidgetSwitchTests.
    static func isFreshDismissal(closedKind: MeterKind, closedAt: Date, kind: MeterKind, now: Date) -> Bool {
        guard kind == closedKind else { return false }
        return now.timeIntervalSince(closedAt) < toggleFreshnessWindow
    }

    init(cpu: CPUMonitor, mem: MemoryMonitor, disk: DiskMonitor, procs: ProcessMonitor) {
        self.cpu = cpu
        self.mem = mem
        self.disk = disk
        self.procs = procs
        super.init()
    }

    func start() {
        cpuItem = makeItem(kind: .cpu)
        memItem = makeItem(kind: .memory)
        diskItem = makeItem(kind: .disk)
        fallbackItem = makeFallbackItem()
        defaultsToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                UserDefaults.standard.synchronize()
                self?.applyVisibility()
                self?.refresh()
            }
        }
        dismissToken = NotificationCenter.default.addObserver(
            forName: .dismissWidgetMenu, object: nil, queue: .main
        ) { [weak self] _ in
            // Without animation: row taps must feel as instant as native
            // menu-item selection.
            Task { @MainActor [weak self] in self?.openMenu?.cancelTrackingWithoutAnimation() }
        }
        heightToken = NotificationCenter.default.addObserver(
            forName: .panelContentHeight, object: nil, queue: .main
        ) { [weak self] note in
            let height = note.userInfo?["height"] as? CGFloat
            Task { @MainActor [weak self] in
                guard let self, let height, let kind = self.openKind else { return }
                self.refitOpenMenu(kind: kind, height: height)
            }
        }
        stripMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stripMouseDown() }
        }
        // Samplers start only while at least one widget is visible (gated in
        // applyVisibility); a fully-removed trio idles silently.
        applyVisibility()
        refresh()
        // Pre-warm menu content off the critical path so the first open of
        // each widget is as instant as later ones.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for kind in [MeterKind.cpu, .memory, .disk] { _ = self.menuHost(for: kind) }
        }
    }

    // MARK: - Prefs

    private func showKey(for kind: MeterKind) -> String {
        switch kind {
        case .cpu: return "showCPU"
        case .memory: return "showMEM"
        case .disk: return "showDisk"
        }
    }

    private func pctKey(for kind: MeterKind) -> String {
        switch kind {
        case .cpu: return "showCPUPct"
        case .memory: return "showMEMPct"
        case .disk: return "showDiskPct"
        }
    }

    /// Reads through to cfprefsd instead of the in-process cache, so external
    /// writes (e.g. `defaults write`, MDM) apply too.
    private func storedBool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let v = CFPreferencesCopyAppValue(key as CFString, kCFPreferencesCurrentApplication) else {
            return defaultValue
        }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return defaultValue
    }

    private func applyVisibility() {
        cpuItem.isVisible = storedBool("showCPU", default: true)
        memItem.isVisible = storedBool("showMEM", default: true)
        diskItem.isVisible = storedBool("showDisk", default: true)
        fallbackItem.isVisible = Self.fallbackVisible(
            cpuVisible: cpuItem.isVisible, memVisible: memItem.isVisible, diskVisible: diskItem.isVisible)
        setMonitoring(cpuItem.isVisible || memItem.isVisible || diskItem.isVisible)
    }

    /// Fallback launcher visibility: shown if and only if no widget is
    /// visible. Pure rule; covered by FallbackWidgetTests.
    static func fallbackVisible(cpuVisible: Bool, memVisible: Bool, diskVisible: Bool) -> Bool {
        !(cpuVisible || memVisible || diskVisible)
    }

    /// Starts samplers on the visible→any transition, stops them when the
    /// last widget is removed. Idempotent: repeated calls with the same state
    /// never restart running samplers (which would re-prime CPU deltas).
    /// Covered by MonitorTests.
    private func setMonitoring(_ on: Bool) {
        guard on != monitoringActive else { return }
        monitoringActive = on
        guard on else {
            cpu.stop(); mem.stop(); disk.stop(); procs.stop()
            refreshTimer?.invalidate(); refreshTimer = nil
            return
        }
        // Fixed cadence: CPU/RAM/apps every 5s, storage every 15s.
        cpu.start(interval: 5.0)
        mem.start(interval: 5.0)
        disk.start(interval: 15.0)
        procs.start(interval: 5.0)
        refreshTimer?.invalidate()
        refreshTimer = scheduleCommonTimer(interval: 5.0) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyVisibility()
                self?.refresh()
            }
        }
    }

    /// Reopening the app with everything hidden restores all widgets — the
    /// only re-entry path besides System Settings. Covered by MonitorTests.
    func restoreAllWidgets() {
        UserDefaults.standard.set(true, forKey: showKey(for: .cpu))
        UserDefaults.standard.set(true, forKey: showKey(for: .memory))
        UserDefaults.standard.set(true, forKey: showKey(for: .disk))
        UserDefaults.standard.synchronize()
        applyVisibility()
    }

    // MARK: - Icon content

    private func refresh() {
        setContent(item: cpuItem, kind: .cpu, name: "CPU",
                   fraction: cpu.overall, showPct: storedBool("showCPUPct", default: false))
        setContent(item: memItem, kind: .memory, name: "Memory",
                   fraction: mem.snapshot.pressure, showPct: storedBool("showMEMPct", default: false))
        setContent(item: diskItem, kind: .disk, name: "Storage",
                   fraction: disk.snapshot.fraction, showPct: storedBool("showDiskPct", default: false))
    }

    private func setContent(item: NSStatusItem, kind: MeterKind, name: String, fraction: Double, showPct: Bool) {
        guard let button = item.button else { return }
        let clamped = min(max(fraction, 0), 1)
        let pct = Int((clamped * 100).rounded())
        let label = "\(name) \(pct)%"
        button.image = makeStatusImage(kind: kind, fraction: clamped,
                                       percentText: showPct ? "\(pct)%" : nil)
        button.title = ""
        button.toolTip = label
        button.accessibilitySetOverrideValue(label, forAttribute: NSAccessibility.Attribute(rawValue: "AXTitle"))
    }

    // MARK: - Items & clicks

    private func makeItem(kind: MeterKind) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.tag = kind.rawValue
            button.target = self
            button.action = #selector(toggle(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageRight
        }
        return item
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        guard let kind = MeterKind(rawValue: sender.tag),
              let type = NSApp.currentEvent?.type else { return }
        if type == .rightMouseUp {
            // Yield any open content menu first: a right-click explicitly
            // asks for this widget's context menu, never the content menu
            // an auto-open may just have shown.
            if openMenu != nil {
                if let open = openKind { setWidgetHighlight(false, for: open) }
                openMenu?.cancelTrackingWithoutAnimation()
                openMenu = nil
                openKind = nil
            }
            popUp(contextMenu(for: kind), from: sender)
            return
        }
        if let just = justClosed,
           Self.isFreshDismissal(closedKind: just.kind, closedAt: just.at, kind: kind, now: Date()) {
            justClosed = nil
            return
        }
        presentMenu(contentMenu(for: kind), kind: kind)
    }

    // MARK: - Fallback launcher

    /// Idle gauge shown only when all three widgets are hidden. Gauge-only —
    /// no live value — so it reads as off until a widget is re-enabled.
    private func makeFallbackItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.tag = 99
            button.target = self
            button.action = #selector(fallbackToggle(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.image = makeFallbackImage()
            button.toolTip = "Resource Monitor"
        }
        return item
    }

    @objc private func fallbackToggle(_ sender: NSStatusBarButton) {
        // Docker-style: left-click and right-click open the same menu.
        // The click type only decides compatibility, never the content.
        guard NSApp.currentEvent?.type != nil else { return }
        if shouldSuppressFallbackToggle() { return }
        presentFallbackMenu(fallbackSelectorMenu())
    }

    /// Consume-once suppression for fallback toggle doubles: a click that
    /// dismissed a fallback menu can re-deliver its action right after; it
    /// must stay closed. Same freshness window as widget toggles.
    /// Covered by FallbackWidgetTests.
    func shouldSuppressFallbackToggle(now: Date = Date()) -> Bool {
        guard let at = fallbackDismissedAt else { return false }
        fallbackDismissedAt = nil
        return now.timeIntervalSince(at) < StatusBarController.toggleFreshnessWindow
    }

    /// Widget checklist shown on any click when no widgets are visible.
    /// Hosted SwiftUI like the widget panels — same menu chrome and the same
    /// Battery-style hover pills — deliberately not the vibrantDark
    /// right-click context menu. Covered by FallbackWidgetTests.
    func fallbackSelectorMenu() -> NSMenu {
        let root = NSHostingView(rootView: FallbackPopover(rows: fallbackRows()) { [weak self] kind in
            self?.enableWidget(kind)
        })
        // Natural content width (a short checklist, not a 290pt panel).
        root.setFrameSize(NSSize(width: root.fittingSize.width, height: max(root.fittingSize.height, 60)))
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem()
        item.view = root
        menu.addItem(item)
        return menu
    }

    /// Row data driving the fallback panel. Covered by FallbackWidgetTests.
    func fallbackRows() -> [(title: String, kind: MeterKind)] {
        [MeterKind.cpu, .memory, .disk].map { (title: widgetTitle($0), kind: $0) }
    }

    /// Re-add a widget from the fallback launcher. Covered by FallbackWidgetTests.
    func enableWidget(_ kind: MeterKind) {
        UserDefaults.standard.set(true, forKey: showKey(for: kind))
        applyVisibility()
    }

    /// One checkmark row per widget, reflecting live visibility prefs.
    /// Shared by every Widgets submenu and the fallback selector menu.
    func widgetToggleItem(for kind: MeterKind) -> NSMenuItem {
        let item = NSMenuItem(title: widgetTitle(kind), action: #selector(toggleWidget(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = kind.rawValue
        item.state = storedBool(showKey(for: kind), default: true) ? .on : .off
        return item
    }

    /// The Widgets submenu content shared by all context menus.
    func widgetsSubmenu() -> NSMenu {
        let sub = NSMenu()
        for kind in [MeterKind.cpu, .memory, .disk] {
            sub.addItem(widgetToggleItem(for: kind))
        }
        return sub
    }

    /// Presents a fallback menu glued under the menu bar at the click x,
    /// mirroring presentMenu's anchoring without widget state (the launcher
    /// has no popover, highlight, or switch target).
    private func presentFallbackMenu(_ menu: NSMenu) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        // Same Battery left-alignment as the widget panels: anchor to the
        // launcher's left edge, clamping by this menu's own narrow width.
        let width = menu.items.first?.view?.frame.width ?? 316
        let x = Self.anchorX(iconLeft: stripItemLeftEdge(at: mouse.x) ?? mouse.x,
                             visibleMinX: visible.minX, visibleMaxX: visible.maxX,
                             menuWidth: width)
        let barBottom = screen.frame.maxY - menuBarHeight
        let helper = NSPanel(contentRect: NSRect(x: x, y: barBottom, width: 1, height: 1),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        helper.isOpaque = false
        helper.backgroundColor = .clear
        helper.hasShadow = false
        helper.ignoresMouseEvents = true
        helper.level = .popUpMenu
        helper.isReleasedWhenClosed = false
        helper.orderFrontRegardless()
        menu.popUp(positioning: nil, at: NSPoint(x: 0.5, y: 1.0), in: helper.contentView!)
        helper.orderOut(nil)
        fallbackDismissedAt = Date()
    }

    // MARK: - Menus

    func showPanelTest(kind: MeterKind) {
        // Diagnostics hook: build the menu to verify content construction.
        _ = contentMenu(for: kind)
    }

    /// Cached hosting view per widget (see `menuHosts`). Covered by MenuStructureTests.
    func menuHost(for kind: MeterKind) -> NSHostingView<AnyView> {
        if let host = menuHosts[kind] { return host }
        let root: NSHostingView<AnyView>
        switch kind {
        case .cpu:
            root = NSHostingView(rootView: AnyView(CPUPopover(cpu: cpu, procs: procs)))
        case .memory:
            root = NSHostingView(rootView: AnyView(MemoryPopover(mem: mem, procs: procs)))
        case .disk:
            root = NSHostingView(rootView: AnyView(DiskPopover(disk: disk)))
        }
        menuHosts[kind] = root
        return root
    }

    private func contentMenu(for kind: MeterKind) -> NSMenu {
        let root = menuHost(for: kind)
        root.removeFromSuperview()
        root.setFrameSize(NSSize(width: menuContentWidth, height: max(root.fittingSize.height, 60)))
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem()
        item.view = root
        menu.addItem(item)
        return menu
    }

    /// Resize a live menu's hosting view as its content changes (apps appear
    /// or disappear in "Using Significant …"), keeping the menu top glued.
    /// Covered by MenuStructureTests.
    func refitOpenMenu(kind: MeterKind, height: CGFloat) {
        guard height > 1 else { return }
        let host = menuHost(for: kind)
        guard abs(host.frame.height - height) > 0.5 else { return }
        host.setFrameSize(NSSize(width: host.frame.width, height: height))
        openMenu?.update()
    }

    /// Highlight cleanup at tracking end (deselect timing). Covered by
    /// MenuStructureTests.
    func trackingEnded(for kind: MeterKind) {
        setWidgetHighlight(false, for: kind)
    }

    /// Pure switch decision: open the targeted widget only when it differs
    /// from the just-closed one. Covered by WidgetSwitchTests.
    func autoOpenTarget(closed: MeterKind, mouseKind: MeterKind?, rightDown: Bool = false) -> MeterKind? {
        // A held right button means a context menu was requested, never
        // content — opening content here would flash it under the context menu.
        guard !rightDown else { return nil }
        guard let mouseKind, mouseKind != closed else { return nil }
        return mouseKind
    }

    /// Keeps the pressed look on whichever widget's menu is open (Battery
    /// behavior): highlight on open, release on close, so a switch hands the
    /// highlight from the old widget to the new one. Covered by WidgetSwitchTests.
    func setWidgetHighlight(_ highlight: Bool, for kind: MeterKind) {
        let item: NSStatusItem?
        switch kind {
        case .cpu: item = cpuItem
        case .memory: item = memItem
        case .disk: item = diskItem
        }
        item?.button?.highlight(highlight)
    }

    /// Test hook: pressed state of a widget's button.
    func isWidgetHighlighted(_ kind: MeterKind) -> Bool {
        let item: NSStatusItem?
        switch kind {
        case .cpu: item = cpuItem
        case .memory: item = memItem
        case .disk: item = diskItem
        }
        return item?.button?.isHighlighted ?? false
    }

    /// Left edge of the menu-bar item under the click (Control Centre mirrors
    /// every item, including ours, as a real strip window). Falls back to the
    /// click position when no item matches, e.g. diagnostics without a click.
    private func stripItemLeftEdge(at mouseX: CGFloat) -> CGFloat? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for w in list {
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 25 else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let width = b["Width"], let height = b["Height"] else { continue }
            guard height >= 20 && height <= 40 else { continue }
            if mouseX >= x - 4 && mouseX <= x + width + 4 { return x }
        }
        return nil
    }

    /// Left-align the menu with the clicked icon like Battery does, keeping
    /// it on screen. Pure logic; covered by MenuStructureTests.
    static func anchorX(iconLeft: CGFloat, visibleMinX: CGFloat, visibleMaxX: CGFloat, menuWidth: CGFloat = 316) -> CGFloat {
        min(max(iconLeft, visibleMinX + 6), visibleMaxX - menuWidth)
    }

    /// Gap between the menu bar's bottom edge and the context menu's top edge,
    /// matching the Battery reference. Covered by MenuStructureTests.
    static let contextMenuTopGap: CGFloat = 10

    /// Presents a context menu from the status button itself — the long-proven
    /// path: AppKit resolves the Tahoe proxy to the real icon internally, so
    /// the menu sizes and positions natively with no scroll state.
    private func popUp(_ menu: NSMenu, from button: NSStatusBarButton) {
        button.highlight(true)
        menu.popUp(positioning: nil,
                   at: NSPoint(x: button.bounds.midX, y: button.bounds.minY - Self.contextMenuTopGap),
                   in: button)
        button.highlight(false)
    }

    /// Presents a menu glued under the menu bar, left-aligned with the
    /// clicked icon like Battery. On Tahoe the status button lives in a
    /// degenerate offscreen proxy, so anchor from a 1×1 helper window at the
    /// icon's left edge instead — the system then positions, tracks and
    /// dismisses the menu natively.
    private func presentMenu(_ menu: NSMenu, kind: MeterKind) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let x = Self.anchorX(iconLeft: stripItemLeftEdge(at: mouse.x) ?? mouse.x,
                             visibleMinX: visible.minX, visibleMaxX: visible.maxX)
        let barBottom = screen.frame.maxY - menuBarHeight
        let helper = NSPanel(contentRect: NSRect(x: x, y: barBottom, width: 1, height: 1),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        helper.isOpaque = false
        helper.backgroundColor = .clear
        helper.hasShadow = false
        helper.ignoresMouseEvents = true
        helper.level = .popUpMenu
        helper.isReleasedWhenClosed = false
        helper.orderFrontRegardless()
        openMenu = menu
        openKind = kind
        // Deselect the instant tracking ends (fade start), not after the
        // fade completes — matches native deselect timing.
        let trackingToken = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: menu, queue: .main
        ) { [weak self, kind] _ in
            Task { @MainActor [weak self] in self?.trackingEnded(for: kind) }
        }
        defer { NotificationCenter.default.removeObserver(trackingToken) }
        setWidgetHighlight(true, for: kind)
        menu.popUp(positioning: nil, at: NSPoint(x: 0.5, y: 1.0), in: helper.contentView!)
        setWidgetHighlight(false, for: kind)
        openMenu = nil
        openKind = nil
        helper.orderOut(nil)
        justClosed = (kind, Date())
        // The click that dismissed this menu may have landed on another of
        // our widgets — the system swallows that click instead of delivering
        // a fresh action, so open the targeted widget directly. One click
        // switches widgets; a second click is never needed.
        if let target = autoOpenTarget(closed: kind, mouseKind: widgetKind(at: NSEvent.mouseLocation),
                                             rightDown: NSEvent.pressedMouseButtons & (1 << 1) != 0) {
            justClosed = nil
            presentMenu(contentMenu(for: target), kind: target)
        }
    }

    /// Hit-test a strip point against our three status-item buttons (Tahoe
    /// hosts them in-process with real strip frames — no permissions needed).
    private func widgetKind(at loc: NSPoint) -> MeterKind? {
        let items: [(MeterKind, NSStatusItem?)] = [(.cpu, cpuItem), (.memory, memItem), (.disk, diskItem)]
        var best: (kind: MeterKind, distance: CGFloat)?
        for (kind, item) in items {
            guard let button = item?.button, let window = button.window else { continue }
            let frame = window.frame.insetBy(dx: -4, dy: -8)
            guard frame.contains(loc) else { continue }
            let distance = abs(loc.x - frame.midX)
            if best == nil || distance < best!.distance { best = (kind, distance) }
        }
        return best?.kind
    }

    // MARK: - Menu-bar strip dismissal
    //
    // Menu tracking already handles outside clicks, but clicks delivered to
    // status-bar items (any process's — including other apps' widgets) need
    // an instant, animation-free dismissal so switching feels instant.

    private func stripMouseDown() {
        dismissOpenMenuForStripClick(at: NSEvent.mouseLocation)
    }

    /// Ends open-menu tracking instantly (no fade) for menu-bar clicks, so a
    /// switch opens the new widget at once. Returns whether it acted.
    /// Non-strip clicks keep the native fade to match Battery. Skipped during
    /// screen capture, like all dismissal paths.
    /// Covered by MenuStructureTests.
    @discardableResult
    func dismissOpenMenuForStripClick(at loc: NSPoint) -> Bool {
        guard openMenu != nil else { return false }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }),
              loc.y >= screen.frame.maxY - menuBarHeight else { return false }
        if Self.isCaptureUIOnScreen() { return false }
        openMenu?.cancelTrackingWithoutAnimation()
        return true
    }

    /// The screen-capture UI (⌘⇧4/⌘⌃⇧4 crosshair) runs its own process and
    /// consumes clicks without activating anything; its windows on screen
    /// mark capture mode. Permission-free.
    static func isCaptureUIOnScreen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { ($0[kCGWindowOwnerName as String] as? String) == "screencaptureui" }
    }

}

// MARK: - Right-click: Battery's exact context menu

extension StatusBarController {
    func contextMenu(for kind: MeterKind) -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .vibrantDark)

        let pct = NSMenuItem(title: "Show Percentage", action: #selector(togglePercentage(_:)), keyEquivalent: "")
        pct.target = self
        pct.representedObject = kind.rawValue
        pct.state = storedBool(pctKey(for: kind), default: false) ? .on : .off
        menu.addItem(pct)

        let widgets = NSMenuItem(title: "Widgets", action: nil, keyEquivalent: "")
        widgets.submenu = widgetsSubmenu()
        menu.addItem(widgets)

        menu.addItem(.separator())

        let remove = NSMenuItem(title: "Remove", action: #selector(removeWidget(_:)), keyEquivalent: "")
        remove.target = self
        remove.representedObject = kind.rawValue
        menu.addItem(remove)

        return menu
    }

    @objc private func togglePercentage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let kind = MeterKind(rawValue: raw) else { return }
        let key = pctKey(for: kind)
        UserDefaults.standard.set(!storedBool(key, default: false), forKey: key)
        refresh()
    }

    @objc private func removeWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let kind = MeterKind(rawValue: raw) else { return }
        // Re-add any time from another widget's Widgets submenu (or by
        // relaunching the app, which restores all widgets when hidden).
        UserDefaults.standard.set(false, forKey: showKey(for: kind))
        applyVisibility()
    }

    private func widgetTitle(_ kind: MeterKind) -> String {
        switch kind {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Storage"
        }
    }

    @objc func toggleWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let kind = MeterKind(rawValue: raw) else { return }
        let key = showKey(for: kind)
        UserDefaults.standard.set(!storedBool(key, default: true), forKey: key)
        applyVisibility()
    }

}
