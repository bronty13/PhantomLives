import Foundation

enum AppVersion {
    static let marketing: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }()

    static let build: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.unknown"
    }()

    static let display: String = "v\(marketing) (\(build))"
}
