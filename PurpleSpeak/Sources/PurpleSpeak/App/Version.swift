import Foundation

/// Build-stamped version. `build-app.sh` rewrites the two string literals
/// below with git-derived numbers (`1.0.<commit-count>` /
/// `<count>.<short-sha>`) at package time, and also writes the same values
/// into the bundle's Info.plist. The source values here are placeholders so
/// `git status` stays clean between builds.
enum AppVersion {
    static let marketing = "0.0.0"
    static let build = "0.unknown"
    static let display = "v\(AppVersion.marketing) (\(AppVersion.build))"

    /// Prefer the bundle's Info.plist (the source of truth at runtime) and
    /// fall back to the compiled-in literals for `swift run` / test contexts.
    static var resolved: String {
        let m = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "v\(m ?? marketing) (\(b ?? build))"
    }
}
