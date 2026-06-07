import AppKit
import SwiftUI

/// A non-activating, borderless floating panel. Used for the control HUD so it
/// hovers above the mirror without stealing key focus away from scrcpy (which
/// needs focus to receive keyboard/mouse input forwarded to the device).
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    // Allow the HUD's SwiftUI buttons to respond, but never become the main window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the HUD panel and hosts the SwiftUI `ControlHUD` inside it.
@MainActor
final class HUDWindowController {
    private weak var appState: AppState?
    private var panel: FloatingPanel?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        positionIfNeeded(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Internals

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 78))
        if let appState {
            let hosting = NSHostingView(rootView: ControlHUD().environmentObject(appState))
            panel.contentView = hosting
            panel.setContentSize(hosting.fittingSize)
        }
        return panel
    }

    private func positionIfNeeded(_ panel: FloatingPanel) {
        guard panel.frame.origin == .zero, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.minY + 64))
    }
}
