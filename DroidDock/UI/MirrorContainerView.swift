import SwiftUI

/// The central bezel where the scrcpy mirror window docks. When not mirroring it
/// shows a state-appropriate prompt; while mirroring, the scrcpy window overlays
/// this area and the faint hint sits behind it.
struct MirrorContainerView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.30))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.06)))

            content
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        switch app.phase {
        case .mirroring:
            VStack(spacing: 10) {
                Image(systemName: "rectangle.connected.to.line.below").font(.system(size: 44))
                Text("Mirroring \(app.selectedDevice?.displayName ?? "device")")
            }
            .foregroundStyle(.secondary)
            .opacity(0.22)

        case .ready:
            VStack(spacing: 16) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 66))
                    .foregroundStyle(.tint)
                Text("Ready to mirror \(app.selectedDevice?.displayName ?? "")")
                    .font(.title3).bold()
                Button { app.startMirror() } label: {
                    Label("Start Mirroring", systemImage: "play.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .noDevice:
            emptyState(icon: "cable.connector.horizontal",
                       title: "Connect a device",
                       subtitle: "Plug in an Android phone with USB debugging enabled.")

        case .detected:
            emptyState(icon: "magnifyingglass",
                       title: "Detecting…",
                       subtitle: "Talking to the device over ADB.")

        case .unauthorized:
            emptyState(icon: "lock.shield",
                       title: "Authorize on the device",
                       subtitle: "Accept the “Allow USB debugging?” prompt on your phone.")

        case .error(let message):
            emptyState(icon: "exclamationmark.triangle.fill",
                       title: "Something went wrong",
                       subtitle: message,
                       tint: .orange)
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String, tint: Color = .secondary) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(tint)
            Text(title).font(.title3).bold()
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(40)
    }
}
