# Resource Monitor Widget (macOS menu bar)

Battery-widget-style CPU / Memory / Storage monitors for the macOS menu bar.
Three separate icons sharing one codebase — monochrome outline + progressive
fill in compact battery proportions (18px glyphs), icons only by default exactly
like Battery without its %; per-widget % (11pt menu-bar typeface, left of the
glyph) via right-click. Left-click opens a Battery-structured menu — header
visual, stats, per-core visual, "Using Significant …" apps (clicking one
opens Activity Monitor, like Battery), settings entry; all background,
separators, hover, margins, and dismissal rendered natively by AppKit.
Right-click opens Battery's exact context menu. Each widget is ~52pt with % on, matching
Battery's own spec.

## Run it

```sh
./build-app.sh            # debug build -> Resource Monitor.app
open "Resource Monitor.app"

./build-app.sh --release  # optimized build for daily use
```

Or open the folder in Xcode (File > Open > this folder) and press Run —
`Package.swift` targets macOS 14+ and Xcode picks up the scheme automatically.

## Tests

```sh
swift test                                   # 44 tests: logic + live-sampler
                                             # invariants + visual snapshots
RMW_RECORD=1 swift test --filter SnapshotTests   # re-record reference images
                                                 # after intentional UI changes
```

`SnapshotTests` renders every popover with fixed fixtures in light and dark
mode and diffs against `Tests/ResourceMonitorWidgetTests/ReferenceImages/`
(>0.5% differing pixels fails). Each run also writes its actuals plus a
side-by-side review page to `Tests/SnapshotResults/gallery.html` (ignored by
git). References are recorded on this machine — re-record them here if fonts
or rendering change, never copy them from another Mac.

## Menu-bar behavior (mirrors Battery)

- **Left-click** → info menu: header + sparkline (CPU), wired/compressed/swap
  (Memory), volumes (Storage), "Using Significant CPU/Memory" app list with
  app icons.
- **Right-click** → context menu: ✓ **Show Percentage**, a **Widgets** submenu
  to show/hide each widget (identical in every widget's menu), separator,
  **Remove**. There is no Settings window and no Quit — like Battery, the
  agent simply runs while logged in (launch registration is automatic; the
  only opt-out is System Settings → General → Login Items).
- Removed widgets come back from any visible widget's **Widgets** submenu,
  or by relaunching the app, which restores all widgets when everything is
  hidden.

## If an icon is missing

Tahoe manages the menu bar through Control Center and can hide third-party
icons without telling the app:

1. System Settings → Menu Bar → **Allow in the Menu Bar** → enable this app
   (this is the OS-level widget selector — third-party apps cannot inject
   their own entries anywhere else in System Settings).
2. Make room: on notch Macs the usable strip starts right of the notch
   (x=825 on a 13" Air at 1470pt). This trio is sized to fit right of it
   (~52pt per widget with % on), but a crowded bar still parks extras behind
   the notch — the single biggest space saver is turning Apple's Battery %
   off. ⌘-drag icons to reorder.
3. In-app fallback: any visible widget's right-click menu → **Widgets** submenu
   (same toggles).

Nuclear reset (clears stale Control Center registrations and prefs):

```sh
pkill -x ResourceMonitorWidget
defaults delete com.jagnelo.resourcemonitorwidget
open "Resource Monitor.app"
```

## How it maps to the Battery widget

| Battery | This app |
|---|---|
| Monochrome icon, system font, % left | Template `NSImage`s (auto light/dark), 11pt menu-bar typeface, `%` left via `imageRight` |
| Compact glyph | 18×13 flat 2D icons sharing one Battery-matched language (10pt art, 1.2 stroke): CPU = pinned chip, Memory = toothed stick, Storage = wireframe tank filling like a liquid level |
| Click → summary popover | Real `NSMenu` per metric (system chrome, no arrow, instant, native exclusive dismissal; stays open during ⌘⌃⇧4 captures) |
| CPU popover | Overall % + history sparkline + per-core grid. CPU values only |
| Memory popover | Used/total + wired/compressed/swap. Byte values only |
| Storage popover | Used/total + available/purgeable + volumes (no auto top-files: needs a full-disk scan + Full Disk Access prompt) |
| "Using Significant Energy" | "Using Significant CPU" (≥ 20%) / "Using Significant Memory" (≥ 500 MB), per app with icons |
| "Show Percentage" / "Remove" menu | Same, per widget, on right-click |

## Implementation notes

- Classic `NSStatusItem`s, not `MenuBarExtra` — that's what gives
  system-font %, correct light/dark tinting, right-click menus, and exclusive
  popovers.
- Metrics: `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` deltas (CPU),
  `host_statistics64(HOST_VM_INFO64)` + `hw.memsize` + `vm.swapusage` (RAM),
  `volumeTotalCapacity` / `volumeAvailableCapacity` (disk). All public API, no entitlements.
- Top apps: `/bin/ps` sampling + `proc_pidpath` roll-up to parent `.app`
  (fallback: name matching, then bare process with its file icon).
- Fixed cadence: CPU/RAM/apps every 5s, storage every 15s, icon refresh 5s.

## Before daily-driving / distributing

1. The bundle ID is `com.jagnelo.resourcemonitorwidget` (set as `CFBundleIdentifier`
   in `build-app.sh`). Changing it orphans prefs (they live under the old ID)
   and the old Login Items entry — remove the stale entry by hand.
2. Open at Login uses `SMAppService` — needs a signed bundle; ad-hoc sign (done
   by the script) is fine locally, Developer ID + notarization for sharing.
3. No sandbox blockers; no Full Disk Access requested on purpose.

## License

MIT — see [LICENSE](LICENSE).
