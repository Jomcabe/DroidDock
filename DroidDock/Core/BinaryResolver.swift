import Foundation

enum BinaryResolverError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name):
            return """
            Embedded binary '\(name)' was not found in the app bundle. \
            Run `make setup` (scripts/fetch-binaries.sh) before building so the \
            adb/scrcpy toolchain is provisioned into Resources/vendor.
            """
        }
    }
}

/// Resolves the embedded adb/scrcpy toolchain and the environment used to spawn
/// it. The binaries live in `…/Contents/Resources/vendor`, copied there by the
/// build's pre-build phase. Resolution uses `Bundle.main` so the app is portable
/// to any Mac without external installs.
enum BinaryResolver {
    private static let vendorDir = "vendor"
    private static let scrcpyDir = "vendor/scrcpy"

    /// `…/Contents/Resources/vendor/adb`
    static func adbURL() throws -> URL {
        try resolve(resource: "adb", ofType: nil, inDirectory: vendorDir)
    }

    /// `…/Contents/Resources/vendor/scrcpy/scrcpy`
    static func scrcpyURL() throws -> URL {
        try resolve(resource: "scrcpy", ofType: nil, inDirectory: scrcpyDir)
    }

    /// `…/Contents/Resources/vendor/scrcpy/scrcpy-server`
    static func scrcpyServerURL() throws -> URL {
        try resolve(resource: "scrcpy-server", ofType: nil, inDirectory: scrcpyDir)
    }

    /// Environment for spawning scrcpy: point it at *our* embedded adb and server
    /// push, never anything on the system `PATH`.
    static func scrcpyEnvironment() throws -> [String: String] {
        [
            "ADB": try adbURL().path,
            "SCRCPY_SERVER_PATH": try scrcpyServerURL().path,
        ]
    }

    /// Confirms the whole toolchain is present; throws a descriptive error if not.
    @discardableResult
    static func validateToolchain() throws -> (adb: URL, scrcpy: URL, server: URL) {
        (try adbURL(), try scrcpyURL(), try scrcpyServerURL())
    }

    // MARK: - Internals

    private static func resolve(resource: String, ofType type: String?, inDirectory dir: String) throws -> URL {
        // Faithful to the brief: Bundle.main.path(forResource:ofType:inDirectory:).
        guard let path = Bundle.main.path(forResource: resource, ofType: type, inDirectory: dir) else {
            throw BinaryResolverError.missing("\(dir)/\(resource)")
        }
        let url = URL(fileURLWithPath: path)
        ensureExecutable(at: url)
        return url
    }

    /// Belt-and-suspenders: make sure the executable bit survived bundle copying
    /// and code signing (resources are not guaranteed to retain `+x`).
    private static func ensureExecutable(at url: URL) {
        let fm = FileManager.default
        guard
            let attrs = try? fm.attributesOfItem(atPath: url.path),
            let perm = attrs[.posixPermissions] as? NSNumber
        else { return }

        let mode = perm.uint16Value
        if mode & 0o111 == 0 {
            try? fm.setAttributes(
                [.posixPermissions: NSNumber(value: mode | 0o755)],
                ofItemAtPath: url.path
            )
        }
    }
}
