import AppKit
import Combine

/// The single source of truth the UI binds to, and the orchestrator that wires
/// the device monitor, ADB, scrcpy, and the docked mirror window together.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Published UI state
    @Published private(set) var devices: [AndroidDevice] = []
    @Published var selectedSerial: String?
    @Published private(set) var phase: AppPhase = .noDevice
    @Published private(set) var isRecording = false
    @Published private(set) var accessibilityGranted = false
    @Published var hudVisible = false

    // MARK: Collaborators
    let preferences: Preferences
    private let adb = ADBController()
    private let scrcpy: ScrcpyController
    private let monitor: DeviceMonitor
    let clipboard: ClipboardManager
    let mirror = MirrorWindowController()
    private lazy var hud = HUDWindowController(appState: self)

    var selectedDevice: AndroidDevice? {
        guard let selectedSerial else { return nil }
        return devices.first { $0.serial == selectedSerial }
    }

    var isMirroring: Bool { scrcpy.isRunning }

    private init(preferences: Preferences = .shared) {
        self.preferences = preferences
        self.scrcpy = ScrcpyController(preferences: preferences)
        self.monitor = DeviceMonitor(adb: adb)
        self.clipboard = ClipboardManager(adb: adb)
        wireCallbacks()
    }

    // MARK: Lifecycle

    func start() {
        accessibilityGranted = MirrorWindowController.hasAccessibilityPermission
        do {
            try BinaryResolver.validateToolchain()
            Log.info("Embedded toolchain verified.")
        } catch {
            phase = .error(error.localizedDescription)
            Log.error(error.localizedDescription)
            return
        }
        monitor.start()
        Log.info("DroidDock is watching for devices.")
    }

    func shutdown() {
        scrcpy.stop()
        clipboard.stop()
        monitor.stop()
        mirror.detach()
    }

    /// Called once the main window exists so the mirror can dock to it.
    func attachHostWindow(_ window: NSWindow) {
        mirror.attach(to: window)
    }

    // MARK: Mirror control

    func toggleMirror() { isMirroring ? stopMirror() : startMirror() }

    func startMirror() {
        guard let device = selectedDevice, device.state.isReady else {
            Log.warning("Cannot mirror: no authorized device selected.")
            return
        }
        let frame = mirror.launchFrame()
        if scrcpy.start(serial: device.serial, launchFrame: frame) {
            mirror.beginTracking(pid: scrcpy.pid)
            if preferences.clipboardSync { clipboard.start(serial: device.serial) }
        }
    }

    func stopMirror() {
        scrcpy.stop()
        mirror.stopTracking()
        clipboard.stop()
    }

    // MARK: HUD

    func toggleHUD() { hudVisible ? hideHUD() : showHUD() }
    func showHUD() { hud.show(); hudVisible = true }
    func hideHUD() { hud.hide(); hudVisible = false }

    // MARK: Buttons / input

    func send(_ key: AndroidKey) {
        guard let serial = selectedSerial else { return }
        Task { await adb.sendKey(key, serial: serial) }
    }

    func rotateDevice() {
        guard let serial = selectedSerial else { return }
        Task { await adb.rotateDevice(serial: serial) }
    }

    // MARK: Clipboard copy/paste between the mirror and the Mac

    /// Copy the device's current text selection to the Mac clipboard. Sends
    /// KEYCODE_COPY (which puts the selection on the device clipboard) and then
    /// pulls it back to `NSPasteboard` (scrcpy's autosync also mirrors it).
    func copyFromDevice() {
        guard let serial = selectedSerial else { return }
        Task {
            await adb.sendKey(.copy, serial: serial)
            try? await Task.sleep(nanoseconds: 350_000_000)
            if let text = await adb.getDeviceClipboard(serial: serial), !text.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                Log.info("Copied \(text.count) characters from the device.")
            } else {
                Log.info("Sent Copy to the device (synced to Mac if a selection was active).")
            }
        }
    }

    /// Paste the Mac clipboard into the focused field on the device: push the
    /// text to the device clipboard, then send KEYCODE_PASTE.
    func pasteToDevice() {
        guard let serial = selectedSerial else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty else {
            Log.warning("Paste: the Mac clipboard has no text.")
            return
        }
        Task {
            _ = await adb.setDeviceClipboard(text, serial: serial)
            await adb.sendKey(.paste, serial: serial)
            Log.info("Pasted \(text.count) characters to the device.")
        }
    }

    // MARK: Screenshot / recording

    func captureScreenshot() {
        guard let serial = selectedSerial else { return }
        Task {
            do {
                let data = try await adb.screenshotPNG(serial: serial)
                let url = Self.outputURL(directory: "Pictures", prefix: "Screenshot", ext: "png")
                try data.write(to: url)
                Log.info("Screenshot saved → \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                Log.error("Screenshot failed: \(error.localizedDescription)")
            }
        }
    }

    func toggleRecording() {
        guard let serial = selectedSerial else { return }
        if scrcpy.isRecording {
            scrcpy.stopRecording()
        } else {
            let url = Self.outputURL(directory: "Movies", prefix: "Recording", ext: "mp4")
            scrcpy.startRecording(serial: serial, to: url)
        }
    }

    // MARK: Wireless

    func connectWirelessly() {
        guard let device = selectedDevice, !device.isWireless else {
            Log.warning("Wireless: select a USB-connected device first.")
            return
        }
        Task {
            guard let ip = await adb.wifiIPAddress(serial: device.serial) else {
                Log.error("Wireless: could not determine the device Wi-Fi IP.")
                return
            }
            do {
                try await adb.enableTCPIP(serial: device.serial)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if await adb.connect(host: ip) {
                    Log.info("Wireless connected: \(ip):5555 — you can unplug the cable.")
                    selectedSerial = "\(ip):5555"
                    monitor.refreshNow()
                } else {
                    Log.error("Wireless: connect to \(ip):5555 failed.")
                }
            } catch {
                Log.error("Wireless: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Drag & drop

    func handleDroppedFiles(_ urls: [URL]) {
        guard let serial = selectedSerial else {
            Log.warning("Dropped files ignored: no device selected.")
            return
        }
        for url in urls {
            Task {
                do {
                    if url.pathExtension.lowercased() == "apk" {
                        try await adb.installAPK(at: url.path, serial: serial)
                    } else {
                        try await adb.push(localPath: url.path, serial: serial)
                    }
                } catch {
                    Log.error("Transfer of \(url.lastPathComponent) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Accessibility

    func requestAccessibilityPermission() {
        _ = MirrorWindowController.requestAccessibilityPermission()
        // Re-check shortly after the user (hopefully) grants it.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.accessibilityGranted = MirrorWindowController.hasAccessibilityPermission
        }
    }

    // MARK: - Internals

    private func wireCallbacks() {
        monitor.onDevicesChanged = { [weak self] devices in
            Task { @MainActor in self?.devicesUpdated(devices) }
        }
        scrcpy.onStateChange = { [weak self] state in
            Task { @MainActor in self?.scrcpyStateChanged(state) }
        }
        scrcpy.onRecordingChange = { [weak self] recording in
            Task { @MainActor in self?.isRecording = recording }
        }
    }

    private func devicesUpdated(_ newDevices: [AndroidDevice]) {
        devices = newDevices

        // Keep the current selection if still present; otherwise pick the best.
        if let serial = selectedSerial, newDevices.contains(where: { $0.serial == serial }) {
            // keep
        } else {
            selectedSerial = newDevices.first(where: { $0.state.isReady })?.serial
                ?? newDevices.first?.serial
        }

        updatePhase()

        if let device = selectedDevice {
            switch device.state {
            case .device:
                if preferences.autoMirrorOnConnect && preferences.launchAtPlugIn && !isMirroring {
                    Log.info("Authorized device \(device.displayName) — starting mirror.")
                    startMirror()
                }
            case .unauthorized:
                Log.warning("Device \(device.serial) is unauthorized — accept the prompt on the phone.")
            default:
                break
            }
        }

        if selectedDevice?.state.isReady != true && isMirroring {
            stopMirror()
        }
    }

    private func updatePhase() {
        if devices.isEmpty {
            phase = .noDevice
        } else if let device = selectedDevice {
            switch device.state {
            case .device:       phase = isMirroring ? .mirroring : .ready
            case .unauthorized: phase = .unauthorized
            default:            phase = .detected
            }
        } else {
            phase = .detected
        }
    }

    private func scrcpyStateChanged(_ state: ScrcpyController.State) {
        switch state {
        case .stopped, .starting, .running:
            updatePhase()
        case .failed(let message):
            phase = .error(message)
        }
    }

    /// `~/<directory>/DroidDock/<prefix>-yyyyMMdd-HHmmss.<ext>`, creating the dir.
    private static func outputURL(directory: String, prefix: String, ext: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(directory).appendingPathComponent("DroidDock")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(prefix)-\(formatter.string(from: Date())).\(ext)"
        return dir.appendingPathComponent(name)
    }
}
