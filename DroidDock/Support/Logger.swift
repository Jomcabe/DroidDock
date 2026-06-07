import Foundation
import os

/// Severity for both the unified-logging sink and the in-app log view.
enum LogLevel: String, CaseIterable {
    case debug, info, warning, error

    var symbol: String {
        switch self {
        case .debug:   return "ladybug"
        case .info:    return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error:   return "xmark.octagon"
        }
    }

    var osType: OSLogType {
        switch self {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .default
        case .error:   return .error
        }
    }
}

/// A single line in the in-app log console.
struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let message: String
}

/// Observable ring buffer of recent log lines, surfaced in the UI, and a mirror
/// into the unified logging system (`os.Logger`).
final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var entries: [LogEntry] = []

    private let osLog = Logger(subsystem: "com.droiddock.DroidDock", category: "app")
    private let maxEntries = 600

    private init() {}

    /// Thread-safe: appends on the main thread (for SwiftUI) and mirrors to os_log.
    func log(_ message: String, level: LogLevel = .info) {
        osLog.log(level: level.osType, "\(message, privacy: .public)")
        let entry = LogEntry(date: Date(), level: level, message: message)
        if Thread.isMainThread {
            append(entry)
        } else {
            DispatchQueue.main.async { [weak self] in self?.append(entry) }
        }
    }

    func clear() {
        if Thread.isMainThread { entries.removeAll() }
        else { DispatchQueue.main.async { [weak self] in self?.entries.removeAll() } }
    }

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}

/// Terse, call-site-friendly logging facade.
enum Log {
    static func debug(_ message: @autoclosure () -> String)   { AppLog.shared.log(message(), level: .debug) }
    static func info(_ message: @autoclosure () -> String)    { AppLog.shared.log(message(), level: .info) }
    static func warning(_ message: @autoclosure () -> String) { AppLog.shared.log(message(), level: .warning) }
    static func error(_ message: @autoclosure () -> String)   { AppLog.shared.log(message(), level: .error) }
}
