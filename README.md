# menubar-tidy

A small macOS menu bar helper for my own use: click its icon to get a list of
**every** menu bar item — including the ones macOS hides behind the notch or
under the frontmost app's menus — and choose one to open it.

**This is not a product and it is not supported.** Issues and pull requests here
will not be answered.

## What it does

- One status icon. Clicking it lists every menu bar item, split into hidden and
  visible ones, with the owning app's icon and name
- Choosing an item opens its menu just below where the item sits — behind the
  notch, if that is where it is hidden — via Accessibility (`AXPress`). Not under
  this app's icon: macOS opens a menu at its item, and moving the item there first
  is exactly what made 1.x fragile. Nothing is moved
- Only the Accessibility permission. No Screen Recording, no private APIs

What it does not do: hide items, move them, or arrange them. Arrange items with
⌘-drag; put the ones you use most on the right, since macOS hides items from the
left when the bar is full.

Limits:

- An item pushed past the screen's left edge (more items than the screen is wide)
  opens its menu off screen. The list greys it out
- A few items do not respond to `AXPress` (Spotlight — use ⌘Space; apps that
  tell left and right clicks apart by the mouse event)

Tip: `defaults -currentHost write -globalDomain NSStatusItemSpacing -int 6`
(then log out) packs items closer, so fewer overflow. The default is 16.

## History

Versions 1.x were a cut-down fork of [thaw-app/Thaw](https://github.com/thaw-app/Thaw)
that hid items by pushing them off the bar and moved them back to click them.
That machinery kept breaking with macOS updates. 2.0 replaced it: see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for what was measured and why.
[INVESTIGATION.md](INVESTIGATION.md) is the survey of the Thaw code base from the 1.x days.

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
identifier `com.nyshk97.MenuBarTidy.dev`, blue icon with a DEV ribbon. Each needs
its own Accessibility approval. The two can run at the same time.

See [VERIFY.md](VERIFY.md) for how to check changes, including scripts that read
and press menu bar items without launching the app.

## License

GPL-3.0. See [LICENSE](LICENSE).

- Ice © 2023–2025 Jordan Baird
- Thaw © 2026 Toni Förster
- MenuBar Tidy © 2026 Tsubasa Namatame

A few files carried over from Thaw keep their upstream headers.
