import Foundation

/// Reads the build-stamped version values out of the running bundle so the
/// "About" screen can show them without requiring a regenerated source file.
/// `build-app.sh` writes the real values into the BUILT bundle's Info.plist
/// after `ditto`. The placeholders in `Info.plist` are deliberately low —
/// seeing "0.0.0 (0.unknown)" in the UI is the signal that the build wrapper
/// was bypassed.
enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.unknown"
    }
    static var display: String { "v\(marketing) (\(build))" }
}
