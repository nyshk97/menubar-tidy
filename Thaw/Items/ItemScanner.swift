//
//  ItemScanner.swift
//  Project: MenuBar Tidy
//
//  Licensed under the GNU GPLv3

import AppKit
import ApplicationServices

/// Reads menu bar items through each owning app's `AXExtrasMenuBar`.
///
/// Asking every running process takes over a second (1.6s for 87 processes),
/// so the processes that have menu bar items are remembered: a full scan runs in
/// the background at launch, whenever the list is opened (for apps that show an
/// item long after they launch) and shortly after an app launches. Reading the
/// remembered processes is fast enough to do while the list opens (about 30ms
/// for 18 apps and 40 items).
final class ItemScanner {
    /// The processes known to have menu bar items.
    private(set) var knownPIDs: Set<pid_t> = []

    /// Whether a full scan has finished at least once since launch.
    private(set) var hasCompletedScan = false

    /// Called on the main thread when a full scan changes ``knownPIDs``.
    var onKnownPIDsChanged: (() -> Void)?

    private var isScanning = false
    private var observers: [NSObjectProtocol] = []

    /// How long one process may take to answer. A healthy process answers in a
    /// few milliseconds; one that is stuck would otherwise hold us for the
    /// system default of six seconds.
    static nonisolated let messagingTimeout: Float = 0.2

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.scanLaunchedApp(pid: pid)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                _ = self?.knownPIDs.remove(pid)
            }
        })
        startFullScan()
    }

    /// Asks every running process whether it has menu bar items, in the
    /// background. Does nothing while a scan is already running or without the
    /// accessibility permission.
    func startFullScan() {
        guard !isScanning, AXIsProcessTrusted() else {
            return
        }
        isScanning = true
        let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        let started = Date()
        Task.detached(priority: .utility) {
            let found = Self.pidsWithMenuBarItems(among: pids)
            await MainActor.run {
                self.finishFullScan(found: found, started: started)
            }
        }
    }

    private func finishFullScan(found: Set<pid_t>, started: Date) {
        isScanning = false
        hasCompletedScan = true
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Log.scanner.debug("Full scan: \(found.count) processes with items in \(elapsed)ms")
        guard found != knownPIDs else {
            return
        }
        knownPIDs = found
        onKnownPIDsChanged?()
    }

    /// Apps add their item a moment after launch, so look again a little later.
    private func scanLaunchedApp(pid: pid_t) {
        for delay in [2.0, 10.0] {
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: .seconds(delay))
                guard !Self.pidsWithMenuBarItems(among: [pid]).isEmpty else {
                    return
                }
                await MainActor.run {
                    guard !self.knownPIDs.contains(pid) else {
                        return
                    }
                    self.knownPIDs.insert(pid)
                    self.onKnownPIDsChanged?()
                }
            }
        }
    }

    /// The items of every known process, left to right.
    func readItems() -> [MenuBarItem] {
        var items: [MenuBarItem] = []
        for pid in knownPIDs {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                knownPIDs.remove(pid)
                continue
            }
            items += Self.readItems(pid: pid, bundleID: app.bundleIdentifier, appName: app.localizedName ?? app.bundleIdentifier ?? "?")
        }
        return items.sorted { $0.info.frame.minX < $1.info.frame.minX }
    }

    /// The items one app shows, in the order it reports them.
    static nonisolated func readItems(pid: pid_t, bundleID: String?, appName: String) -> [MenuBarItem] {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        guard let bar: AXUIElement = AXHelper.value(of: appElement, "AXExtrasMenuBar"),
              let children: [AXUIElement] = AXHelper.value(of: bar, kAXChildrenAttribute)
        else {
            return []
        }
        return children.enumerated().map { index, element in
            let info = ItemInfo(
                pid: pid,
                bundleID: bundleID,
                appName: appName,
                identifier: AXHelper.value(of: element, "AXIdentifier"),
                axDescription: AXHelper.value(of: element, kAXDescriptionAttribute) ?? "",
                axTitle: AXHelper.value(of: element, kAXTitleAttribute) ?? "",
                frame: AXHelper.frame(of: element) ?? .zero,
                isEnabled: AXHelper.value(of: element, kAXEnabledAttribute) ?? true,
                indexInApp: index
            )
            return MenuBarItem(info: info, element: element)
        }
    }

    /// The processes among `pids` that have menu bar items.
    static nonisolated func pidsWithMenuBarItems(among pids: [pid_t]) -> Set<pid_t> {
        var found: Set<pid_t> = []
        for pid in pids {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
            if let bar: AXUIElement = AXHelper.value(of: appElement, "AXExtrasMenuBar"),
               let children: [AXUIElement] = AXHelper.value(of: bar, kAXChildrenAttribute),
               !children.isEmpty
            {
                found.insert(pid)
            }
        }
        return found
    }
}

/// Small typed wrappers around the accessibility C API.
nonisolated enum AXHelper {
    static func value<T>(of element: AXUIElement, _ attribute: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = value(of: element, kAXPositionAttribute),
              let size: AXValue = value(of: element, kAXSizeAttribute)
        else {
            return nil
        }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent) else {
            return nil
        }
        return CGRect(origin: point, size: extent)
    }

    /// The right edge of an app's menus (the menu bar titles next to the Apple
    /// menu) within `screenFrame`, or `nil` if it has none there.
    static func menusMaxX(of pid: pid_t, within screenFrame: CGRect) -> CGFloat? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        guard let bar: AXUIElement = value(of: appElement, kAXMenuBarAttribute),
              let menus: [AXUIElement] = value(of: bar, kAXChildrenAttribute)
        else {
            return nil
        }
        let frames = menus.compactMap(frame(of:)).filter { $0.width > 0 && screenFrame.intersects($0) }
        return frames.map(\.maxX).max()
    }
}
