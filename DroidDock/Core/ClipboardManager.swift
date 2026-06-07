import AppKit

/// Background bidirectional clipboard bridge between the Mac `NSPasteboard` and
/// the Android device.
///
/// This complements scrcpy's own (focus-gated) clipboard forwarding: it keeps
/// the clipboards aligned even when the mirror window isn't focused. The
/// Mac→device direction is reliable; the device→Mac pull uses
/// `adb shell cmd clipboard get-text`, which some Android builds restrict — in
/// that case scrcpy's forwarding remains the path and this simply no-ops.
final class ClipboardManager {
    private let adb: ADBController
    private let queue = DispatchQueue(label: "com.droiddock.clipboard")
    private var timer: DispatchSourceTimer?
    private var serial: String?

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastSyncedText: String?
    private var pullCounter = 0

    init(adb: ADBController) {
        self.adb = adb
    }

    func start(serial: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.serial = serial
            guard self.timer == nil else { return }
            self.lastChangeCount = NSPasteboard.general.changeCount

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
            Log.debug("Clipboard sync started for \(serial)")
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.serial = nil
        }
    }

    // MARK: - Sync loop (runs on `queue`)

    private func tick() {
        guard let serial else { return }

        // ── Mac → device: detect a local clipboard change and push it. ──
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        if changeCount != lastChangeCount {
            lastChangeCount = changeCount
            if let text = pasteboard.string(forType: .string),
               !text.isEmpty, text != lastSyncedText {
                lastSyncedText = text
                Task { [weak self] in
                    guard let self else { return }
                    if await self.adb.setDeviceClipboard(text, serial: serial) {
                        Log.debug("Clipboard → device (\(text.count) chars)")
                    }
                }
            }
        }

        // ── device → Mac: pull every other tick (cheaper), best-effort. ──
        pullCounter += 1
        guard pullCounter % 2 == 0 else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let deviceText = await self.adb.getDeviceClipboard(serial: serial),
                  !deviceText.isEmpty else { return }
            self.queue.async {
                guard deviceText != self.lastSyncedText else { return }
                self.lastSyncedText = deviceText
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(deviceText, forType: .string)
                    self.queue.async { self.lastChangeCount = NSPasteboard.general.changeCount }
                }
                Log.debug("Clipboard ← device (\(deviceText.count) chars)")
            }
        }
    }
}
