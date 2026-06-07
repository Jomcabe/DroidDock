import Foundation

/// The ADB-reported state of a device on the bus.
enum DeviceConnectionState: Equatable {
    case device          // authorized & online
    case unauthorized    // awaiting the on-device "Allow USB debugging?" prompt
    case offline
    case bootloader
    case recovery
    case noPermissions
    case unknown(String)

    init(adbToken: String) {
        switch adbToken.lowercased() {
        case "device":       self = .device
        case "unauthorized": self = .unauthorized
        case "offline":      self = .offline
        case "bootloader":   self = .bootloader
        case "recovery":     self = .recovery
        case "no":           self = .noPermissions   // "no permissions" splits on space
        default:             self = .unknown(adbToken)
        }
    }

    var isReady: Bool { self == .device }

    var displayName: String {
        switch self {
        case .device:        return "Connected"
        case .unauthorized:  return "Unauthorized"
        case .offline:       return "Offline"
        case .bootloader:    return "Bootloader"
        case .recovery:      return "Recovery"
        case .noPermissions: return "No permissions"
        case .unknown(let s): return s.capitalized
        }
    }
}

/// A single Android device as seen by `adb devices -l`.
struct AndroidDevice: Identifiable, Equatable, Hashable {
    let serial: String
    var state: DeviceConnectionState
    var model: String?
    var product: String?
    var device: String?
    var transportId: String?

    var id: String { serial }

    /// `host:port` serials denote a TCP/IP (wireless) connection.
    var isWireless: Bool { serial.contains(":") }

    var displayName: String {
        if let model, !model.isEmpty {
            return model.replacingOccurrences(of: "_", with: " ")
        }
        return serial
    }

    static func == (lhs: AndroidDevice, rhs: AndroidDevice) -> Bool {
        lhs.serial == rhs.serial && lhs.state == rhs.state
    }

    func hash(into hasher: inout Hasher) { hasher.combine(serial) }
}

/// The DroidDock app-level lifecycle phase that the UI binds to.
enum AppPhase: Equatable {
    case noDevice            // bus is empty
    case detected            // USB device seen, ADB not yet authorized/online
    case unauthorized        // device present but debugging not authorized
    case ready               // device authorized; not yet mirroring
    case mirroring           // scrcpy running
    case error(String)

    var headline: String {
        switch self {
        case .noDevice:     return "No device"
        case .detected:     return "Detecting…"
        case .unauthorized: return "Authorize on device"
        case .ready:        return "Ready"
        case .mirroring:    return "Mirroring"
        case .error(let m): return m
        }
    }

    var isMirroring: Bool { self == .mirroring }
}

/// Android `KEYCODE_*` values for the buttons exposed by the control HUD.
enum AndroidKey: Int {
    case home        = 3
    case back        = 4
    case menu        = 82
    case appSwitch   = 187   // recents / overview
    case volumeUp    = 24
    case volumeDown  = 25
    case volumeMute  = 164
    case power       = 26
    case notifications = 83
    case enter       = 66
}
