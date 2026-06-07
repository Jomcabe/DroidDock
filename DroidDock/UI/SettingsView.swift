import SwiftUI

/// Preferences window (⌘,). Changes are persisted immediately and applied on the
/// next mirror launch.
struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView {
            mirroringTab
                .tabItem { Label("Mirroring", systemImage: "iphone") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 420)
    }

    // MARK: Mirroring

    private var mirroringTab: some View {
        Form {
            Section("Performance") {
                Stepper(value: $prefs.maxFPS, in: 24...120, step: 6) {
                    LabeledContent("Max FPS", value: "\(prefs.maxFPS)")
                }
                TextField("Video bit-rate", text: $prefs.videoBitRate)
                    .help("e.g. 8M, 16M, 4000K")
                Stepper(value: $prefs.maxSize, in: 0...3840, step: 160) {
                    LabeledContent("Max size (px)", value: prefs.maxSize == 0 ? "Native" : "\(prefs.maxSize)")
                }
                Picker("Render driver", selection: $prefs.renderDriver) {
                    Text("Metal").tag("metal")
                    Text("OpenGL").tag("opengl")
                    Text("Software").tag("software")
                }
            }

            Section("Display") {
                Toggle("Keep device awake while mirroring", isOn: $prefs.stayAwake)
                Toggle("Turn device screen off", isOn: $prefs.turnScreenOff)
                Toggle("Forward device audio", isOn: $prefs.forwardAudio)
                Toggle("Mirror window always on top", isOn: $prefs.alwaysOnTop)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Behavior

    private var behaviorTab: some View {
        Form {
            Section("Automatic") {
                Toggle("Detect devices on plug-in", isOn: $prefs.launchAtPlugIn)
                Toggle("Start mirroring automatically", isOn: $prefs.autoMirrorOnConnect)
                    .disabled(!prefs.launchAtPlugIn)
            }

            Section("Integration") {
                Toggle("Bidirectional clipboard sync", isOn: $prefs.clipboardSync)
                Toggle("Dock mirror window to the frame", isOn: $prefs.dockMirrorWindow)
            }

            Section("Window docking") {
                LabeledContent("Accessibility permission") {
                    HStack(spacing: 8) {
                        Image(systemName: app.accessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(app.accessibilityGranted ? .green : .orange)
                        Text(app.accessibilityGranted ? "Granted" : "Not granted")
                            .foregroundStyle(.secondary)
                    }
                }
                if !app.accessibilityGranted {
                    Button("Grant Accessibility Permission…") {
                        app.requestAccessibilityPermission()
                    }
                    Text("Required to keep the borderless mirror docked as you move and resize the window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
