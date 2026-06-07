import Foundation
import AppKit

/// Owns the scrcpy mirroring process (and an optional headless recorder).
/// Builds M-series-tuned launch flags from `Preferences`, launches scrcpy
/// silently with our embedded toolchain, and auto-restarts on unexpected exit
/// while a device is still present. All callbacks are delivered on the main queue.
final class ScrcpyController {

    /// The fixed window title we tag scrcpy with so the Accessibility-based
    /// positioner can find the right window.
    static let mirrorWindowTitle = "DroidDock-Mirror"

    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    private(set) var process: Process?
    private var recorderProcess: Process?
    private var currentSerial: String?
    private var currentFrame: CGRect?
    private var intentionalStop = false
    private var lastStartDate = Date.distantPast
    private var restartAttempts = 0
    private let maxRestartAttempts = 4
    private let preferences: Preferences

    /// Fires on the main queue whenever the mirror state changes.
    var onStateChange: ((State) -> Void)?
    /// Fires on the main queue when recording starts/stops.
    var onRecordingChange: ((Bool) -> Void)?

    var isRunning: Bool { process?.isRunning ?? false }
    var isRecording: Bool { recorderProcess?.isRunning ?? false }
    /// The scrcpy process id, for the window positioner.
    var pid: pid_t? { process?.processIdentifier }

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    // MARK: Mirroring

    /// Launch the mirror. `launchFrame` is the desired window rect in scrcpy's
    /// top-left global coordinate space (see `MirrorWindowController`).
    @discardableResult
    func start(serial: String, launchFrame: CGRect?) -> Bool {
        guard !isRunning else { return true }
        intentionalStop = false
        currentSerial = serial
        currentFrame = launchFrame

        do {
            let scrcpy = try BinaryResolver.scrcpyURL()
            let environment = try BinaryResolver.scrcpyEnvironment()
            let arguments = makeArguments(serial: serial, frame: launchFrame)

            emit(.starting)
            lastStartDate = Date()
            let proc = try ProcessRunner.launch(
                scrcpy, arguments: arguments, environment: environment
            ) { [weak self] finished in
                self?.handleTermination(finished)
            }
            process = proc
            emit(.running)
            Log.info("scrcpy launched (\(serial))  ·  \(arguments.joined(separator: " "))")
            return true
        } catch {
            Log.error("scrcpy launch failed: \(error.localizedDescription)")
            emit(.failed(error.localizedDescription))
            return false
        }
    }

    /// User- or app-initiated stop. Suppresses auto-restart.
    func stop() {
        intentionalStop = true
        restartAttempts = 0
        if let process, process.isRunning { process.terminate() }
        process = nil
        stopRecording()
        emit(.stopped)
    }

    // MARK: Recording (headless second instance, so the live mirror is untouched)

    @discardableResult
    func startRecording(serial: String, to url: URL) -> Bool {
        guard !isRecording else { return false }
        do {
            let scrcpy = try BinaryResolver.scrcpyURL()
            let environment = try BinaryResolver.scrcpyEnvironment()
            var arguments = ["-s", serial, "--no-window", "--no-playback", "--record=\(url.path)"]
            if preferences.maxFPS > 0 { arguments.append("--max-fps=\(preferences.maxFPS)") }
            if !preferences.forwardAudio { arguments.append("--no-audio") }

            let proc = try ProcessRunner.launch(
                scrcpy, arguments: arguments, environment: environment
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.recorderProcess = nil
                    self?.onRecordingChange?(false)
                }
            }
            recorderProcess = proc
            onRecordingChange?(true)
            Log.info("Recording started → \(url.lastPathComponent)")
            return true
        } catch {
            Log.error("Recording failed: \(error.localizedDescription)")
            return false
        }
    }

    /// SIGTERM lets scrcpy finalize (moov atom) the recording file cleanly.
    func stopRecording() {
        guard let recorder = recorderProcess, recorder.isRunning else { return }
        recorder.terminate()
        recorderProcess = nil
        onRecordingChange?(false)
        Log.info("Recording stopped")
    }

    // MARK: - Internals

    private func makeArguments(serial: String, frame: CGRect?) -> [String] {
        var args = ["-s", serial,
                    "--window-title=\(Self.mirrorWindowTitle)",
                    "--window-borderless"]

        if preferences.maxFPS > 0          { args.append("--max-fps=\(preferences.maxFPS)") }
        if !preferences.videoBitRate.isEmpty { args.append("--video-bit-rate=\(preferences.videoBitRate)") }
        if preferences.maxSize > 0         { args.append("--max-size=\(preferences.maxSize)") }
        if !preferences.renderDriver.isEmpty { args.append("--render-driver=\(preferences.renderDriver)") }
        if preferences.stayAwake           { args.append("--stay-awake") }
        if preferences.turnScreenOff       { args.append("--turn-screen-off") }
        if preferences.alwaysOnTop         { args.append("--always-on-top") }
        if !preferences.forwardAudio       { args.append("--no-audio") }

        if let frame {
            args.append("--window-x=\(Int(frame.origin.x))")
            args.append("--window-y=\(Int(frame.origin.y))")
            args.append("--window-width=\(Int(frame.size.width))")
            args.append("--window-height=\(Int(frame.size.height))")
        }
        return args
    }

    private func handleTermination(_ finished: Process) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Ignore terminations from a stale process reference.
            guard finished === self.process || self.process == nil else { return }
            self.process = nil

            if self.intentionalStop {
                self.emit(.stopped)
                return
            }

            let status = finished.terminationStatus
            Log.warning("scrcpy exited unexpectedly (status \(status))")

            // A run that lasted a while is a "drop", not a crash loop — reset.
            if Date().timeIntervalSince(self.lastStartDate) > 10 {
                self.restartAttempts = 0
            }

            guard self.restartAttempts < self.maxRestartAttempts,
                  let serial = self.currentSerial else {
                self.emit(.failed("scrcpy exited (status \(status))"))
                return
            }

            self.restartAttempts += 1
            let delay = min(pow(2.0, Double(self.restartAttempts)), 16)   // 2,4,8,16
            Log.info("Restarting scrcpy in \(Int(delay))s (attempt \(self.restartAttempts)/\(self.maxRestartAttempts))")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.intentionalStop else { return }
                _ = self.start(serial: serial, launchFrame: self.currentFrame)
            }
        }
    }

    private func emit(_ state: State) {
        if Thread.isMainThread {
            onStateChange?(state)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
        }
    }
}
