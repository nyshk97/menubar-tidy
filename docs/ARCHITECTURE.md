# Architecture

A map of the major components of **MenuBar Tidy**, a personal fork of
[thaw-app/Thaw](https://github.com/thaw-app/Thaw) cut down to five features.
This is not an API reference. For what was removed and why, see
[INVESTIGATION.md](../INVESTIGATION.md); for how to check the app works, see
[VERIFY.md](../VERIFY.md).

## What it does

Native macOS menu bar manager (Swift / AppKit / SwiftUI), local-only, no
accounts and no network surface at all:

1. Hides menu bar items by pushing them off the bar with an invisible
   `NSStatusItem` divider
2. Reveals the hidden items in a separate floating bar when empty menu bar
   space is clicked
3. Forwards a click on that bar to the real menu bar item
4. Keeps one status icon always visible
5. Persists the divider position

## Repository layout

| Path | Role |
| --- | --- |
| `Thaw/` | Main application target (menu bar logic, layout editor, events, permissions) |
| `Shared/` | Code shared with the helper process (CGS bridging, `WindowInfo`, diagnostic logging) |
| `MenuBarItemService/` | XPC helper that resolves the owning process of a menu bar item |
| `ThawTests/` | swift-testing suite |
| `docs/` | This file and [HIDDEN_FLAGS.md](HIDDEN_FLAGS.md) |
| `scripts/` | `list-menu-bar-items.swift` (see VERIFY.md) and the SwiftLint input list generator |

Dependencies are declared via SwiftPM and locked in
`Thaw.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
(AXSwift, CompactSlider, LaunchAtLogin-Modern, swift-algorithms,
swift-async-algorithms, swift-collections, swift-subprocess).

## Runtime components

```text
┌─────────────────────────────────────────────────────────────┐
│                     MenuBar Tidy.app                        │
│  AppDelegate / AppState                                     │
│  ├── MenuBar/ItemManager   status item enumeration + moves  │
│  ├── MenuBar/ControlItem   the dividers and the app's icon  │
│  ├── MenuBar/IceBar        the floating "Thaw Bar" panel    │
│  ├── MenuBar/LayoutBar     the drag-to-arrange editor       │
│  ├── Events / HID          empty-space click detection      │
│  └── Permissions           Accessibility / Screen Recording │
│                         │ XPC                               │
│                         ▼                                   │
│              MenuBarItemService.xpc                         │
│              (source PID cache / listener)                  │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
              macOS WindowServer / Accessibility /
              private menu-bar APIs (SkyLight)
```

### Main app (`Thaw/`)

- **MenuBar:** enumerates and moves status items, maintains the hidden and
  always-hidden sections, reconciles layout, and drives the Thaw Bar.
- **Events / HID:** detects clicks on empty menu bar space, which is the only
  reveal gesture this fork keeps.
- **Settings:** UserDefaults-backed configuration and profiles. The settings
  window is the layout editor and nothing else; every other value is a
  hardcoded default.
- **Permissions:** walks the user through the Accessibility (required) and
  Screen Recording (optional) TCC prompts.

### `MenuBarItemService` (XPC)

A separate process that isolates WindowServer and PID-lookup work from the UI
process. The shared protocol is a small Codable request/response surface
(`start`, `configureLogging`, `sourcePID` / `sourcePIDs`). The main app
configures logging to a shared diagnostic file after launch.

Resolving the *true* owning process matters because most menu bar items are
owned by Control Center rather than the app whose icon they show; click
forwarding targets the wrong process without it.

### External interfaces

| Interface | Direction | Notes |
| --- | --- | --- |
| Accessibility | System | Required. Detecting, moving and clicking menu bar items |
| Screen Recording | System | Optional. Item image capture and menu bar colour sampling for the Thaw Bar |

There is no URL scheme, no update feed, and no outbound network traffic.

## Data and persistence

- Preferences and profiles: `UserDefaults` (`com.nyshk97.MenuBarTidy`) and files under
  Application Support, on the local Mac only.
- Diagnostic logs: optional local files under `~/Library/Logs/Thaw/`, never
  uploaded.
- Undocumented diagnostic switches: [HIDDEN_FLAGS.md](HIDDEN_FLAGS.md).

## Build and release

- **Dev loop:** Xcode 26+ / macOS 26+. `xcodebuild -project Thaw.xcodeproj
  -scheme Thaw -configuration Debug -derivedDataPath Build build`.
- **CI:** `.github/workflows/ci.yml` runs `xcodebuild test` on macOS 26 and
  checks that `scripts/swiftlint-inputs.xcfilelist` still matches the tree.
- **Release:** none. There is no Sparkle, no notarization pipeline, and no
  distribution channel — the app is built and run locally, signed with the
  author's own development team.

## Differences that matter when reading upstream code

- The UI has no localization layer. Strings are Japanese literals in the
  source; `String(localized:)` and `LocalizedStringKey` do not appear.
- `MenuBarAppearanceManager` and the overlay panels are gone, so nothing
  composites over the real menu bar.
- Hotkeys, the search panel, the `thaw://` URL scheme, Focus filters, the
  onboarding tour and the Ice importer have all been removed.
