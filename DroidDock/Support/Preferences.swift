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

    // MARK: Audio
    @Published var audioCodec: String     { didSet { defaults.set(audioCodec, forKey: Keys.audioCodec) } }
    @Published var audioBitRate: String   { didSet { defaults.set(audioBitRate, forKey: Keys.audioBitRate) } }
    @Published var audioBuffer: Int       { didSet { defaults.set(audioBuffer, forKey: Keys.audioBuffer) } }  // ms

    // MARK: Input
    @Published var mouseMode: String      { didSet { defaults.set(mouseMode, forKey: Keys.mouseMode) } }
    @Published var keyboardMode: String   { didSet { defaults.set(keyboardMode, forKey: Keys.keyboardMode) } }

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
        audioCodec          = defaults.string(forKey: Keys.audioCodec) ?? "opus"
        audioBitRate        = defaults.string(forKey: Keys.audioBitRate) ?? "128K"
        audioBuffer         = defaults.integer(forKey: Keys.audioBuffer)
        mouseMode           = defaults.string(forKey: Keys.mouseMode) ?? "sdk"
        keyboardMode        = defaults.string(forKey: Keys.keyboardMode) ?? "sdk"
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
        static let audioCodec = "audioCodec"
        static let audioBitRate = "audioBitRate"
        static let audioBuffer = "audioBuffer"
        static let mouseMode = "mouseMode"
        static let keyboardMode = "keyboardMode"
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
            // Opus @ 128K is transparent for most content. The 120 ms buffer is
            // well above scrcpy's 50 ms default, which underruns on busy systems
            // and is the usual cause of crackly / choppy forwarded audio.
            Keys.audioCodec: "opus",
            Keys.audioBitRate: "128K",
            Keys.audioBuffer: 120,
            // "sdk" forwards the mouse/keyboard as touch + text events (works
            // everywhere). "uhid" simulates a physical mouse/keyboard so you get
            // desktop-style click-drag text selection and ⌃A/⌃C/⌃V (Android 11+).
            Keys.mouseMode: "sdk",
            Keys.keyboardMode: "sdk",
            Keys.autoMirrorOnConnect: true,
            Keys.clipboardSync: true,
            Keys.dockMirrorWindow: true,
            Keys.launchAtPlugIn: true,
        ]
    }
}
