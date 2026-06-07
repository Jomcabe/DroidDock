import SwiftUI

/// A compact status pill showing the connection phase and the active device.
struct ConnectionStatusView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 9, height: 9)
                .shadow(color: indicatorColor.opacity(0.8), radius: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.phase.headline)
                    .font(.caption).bold()
                if let device = app.selectedDevice {
                    Text(device.isWireless ? "\(device.displayName) · Wi-Fi" : device.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }

    private var indicatorColor: Color {
        switch app.phase {
        case .mirroring:    return .green
        case .ready:        return .mint
        case .detected:     return .yellow
        case .unauthorized: return .orange
        case .noDevice:     return .gray
        case .error:        return .red
        }
    }
}
