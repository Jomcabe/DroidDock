import AppKit

/// Hosts the menu bar (status) item and bridges app-lifecycle events into
/// `AppState`. The main window and Settings scene are owned by SwiftUI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

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
    @objc private func quit()           { NSApp.terminate(nil) }
}
