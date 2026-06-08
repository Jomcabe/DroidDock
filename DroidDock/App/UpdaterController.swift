import Foundation
import Combine
import Sparkle

/// Thin wrapper around Sparkle's standard updater so SwiftUI and the menu bar can
/// share one updater instance.
///
/// Sparkle checks the appcast feed (`SUFeedURL` in Info.plist), and only installs
/// an update whose EdDSA signature verifies against `SUPublicEDKey`. Until a real
/// public key is pasted into Info.plist (see the README), we start Sparkle in a
/// disabled state so a fresh checkout never errors on launch.
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    /// The Info.plist placeholder shipped in the repo; replaced per-developer.
    static let placeholderPublicKey = "REPLACE_WITH_YOUR_SPARKLE_EDDSA_PUBLIC_KEY"

    private let controller: SPUStandardUpdaterController

    /// True once Sparkle is configured and ready to check. Drives menu/button state.
    @Published private(set) var canCheckForUpdates = false

    /// Whether a valid public key was found, i.e. auto-update is actually wired up.
    let isConfigured: Bool

    /// `CFBundleShortVersionString`, e.g. "1.2.0", for display in Settings.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !key.isEmpty && key != Self.placeholderPublicKey

        // Only start the background updater when a real key is present. With
        // `startingUpdater: false` the updater object still exists (so settings
        // read fine) but won't run scheduled checks or surface config errors.
        controller = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        if isConfigured {
            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .assign(to: &$canCheckForUpdates)
            Log.info("Auto-update enabled (feed: \(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "—")).")
        } else {
            Log.warning("Auto-update disabled: set SUPublicEDKey in Info.plist to enable (see README).")
        }
    }

    /// Whether Sparkle checks for updates on its own schedule.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// User-initiated check ("Check for Updates…"). Shows Sparkle's standard UI.
    func checkForUpdates() {
        guard canCheckForUpdates else {
            Log.warning("Check for Updates unavailable — updater not configured.")
            return
        }
        controller.updater.checkForUpdates()
    }
}
