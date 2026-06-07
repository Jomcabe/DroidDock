import Foundation
import Combine

/// User-tunable settings, persisted in `UserDefaults` and observable by the UI.
/// `ScrcpyController` reads these when assembling its launch arguments, so
/// changes take effect on the next mirror start.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    // MARK: Mirroring
    @Published var maxFPS: Int            { didSet { defaults.set(maxFPS, forKey: Keys.maxFPS) } }
    @Published var maxSize: Int           { didSet { defaults.set(maxSize, forKey: Keys.maxSize) } }   // 0 == native
    @Published var videoBitRate: String   { didSet { defaults.set(videoBitRate, forKey: Keys.videoBitRate) } }
    @Published var renderDriver: String   { didSet { defaults.set(renderDriver, forKey: Keys.renderDriver) } }
    @Published var stayAwake: Bool        { didSet { defaults.set(stayAwake, forKey: Keys.stayAwake) } }
    @Published var turnScreenOff: Bool    { didSet { defaults.set(turnScreenOff, forKey: Keys.turnScreenOff) } }
    @Published var forwardAudio: Bool     { didSet { defaults.set(forwardAudio, forKey: Keys.forwardAudio) } }
    @Published var alwaysOnTop: Bool      { didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) } }

    // MARK: Behavior
    @Published var autoMirrorOnConnect: Bool { didSet { defaults.set(autoMirrorOnConnect, forKey: Keys.autoMirrorOnConnect) } }
    @Published var clipboardSync: Bool       { didSet { defaults.set(clipboardSync, forKey: Keys.clipboardSync) } }
    @Published var dockMirrorWindow: Bool    { didSet { defaults.set(dockMirrorWindow, forKey: Keys.dockMirrorWindow) } }
    @Published var launchAtPlugIn: Bool      { didSet { defaults.set(launchAtPlugIn, forKey: Keys.launchAtPlugIn) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Defaults.dictionary)

        maxFPS              = defaults.integer(forKey: Keys.maxFPS)
        maxSize             = defaults.integer(forKey: Keys.maxSize)
        videoBitRate        = defaults.string(forKey: Keys.videoBitRate) ?? "8M"
        renderDriver        = defaults.string(forKey: Keys.renderDriver) ?? "metal"
        stayAwake           = defaults.bool(forKey: Keys.stayAwake)
        turnScreenOff       = defaults.bool(forKey: Keys.turnScreenOff)
        forwardAudio        = defaults.bool(forKey: Keys.forwardAudio)
        alwaysOnTop         = defaults.bool(forKey: Keys.alwaysOnTop)
        autoMirrorOnConnect = defaults.bool(forKey: Keys.autoMirrorOnConnect)
        clipboardSync       = defaults.bool(forKey: Keys.clipboardSync)
        dockMirrorWindow    = defaults.bool(forKey: Keys.dockMirrorWindow)
        launchAtPlugIn      = defaults.bool(forKey: Keys.launchAtPlugIn)
    }

    private enum Keys {
        static let maxFPS = "maxFPS"
        static let maxSize = "maxSize"
        static let videoBitRate = "videoBitRate"
        static let renderDriver = "renderDriver"
        static let stayAwake = "stayAwake"
        static let turnScreenOff = "turnScreenOff"
        static let forwardAudio = "forwardAudio"
        static let alwaysOnTop = "alwaysOnTop"
        static let autoMirrorOnConnect = "autoMirrorOnConnect"
        static let clipboardSync = "clipboardSync"
        static let dockMirrorWindow = "dockMirrorWindow"
        static let launchAtPlugIn = "launchAtPlugIn"
    }

    /// M4-Pro-tuned defaults.
    private enum Defaults {
        static let dictionary: [String: Any] = [
            Keys.maxFPS: 120,
            Keys.maxSize: 0,
            Keys.videoBitRate: "8M",
            Keys.renderDriver: "metal",
            Keys.stayAwake: true,
            Keys.turnScreenOff: true,
            Keys.forwardAudio: true,
            Keys.alwaysOnTop: false,
            Keys.autoMirrorOnConnect: true,
            Keys.clipboardSync: true,
            Keys.dockMirrorWindow: true,
            Keys.launchAtPlugIn: true,
        ]
    }
}
