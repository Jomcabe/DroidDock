import SwiftUI

/// The floating control HUD: physical-button proxies, clipboard copy/paste, and
/// screenshot/record — all driven through `adb` so they work independently of
/// the mirror window's focus.
struct ControlHUD: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HUDButton(symbol: "chevron.backward", label: "Back")    { app.send(.back) }
                HUDButton(symbol: "house.fill", label: "Home")          { app.send(.home) }
                HUDButton(symbol: "square.on.square", label: "Recents") { app.send(.appSwitch) }
                divider
                HUDButton(symbol: "speaker.wave.1.fill", label: "Vol −") { app.send(.volumeDown) }
                HUDButton(symbol: "speaker.wave.3.fill", label: "Vol +") { app.send(.volumeUp) }
                HUDButton(symbol: "power", label: "Power")               { app.send(.power) }
            }

            HStack(spacing: 8) {
                HUDButton(symbol: "selection.pin.in.out", label: "All")  { app.selectAllOnDevice() }
                HUDButton(symbol: "doc.on.clipboard", label: "Copy")     { app.copyFromDevice() }
                HUDButton(symbol: "doc.on.clipboard.fill", label: "Paste") { app.pasteToDevice() }
                divider
                HUDButton(symbol: "rotate.right", label: "Rotate")       { app.rotateDevice() }
                HUDButton(symbol: "camera.fill", label: "Shot")          { app.captureScreenshot() }
                HUDButton(symbol: app.isRecording ? "stop.circle.fill" : "record.circle",
                          label: app.isRecording ? "Stop" : "Rec",
                          tint: app.isRecording ? .red : nil)            { app.toggleRecording() }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .padding(8)
        .fixedSize()
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 30)
    }
}
