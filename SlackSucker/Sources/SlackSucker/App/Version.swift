import Foundation

/// Version strings sourced from the bundle's Info.plist. `build-app.sh`
/// stamps `CFBundleShortVersionString` and `CFBundleVersion` at build
/// time, so these read whatever the most recent commit produced.
///
/// When running via `swift run` (no .app wrapper), the keys are absent
/// and the strings fall back to "dev".
enum AppVersion {
    static let marketing: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    static let build: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"

    static var combined: String { "\(marketing) (\(build))" }
}
