import SwiftUI

/// Preferences window (⌘,). Changes are persisted immediately and applied on the
/// next mirror launch.
struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var app: AppState
    @StateObject private var updater = AppUpdater.shared

    var body: some View {
        TabView {
            mirroringTab
                .tabItem { Label("Mirroring", systemImage: "iphone") }
            inputTab
                .tabItem { Label("Input", systemImage: "cursorarrow.rays") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 500)
    }

    // MARK: Input

    private var inputTab: some View {
        Form {
            Section("Pointer") {
                Picker("Mouse", selection: $prefs.mouseMode) {
                    Text("Touch (default)").tag("sdk")
                    Text("Desktop pointer").tag("uhid")
                }
                Text("**Desktop pointer** gives the device a real mouse cursor, so you can click-and-drag to select text — like on a computer — and right-click for context menus, in any app. While the mirror is focused the pointer is captured by the device; press ⌥ or ⌘ to release it. Requires Android 11+.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard") {
                Picker("Keyboard", selection: $prefs.keyboardMode) {
                    Text("Text input (default)").tag("sdk")
                    Text("Physical keyboard").tag("uhid")
                }
                Text("**Physical keyboard** forwards keys as a hardware keyboard, enabling ⌃A / ⌃C / ⌃V and Shift-arrow text selection on the device. Set the device's keyboard layout to match your Mac for correct symbols. Requires Android 11+.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Tip: the control HUD's **Select All → Copy** also grabs a field's text without any selecting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
                Toggle("Mirror window always on top", isOn: $prefs.alwaysOnTop)
            }

            Section("Audio") {
                Toggle("Forward device audio", isOn: $prefs.forwardAudio)
                Picker("Codec", selection: $prefs.audioCodec) {
                    Text("Opus (recommended)").tag("opus")
                    Text("AAC").tag("aac")
                    Text("FLAC").tag("flac")
                }
                .disabled(!prefs.forwardAudio)
                TextField("Bit-rate", text: $prefs.audioBitRate)
                    .help("e.g. 128K, 192K")
                    .disabled(!prefs.forwardAudio)
                Stepper(value: $prefs.audioBuffer, in: 0...500, step: 10) {
                    LabeledContent("Buffer (ms)", value: "\(prefs.audioBuffer)")
                }
                .disabled(!prefs.forwardAudio)
                Text("Raise the buffer if audio crackles or stutters; lower it to cut latency. 120 ms suits most setups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Updates") {
                LabeledContent("Current version", value: updater.currentVersion)
                if updater.isConfigured {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    Button("Check for Updates Now…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                } else {
                    Text("Auto-update isn't configured for this build. Set `SUPublicEDKey` in Info.plist with your Sparkle public key — see the README.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
