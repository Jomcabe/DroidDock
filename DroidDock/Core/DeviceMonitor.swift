import Foundation
import IOKit
import IOKit.usb

/// Low-level USB attach/detach watcher built on IOKit notifications. Fires
/// `onChange` whenever a USB device is added or removed, on a private dispatch
/// queue. DroidDock uses it as a *trigger* to rescan adb immediately, rather
/// than relying solely on polling.
final class USBWatcher {
    private let onChange: () -> Void
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private let queue = DispatchQueue(label: "com.droiddock.usbwatcher")

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        guard notifyPort == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            Log.warning("Could not create IOKit notification port; USB auto-detect disabled.")
            return
        }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, queue)

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        // C-compatible callback: bounces back to the instance and drains+arms
        // the iterator (draining is *required* to re-arm IOKit notifications).
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<USBWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.drain(iterator)
            watcher.onChange()
        }

        // IOServiceMatching returns a +1 dictionary that each call consumes, so
        // build a fresh one for the matched and terminated notifications.
        let matchedResult = IOServiceAddMatchingNotification(
            port, kIOMatchedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            callback, opaqueSelf, &addedIterator)
        if matchedResult == KERN_SUCCESS { drain(addedIterator) }

        let terminatedResult = IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            callback, opaqueSelf, &removedIterator)
        if terminatedResult == KERN_SUCCESS { drain(removedIterator) }

        if matchedResult != KERN_SUCCESS && terminatedResult != KERN_SUCCESS {
            Log.warning("IOKit USB notifications unavailable; falling back to polling only.")
        } else {
            Log.debug("USB watcher armed")
        }
    }

    func stop() {
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
    }

    /// Consume all pending items in an iterator. For a freshly-registered
    /// notification this also arms it; thereafter it acknowledges the event.
    private func drain(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}

/// Combines the USB watcher with a steady adb poll to produce an authoritative,
/// de-duplicated stream of device-list changes. The poll is the reliable driver
/// (it also catches wireless connections and authorization-state transitions);
/// the USB watcher makes plug-in feel instantaneous.
final class DeviceMonitor {
    private let adb: ADBController
    private var usb: USBWatcher?
    private var pollTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.droiddock.devicemonitor")
    private var lastSnapshot: [AndroidDevice] = []
    private var isScanning = false

    /// Invoked on the monitor's private queue when the device set changes.
    /// Consumers must hop to the main actor before touching UI state.
    var onDevicesChanged: (([AndroidDevice]) -> Void)?

    init(adb: ADBController) {
        self.adb = adb
    }

    func start(pollInterval: TimeInterval = 2.0) {
        Task { await adb.startServer() }

        usb = USBWatcher { [weak self] in self?.scanSoon() }
        usb?.start()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.scan() }
        timer.resume()
        pollTimer = timer

        scanSoon(after: 0.2)
    }

    func stop() {
        usb?.stop()
        usb = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// Force an immediate rescan (e.g. right after a wireless connect).
    func refreshNow() { scanSoon(after: 0.0) }

    // MARK: - Internals

    private func scanSoon(after delay: TimeInterval = 0.4) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scan() }
    }

    private func scan() {
        guard !isScanning else { return }   // guard on the serial queue
        isScanning = true
        Task { [weak self] in
            guard let self else { return }
            let devices = await self.adb.listDevices()
            self.queue.async {
                self.isScanning = false
                guard devices != self.lastSnapshot else { return }
                self.lastSnapshot = devices
                self.onDevicesChanged?(devices)
            }
        }
    }
}
