import Foundation

/// All interactions with the embedded `adb`: server lifecycle, device listing,
/// input/key events, app install, file push, screenshots, clipboard, and the
/// wireless (TCP/IP) workflow. Stateless beyond the resolved binary path, so it
/// is safe to call from any task; `adb`'s own server serializes requests.
final class ADBController {

    // MARK: Core command runner

    /// Run an arbitrary adb command. Prefixes `-s <serial>` when targeting a
    /// specific device.
    @discardableResult
    func run(_ arguments: [String], serial: String? = nil) async throws -> ProcessResult {
        let adb = try BinaryResolver.adbURL()
        let fullArgs = (serial.map { ["-s", $0] } ?? []) + arguments
        return try await ProcessRunner.run(adb, arguments: fullArgs)
    }

    // MARK: Server lifecycle

    func startServer() async {
        do {
            _ = try await run(["start-server"])
            Log.debug("adb server started")
        } catch {
            Log.error("Failed to start adb server: \(error.localizedDescription)")
        }
    }

    func killServer() async {
        _ = try? await run(["kill-server"])
    }

    // MARK: Device discovery

    func listDevices() async -> [AndroidDevice] {
        guard let result = try? await run(["devices", "-l"]) else { return [] }
        return Self.parseDevices(result.stdout)
    }

    static func parseDevices(_ output: String) -> [AndroidDevice] {
        var devices: [AndroidDevice] = []
        let lines = output.split(whereSeparator: \.isNewline)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("List of devices") { continue }
            if trimmed.hasPrefix("*") { continue }            // daemon chatter
            if trimmed.lowercased().hasPrefix("adb server") { continue }

            let fields = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 2 else { continue }

            var device = AndroidDevice(serial: fields[0], state: DeviceConnectionState(adbToken: fields[1]))
            for field in fields.dropFirst(2) {
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                switch pair[0] {
                case "model":        device.model = pair[1]
                case "product":      device.product = pair[1]
                case "device":       device.device = pair[1]
                case "transport_id": device.transportId = pair[1]
                default:             break
                }
            }
            devices.append(device)
        }
        return devices
    }

    // MARK: Input / keys

    func sendKey(_ key: AndroidKey, serial: String) async {
        _ = try? await run(["shell", "input", "keyevent", String(key.rawValue)], serial: serial)
        Log.debug("keyevent \(key.rawValue) → \(serial)")
    }

    func tap(x: Int, y: Int, serial: String) async {
        _ = try? await run(["shell", "input", "tap", String(x), String(y)], serial: serial)
    }

    func inputText(_ text: String, serial: String) async {
        // `input text` treats spaces specially; %s is the documented escape.
        let escaped = text.replacingOccurrences(of: " ", with: "%s")
        _ = try? await run(["shell", "input", "text", Self.deviceShellQuote(escaped)], serial: serial)
    }

    /// Cycle the device through its four rotations (best-effort; needs WRITE_SETTINGS,
    /// which `adb shell` has). Disables auto-rotate first so the change sticks.
    func rotateDevice(serial: String) async {
        _ = try? await run(["shell", "settings", "put", "system", "accelerometer_rotation", "0"], serial: serial)
        let current = (try? await run(["shell", "settings", "get", "system", "user_rotation"], serial: serial))?
            .trimmedStdout
        let next = ((Int(current ?? "0") ?? 0) + 1) % 4
        _ = try? await run(["shell", "settings", "put", "system", "user_rotation", String(next)], serial: serial)
    }

    // MARK: App install / file push

    func installAPK(at localPath: String, serial: String) async throws {
        let result = try await run(["install", "-r", localPath], serial: serial)
        let combined = (result.stdout + result.stderr).lowercased()
        guard result.succeeded, !combined.contains("failure"), !combined.contains("error:") else {
            throw ProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: result.stderr + result.stdout)
        }
        Log.info("Installed APK: \((localPath as NSString).lastPathComponent)")
    }

    func push(localPath: String, remotePath: String = "/sdcard/Download/", serial: String) async throws {
        let result = try await run(["push", localPath, remotePath], serial: serial)
        guard result.succeeded else {
            throw ProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }
        Log.info("Pushed \((localPath as NSString).lastPathComponent) → \(remotePath)")
    }

    // MARK: Screenshot

    /// Capture a PNG of the device screen via `exec-out screencap -p`
    /// (binary-safe — no base64/CRLF mangling).
    func screenshotPNG(serial: String) async throws -> Data {
        let adb = try BinaryResolver.adbURL()
        let result = try await ProcessRunner.run(
            adb, arguments: ["-s", serial, "exec-out", "screencap", "-p"])
        guard result.succeeded, !result.stdoutData.isEmpty else {
            throw ProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }
        return result.stdoutData
    }

    // MARK: Clipboard (best-effort, complements scrcpy's own sync)

    @discardableResult
    func setDeviceClipboard(_ text: String, serial: String) async -> Bool {
        let result = try? await run(
            ["shell", "cmd", "clipboard", "set-text", Self.deviceShellQuote(text)], serial: serial)
        return result?.succeeded ?? false
    }

    func getDeviceClipboard(serial: String) async -> String? {
        guard let result = try? await run(["shell", "cmd", "clipboard", "get-text"], serial: serial),
              result.succeeded else { return nil }
        let text = result.trimmedStdout
        // Some devices print an error to stdout rather than failing the command.
        if text.isEmpty || text.lowercased().contains("exception") { return nil }
        return text
    }

    // MARK: Wireless (TCP/IP)

    /// Restart adbd on the device in TCP/IP mode, returning the port used.
    func enableTCPIP(port: Int = 5555, serial: String) async throws {
        let result = try await run(["tcpip", String(port)], serial: serial)
        guard result.succeeded else {
            throw ProcessRunnerError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }
    }

    /// Resolve the device's Wi-Fi IPv4 address (tries wlan0, then any inet route).
    func wifiIPAddress(serial: String) async -> String? {
        if let result = try? await run(["shell", "ip", "-o", "-f", "inet", "addr", "show", "wlan0"], serial: serial),
           let ip = Self.firstIPv4(in: result.stdout) {
            return ip
        }
        if let result = try? await run(["shell", "ip", "route"], serial: serial),
           let ip = Self.firstIPv4(in: result.stdout) {
            return ip
        }
        return nil
    }

    /// Connect to a device over TCP/IP. Returns true on success.
    @discardableResult
    func connect(host: String, port: Int = 5555) async -> Bool {
        guard let result = try? await run(["connect", "\(host):\(port)"]) else { return false }
        let text = result.stdout.lowercased()
        return text.contains("connected") && !text.contains("cannot") && !text.contains("failed")
    }

    func disconnect(host: String, port: Int = 5555) async {
        _ = try? await run(["disconnect", "\(host):\(port)"])
    }

    // MARK: - Internals

    /// Quote a string for the *device* shell (adb joins shell args with spaces
    /// and re-parses them on the device). Single-quote and escape inner quotes.
    static func deviceShellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Extract the first dotted-quad IPv4 address from arbitrary text, ignoring
    /// loopback.
    static func firstIPv4(in text: String) -> String? {
        let pattern = #"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let candidate = ns.substring(with: match.range(at: 1))
            if candidate.hasPrefix("127.") || candidate == "0.0.0.0" { continue }
            return candidate
        }
        return nil
    }
}
