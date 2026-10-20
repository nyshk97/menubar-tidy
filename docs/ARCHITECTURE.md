# Architecture

A map of **MenuBar Tidy** 2.x. This is not an API reference. For how to check
the app works, see [VERIFY.md](../VERIFY.md); for why 2.0 replaced the Thaw
fork, see "Why it does not hide or move items" below and the plan in
[docs/plans/2026-10-20-1826-item-list-menu.md](plans/2026-10-20-1826-item-list-menu.md).

## What it does

One status icon. Clicking it opens a menu listing **every** menu bar item —
including the ones macOS has hidden behind the notch or under the frontmost
app's menus — split into "隠れている" (hidden) and "見えている" (visible).
Choosing an item sends it `AXPress`, which opens its menu or panel just below
where the item sits.

It does not hide, move or reorder anything. Arranging items is left to macOS
(⌘-drag). The only permission is Accessibility.

## Repository layout

| Path | Role |
| --- | --- |
| `Thaw/Main/` | Entry point, `AppDelegate`, Sparkle (`Updates.swift`), the Accessibility permission |
| `Thaw/Items/` | Reading items, deciding how to list them, pressing them |
| `Thaw/Menu/` | The status item's menu |
| `Thaw/Utilities/` | `AppIdentity` (dev vs. release build), `Constants`, logging |
| `ThawTests/` | swift-testing suite (rules and geometry) |
| `scripts/` | `list-ax-items.swift` / `press-ax-item.swift` / `menu-preview/` (see VERIFY.md §3), release scripts, icon renderers |

The directory, target, scheme and Swift module are still called `Thaw`; the
release scripts and tests refer to those names.

## Runtime

```text
AppDelegate
├── NSStatusItem (autosave name "Thaw.ControlItem.Visible", kept from 1.x)
├── StatusMenuController — NSMenuDelegate; rebuilds the menu each time it opens
├── ItemScanner          — which processes have items; reads their AXExtrasMenuBar
└── UpdatesManager       — Sparkle (release build only)

Thaw/Items (pure rules, unit-tested)
├── ItemRules.isListed      — in a screen's menu bar strip, enabled, non-empty, not ours
├── ItemRules.screen(for:)  — the screen the items are on (the active menu bar's)
├── ItemVisibility.classify — visible / hidden (notch, app menus) / off screen
├── ItemRules.title         — the name shown in the list
└── ItemRules.match         — find an item again after its app relaunched
ItemPresser                 — AXPress off the main thread, 0.15s after the menu closes
```

- **Reading.** Every app exposes its items as the children of its
  `AXExtrasMenuBar`, with the owning process, frame, `AXDescription`,
  `AXTitle` and (for Control Center) `AXIdentifier`. The window list
  (`CGWindowList`) is not used: since macOS 26 it shows every third-party item as
  Control Center's `Item-0`.
- **Speed.** Asking all ~90 processes takes ~1.6s, so `ItemScanner` remembers
  the ~18 that have items (full scan in the background at launch, whenever the
  menu opens, and shortly after an app launches). Reading the remembered ones
  while the menu opens takes ~30ms.
- **Which screen.** Accessibility reports only the items of the active menu bar
  (the screen with keyboard focus). When that screen's menu bar is tucked away
  (a full-screen app), the items sit ~60pt above the screen; the menu bar strip
  extends upward to include them.
- **Pressing.** An item that opens an `NSMenu` does not return from `AXPress`
  until the menu closes; after the 1s timeout the call reports
  `kAXErrorCannotComplete` while the menu stays open. That is success.

## Why it does not hide or move items

Measured on 2026-10-20 (macOS 26.6.2, MacBook Pro 14", scripts in
`scripts/`):

- An item opens its menu **where the item is**, and that position cannot be
  changed through accessibility.
- 1.x (Thaw) hid items by pushing them to x ≈ -4000 with a wide divider. Pressed
  there, their menus open off screen, so Thaw had to *move* an item onto the
  bar before clicking it — synthetic ⌘-drags, position inference and private
  APIs, which is what broke with every macOS update.
- Items that do not fit are laid out by macOS right to left without gaps and
  keep on-screen coordinates behind the notch or under the app menus. Pressed
  there, their menus open just below, visibly. Only items past the screen's left
  edge (more items than the screen is wide) cannot be opened.

So 2.0 lets macOS overflow the bar and opens hidden items from a list.

## External interfaces

| Interface | Direction | Notes |
| --- | --- | --- |
| Accessibility | System | Required. Reading and pressing menu bar items |
| Sparkle appcast | Network | Release build only: `releases/latest/download/appcast.xml` |

## Data and persistence

- `UserDefaults` (`com.nyshk97.MenuBarTidy`): the status item's position
  (written by AppKit) and Sparkle's state. Nothing else.
- Logs: unified logging (`os.Logger`, subsystem = bundle identifier). No files.

## Build and release

- **Dev loop:** Xcode 26+ / macOS 26+. Debug builds are a separate app
  (`MenuBarTidy-dev.app`, `com.nyshk97.MenuBarTidy.dev`).
- **CI:** `.github/workflows/ci.yml` runs the tests unsigned and checks that
  `scripts/swiftlint-inputs.xcfilelist` still matches the tree.
- **Release:** `mise run release <bump>` — Developer ID signing, notarization,
  GitHub Release with an EdDSA-signed appcast, Homebrew cask update. See
  VERIFY.md §8.
