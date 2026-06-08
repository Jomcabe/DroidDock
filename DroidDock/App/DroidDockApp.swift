import SwiftUI

@main
struct DroidDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var preferences = Preferences.shared
    @StateObject private var appLog = AppLog.shared
    @StateObject private var updater = AppUpdater.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(preferences)
                .environmentObject(appLog)
                .frame(minWidth: 480, minHeight: 760)
                .onAppear { appState.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }

            CommandGroup(after: .toolbar) {
                Button(appState.isMirroring ? "Stop Mirroring" : "Start Mirroring") {
                    appState.toggleMirror()
                }
                .keyboardShortcut("m", modifiers: [.command])

                Button("Toggle Control HUD") { appState.toggleHUD() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Screenshot") { appState.captureScreenshot() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(preferences)
        }
    }
}
