import AppKit
import ApplicationServices

/// Keeps the (separate-process) scrcpy mirror window visually "docked" inside
/// the DroidDock main window.
///
/// macOS can't reparent another process's window into our view hierarchy, so we
/// (1) hand scrcpy an initial frame at launch and (2) — if the user grants
/// Accessibility permission — track the main window and reposition scrcpy's
/// window via `AXUIElement` so it follows moves/resizes seamlessly. Without the
/// permission, the launch-time frame + `--always-on-top` is the fallback.
final class MirrorWindowController {

    /// Inset of the mirror area inside the host window's content rect.
    struct Insets {
        var top: CGFloat = 52      // room for the translucent title overlay
        var left: CGFloat = 16
        var right: CGFloat = 16
        var bottom: CGFloat = 16
    }

    private weak var hostWindow: NSWindow?
    private var scrcpyPID: pid_t?
    private var trackingTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let preferences: Preferences
    var insets = Insets()

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    deinit { detach() }

    // MARK: Host window

    func attach(to window: NSWindow) {
        hostWindow = window
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification,
                     NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification,
                     NSWindow.didEndLiveResizeNotification] {
            let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.reposition()
            }
            observers.append(token)
        }
    }

    func detach() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver(_:))
        observers.removeAll()
        stopTracking()
        hostWindow = nil
    }

    // MARK: scrcpy lifecycle hooks

    /// The frame to pass to scrcpy at launch, in scrcpy's top-left global space.
    func launchFrame() -> CGRect? {
        guard preferences.dockMirrorWindow, let rect = targetScreenRect() else { return nil }
        return Self.topLeftRect(fromAppKitScreenRect: rect)
    }

    /// Begin following the host window once scrcpy has been launched. The mirror
    /// window appears asynchronously, so we poll briefly before relying on
    /// notifications.
    func beginTracking(pid: pid_t?) {
        scrcpyPID = pid
        guard preferences.dockMirrorWindow else { return }
        stopTracking()

        var ticks = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.reposition()
            ticks += 1
            if ticks >= 16 { t.invalidate() }   // ~8s of settling, then notifications drive it
        }
        trackingTimer = timer
    }

    func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        scrcpyPID = nil
    }

    // MARK: Accessibility permission

    /// Whether DroidDock currently has Accessibility (AX) permission.
    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Prompt for Accessibility permission (opens the System Settings pane).
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Positioning

    private func targetScreenRect() -> NSRect? {
        guard let window = hostWindow else { return nil }
        // Content rect in window coords → screen coords, then inset.
        let content = window.contentLayoutRect
        let onScreen = window.convertToScreen(content)
        let rect = NSRect(
            x: onScreen.minX + insets.left,
            y: onScreen.minY + insets.bottom,
            width: max(0, onScreen.width - insets.left - insets.right),
            height: max(0, onScreen.height - insets.top - insets.bottom)
        )
        return rect.width > 1 && rect.height > 1 ? rect : nil
    }

    private func reposition() {
        guard preferences.dockMirrorWindow,
              Self.hasAccessibilityPermission,
              let pid = scrcpyPID,
              let target = targetScreenRect(),
              let mirror = mirrorWindowElement(pid: pid) else { return }

        let axRect = Self.topLeftRect(fromAppKitScreenRect: target)
        setFrame(of: mirror, position: axRect.origin, size: axRect.size)
    }

    /// Locate scrcpy's window by title via the Accessibility API.
    private func mirrorWindowElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return nil }

        for window in windows {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String,
               title == ScrcpyController.mirrorWindowTitle {
                return window
            }
        }
        // Fall back to the first window if the title didn't match (some scrcpy
        // builds suffix the title with device info).
        return windows.first
    }

    private func setFrame(of element: AXUIElement, position: CGPoint, size: CGSize) {
        var pos = position
        var sz = size
        if let posValue = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &sz) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// Convert an AppKit screen rect (bottom-left origin, y-up) to the top-left
    /// origin (y-down) global space used by scrcpy `--window-*` flags and the
    /// Accessibility API.
    static func topLeftRect(fromAppKitScreenRect rect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        let topLeftY = primaryHeight - rect.maxY
        return CGRect(x: rect.minX, y: topLeftY, width: rect.width, height: rect.height)
    }
}
