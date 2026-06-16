import Foundation

/// App version surfaced in the UI. The authoritative version is the git-derived
/// `CFBundleShortVersionString` written by build-app.sh; this reads it back from the bundle
/// at runtime (falling back to a dev string when run outside a bundle, e.g. unit tests).
enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    static var displayString: String { "PurplePeek \(short) (\(build))" }
}
