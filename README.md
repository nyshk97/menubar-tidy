# menubar-tidy

A personal fork of [thaw-app/Thaw](https://github.com/thaw-app/Thaw), being cut
down to a minimal macOS menu bar manager for my own use.

**This is not a product and it is not supported.** It exists so I can run the
handful of Thaw features I actually use, without the rest. If you want a menu
bar manager, use [Thaw](https://github.com/thaw-app/Thaw) — it is maintained,
it is far more capable, and this fork will lag behind it.

Issues and pull requests here will not be answered. Report bugs to
[upstream](https://github.com/thaw-app/Thaw/issues) instead, after reproducing
them on a real Thaw build.

## What this keeps

Five things. Everything else is being removed.

1. Hiding menu bar items by pushing them off the bar with an invisible
   `NSStatusItem` divider
2. Clicking empty menu bar space to reveal the hidden items in a separate bar
3. Forwarding a click on that bar to the real menu bar item
4. One status icon, always visible, so it is obvious the app is running
5. Persisting the divider position

## What this removes

Menu bar appearance customisation, hotkeys, the search panel, hover and scroll
reveal, the `thaw://` URL scheme, Focus filters, Ice settings import,
auto-update, the onboarding tour, and localization (the UI is written in
Japanese directly). The settings window is now the drag-to-arrange layout
editor and nothing else — every other value is a hardcoded default.

Profiles and the always-hidden section survive without settings UI: profiles
are reachable from the status icon's menu, and the always-hidden section is on
whenever you drag an item into it.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes what is left.
[INVESTIGATION.md](INVESTIGATION.md) is the pre-strip-down survey that decided
what was safe to remove — useful for the reasoning, not as a map of the current
tree.

## Install

```sh
brew install nyshk97/tap/menubar-tidy
```

Releases are notarized `.zip`s built from this tree. The app checks for updates
itself (Sparkle) and the cask follows; what changed in each version is in
[docs/CHANGELOG.md](docs/CHANGELOG.md).

## Build

Requires macOS 26 and Xcode 26.

```sh
xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Debug -derivedDataPath Build build
open "Build/Build/Products/Debug/MenuBarTidy-dev.app"
```

Debug builds are a **separate app** from the release install: `MenuBarTidy-dev.app`,
identifier `com.nyshk97.MenuBarTidy.dev`, blue icon with a DEV ribbon, and its own
defaults, profiles and logs. The release the cask installs keeps running while this
one is built, crashed and rebuilt. Release builds are unchanged — `MenuBar Tidy.app`
under the plain identifier.

The app needs Accessibility and Screen Recording, both required. It appears in
System Settings as **MenuBar Tidy** with a blue icon, and the dev build as
**MenuBarTidy-dev** with the ribboned one; each needs its own approvals. If
upstream Thaw is also installed it appears as **Thaw** with an amber icon — do not
grant permissions to the wrong one, and do not run two of them at once, since they
will fight over the same menu bar.

See [VERIFY.md](VERIFY.md) before trusting anything you observe. Two of this
app's failure modes are invisible in a screenshot, and running the test suite
corrupts the app's own settings.

## Differences from upstream

- Bundle named `MenuBar Tidy.app`, blue icon, identifier
  `com.nyshk97.MenuBarTidy`. Support files live beside it — `~/Library/Logs/
  MenuBar Tidy/`, `~/Library/Application Support/MenuBar Tidy/Profiles/` — so
  nothing collides with an upstream Thaw install. Debug builds shift all of that
  onto `MenuBarTidy-dev`. The Swift module stays `Thaw`, which is what every test
  imports
- No Sparkle. Upstream's appcast URL is gone from `Info.plist`, so this build
  cannot replace itself with an upstream release
- No network surface at all, and no URL scheme
- Japanese-only UI, with no string catalog
- Release builds are signed with my own Developer ID and notarized; debug builds
  keep the development certificate
- Development happens on `main`; upstream develops on `development`

## License

GPL-3.0. See [LICENSE](LICENSE).

- Ice © 2023–2025 Jordan Baird
- Thaw © 2026 Toni Förster
- This fork © 2026 Tsubasa Namatame

Contributors to the upstream projects are credited in
[Thaw's CREDITS.md](https://github.com/thaw-app/Thaw/blob/development/CREDITS.md).
