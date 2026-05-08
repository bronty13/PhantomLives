import Foundation

/// Version strings for the running app, read once from the bundled
/// Info.plist. The real values are stamped into the bundle by
/// `build-app.sh` post-ditto — this file stays pristine in git so
/// each build no longer pollutes the working tree with phantom diffs.
///
/// If you see "0.0.0 (0.unknown)" in the UI, you ran xcodebuild
/// directly instead of `./build-app.sh`.
enum AppVersion {
    /// User-facing "1.0.124" (CFBundleShortVersionString).
    static let marketing: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }()

    /// Build identifier "124.cd41aa8" (CFBundleVersion) — commit count + short SHA.
    static let build: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.unknown"
    }()

    /// Combined display for places that have room: "v1.0.124 (124.cd41aa8)".
    static let display: String = {
        "v\(marketing) (\(build))"
    }()
}
