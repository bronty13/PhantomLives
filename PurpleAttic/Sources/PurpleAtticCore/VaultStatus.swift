import Foundation

/// Readiness of the Cryptomator cloud vault. A Cryptomator vault, when unlocked, appears as
/// a mounted, writable directory at the path the user configured; when locked it's absent.
/// The engine skips the cloud copy (without failing the run) when the vault isn't ready;
/// the UI shows the live status so the user knows whether the 3rd copy is current.
public enum VaultStatus: Sendable, Equatable {
    case notConfigured     // no vault path set — cloud copy intentionally off
    case notMounted        // path set but the vault is locked / not mounted
    case ready             // mounted + writable; the cloud copy will run

    public var label: String {
        switch self {
        case .notConfigured: return "Not configured"
        case .notMounted:    return "Locked / not mounted"
        case .ready:         return "Unlocked — ready"
        }
    }

    public var isReady: Bool { self == .ready }

    /// Inspect the configured vault path.
    public static func check(path: String?) -> VaultStatus {
        guard let path, !path.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .notConfigured
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        guard exists else { return .notMounted }
        return fm.isWritableFile(atPath: path) ? .ready : .notMounted
    }
}
