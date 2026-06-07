import SwiftUI
import AppKit

/// Bridges a SwiftUI view to its hosting `NSWindow`, resolving exactly once so
/// the window can be configured and handed to the mirror controller.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        attempt(view: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attempt(view: nsView, coordinator: context.coordinator)
    }

    private func attempt(view: NSView, coordinator: Coordinator) {
        guard !coordinator.resolved else { return }
        DispatchQueue.main.async { [weak view] in
            guard !coordinator.resolved, let window = view?.window else { return }
            coordinator.resolved = true
            onResolve(window)
        }
    }

    final class Coordinator {
        var resolved = false
    }
}
