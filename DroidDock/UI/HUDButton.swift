import SwiftUI

/// A single glassy control-HUD button: SF Symbol over a tiny caption, with a
/// hover highlight.
struct HUDButton: View {
    let symbol: String
    let label: String
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(width: 46, height: 42)
            .foregroundStyle(tint ?? .primary)
            .background(hovering ? Color.white.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
    }
}
