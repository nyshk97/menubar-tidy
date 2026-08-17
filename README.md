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

Menu bar appearance customisation, hotkeys, the search panel, profiles and
layout switching, the always-hidden section, hover and scroll reveal, inline
expansion, the settings window (values are hardcoded), Ice settings import,
auto-update, and onboarding.

See [INVESTIGATION.md](INVESTIGATION.md) for how the parts fit together and
which of them are safe to remove.

## Build

Requires macOS 26 and Xcode 26.

```sh
xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Debug -derivedDataPath Build build
open Build/Build/Products/Debug/Thaw.app
```

The app needs Accessibility and Screen Recording. It appears in System Settings
as **MenuBar Tidy** with a blue icon; upstream Thaw appears as **Thaw** with an
amber one. Do not grant permissions to the wrong one, and do not run both at
once — they will fight over the same menu bar.

See [VERIFY.md](VERIFY.md) before trusting anything you observe. Two of this
app's failure modes are invisible in a screenshot, and running the test suite
corrupts the app's own settings.

## Differences from upstream

- Bundle identifier `com.nyshk97.Thaw`, display name "MenuBar Tidy", blue icon
- No Sparkle. Upstream's appcast URL is gone from `Info.plist`, so this build
  cannot replace itself with an upstream release
- Signed with my own development team
- Development happens on `main`; upstream develops on `development`

## License

GPL-3.0. See [LICENSE](LICENSE).

- Ice © 2023–2025 Jordan Baird
- Thaw © 2026 Toni Förster
- This fork © 2026 Tsubasa Namatame

Translators and other contributors to the upstream projects are credited in
[CREDITS.md](CREDITS.md).
