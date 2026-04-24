import Foundation

/// Read the bundle's version strings once at startup so UI views don't go
/// hunting through `Bundle.main.infoDictionary` at render time. Values come
/// from the Info.plist that build-app.sh stamps with git-derived strings.
enum AppVersion {
    /// User-facing "1.0.42" (CFBundleShortVersionString).
    static let short: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }()

    /// Build identifier "42.abc1234" (CFBundleVersion) — commit count + short SHA.
    static let build: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }()

    /// Combined display for places that have room: "1.0.42 (42.abc1234)".
    static let display: String = {
        "\(short) (\(build))"
    }()
}
