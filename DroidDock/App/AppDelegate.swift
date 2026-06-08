import AppKit

/// Hosts the menu bar (status) item and bridges app-lifecycle events into
/// `AppState`. The main window and Settings scene are owned by SwiftUI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    /// Runs before any window or device monitoring exists: guarantee this launch
    /// is the *only* DroidDock. A freshly built/installed copy must take over from
    /// — not coexist with — an older one still alive in the menu bar; otherwise
    /// both react to the same device authorization and you get two scrcpy windows.
    func applicationWillFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
    }

    /// Keep running (and keep mirroring) when the window is closed — the menu bar
    /// item remains the control surface.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in AppState.shared.shutdown() }
    }

    // MARK: Single-instance enforcement

    /// Replace any older DroidDock instances so exactly one runs. `pkill` of stray
    /// scrcpy windows handles copies that crashed; terminating live instances
    /// handles a Debug build launched alongside the installed Release (different
    /// bundle paths, which LaunchServices is happy to run side by side).
    private func enforceSingleInstance() {
        // Sweep scrcpy mirrors orphaned by a previous run that never cleaned up.
        ScrcpyController.reapOrphanMirrors()

        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = NSRunningApplication.current.processIdentifier
        func otherInstances() -> [NSRunningApplication] {
            // A fresh snapshot each call, so terminated copies drop out naturally.
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != myPID && !$0.isTerminated }
        }

        let others = otherInstances()
        guard !others.isEmpty else { return }
        Log.info("Replacing \(others.count) older DroidDock instance(s) so only one runs.")

        // Ask them to quit cleanly first — that runs their shutdown(), which stops
        // their own scrcpy child — then wait briefly before force-killing holdouts.
        others.forEach { $0.terminate() }

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if otherInstances().isEmpty { break }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let survivors = otherInstances()
        if !survivors.isEmpty {
            survivors.forEach { $0.forceTerminate() }
            // A force-killed instance can't stop its own scrcpy, so sweep again.
            ScrcpyController.reapOrphanMirrors()
        }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "iphone.gen3.radiowaves.left.and.right",
                                     accessibilityDescription: "DroidDock")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show DroidDock", action: #selector(showMainWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Start / Stop Mirroring", action: #selector(toggleMirror), keyEquivalent: "m")
        menu.addItem(withTitle: "Toggle Control HUD", action: #selector(toggleHUD), keyEquivalent: "h")
        menu.addItem(withTitle: "Screenshot", action: #selector(screenshot), keyEquivalent: "s")
        menu.addItem(withTitle: "Connect Wirelessly", action: #selector(connectWireless), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Quit DroidDock", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        return menu
    }

    // MARK: Actions (menu fires on the main thread → hop to the main actor)

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleMirror()   { Task { @MainActor in AppState.shared.toggleMirror() } }
    @objc private func toggleHUD()      { Task { @MainActor in AppState.shared.toggleHUD() } }
    @objc private func screenshot()     { Task { @MainActor in AppState.shared.captureScreenshot() } }
    @objc private func connectWireless(){ Task { @MainActor in AppState.shared.connectWirelessly() } }
    @objc private func checkForUpdates(){ AppUpdater.shared.checkForUpdates() }
    @objc private func quit()           { NSApp.terminate(nil) }
}
