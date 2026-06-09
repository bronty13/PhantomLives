import Foundation
import Photos
import AppKit
import CoreServices   // AEDeterminePermissionToAutomateTarget, typeWildCard, errAEEvent*
import PurpleAtticCore

/// State of a single TCC grant.
enum GrantState: Equatable {
    case granted
    case denied
    case notDetermined
    case unknown

    var isGranted: Bool { self == .granted }
}

/// The three macOS privacy grants PurpleAttic needs to run cleanly:
///  - **Full Disk Access** — so osxphotos can read the `.photoslibrary` bundle.
///  - **Photos Automation** (Apple Events → Photos) — so `--download-missing` / edited-render
///    exports can drive Photos.app. Its absence is exactly what caused the "AppleScript export
///    failed 10 consecutive times, restarting Photos app" thrash.
///  - **Photos Library** — PhotoKit access (used by the guarded purge, requested up front).
struct PermissionsReport: Equatable {
    var fullDiskAccess: GrantState = .unknown
    var photosAutomation: GrantState = .unknown
    var photosLibrary: GrantState = .unknown

    /// The bar for allowing a dry run or archive: all three present.
    var allGranted: Bool {
        fullDiskAccess == .granted && photosAutomation == .granted && photosLibrary == .granted
    }

    /// The grants still missing, in the order the UI lists them.
    var missing: [PermissionKind] {
        var out: [PermissionKind] = []
        if fullDiskAccess != .granted { out.append(.fullDiskAccess) }
        if photosAutomation != .granted { out.append(.photosAutomation) }
        if photosLibrary != .granted { out.append(.photosLibrary) }
        return out
    }
}

enum PermissionKind: String, CaseIterable, Identifiable {
    case fullDiskAccess
    case photosAutomation
    case photosLibrary
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullDiskAccess:   return "Full Disk Access"
        case .photosAutomation: return "Photos Automation"
        case .photosLibrary:    return "Photos Library"
        }
    }

    var why: String {
        switch self {
        case .fullDiskAccess:   return "Lets osxphotos read your Photos library."
        case .photosAutomation: return "Lets the archive drive Photos to download/export images (avoids the restart-loop)."
        case .photosLibrary:    return "PhotoKit access (required by the guarded purge)."
        }
    }

    /// The System Settings privacy pane deep-link.
    var settingsURL: URL {
        let anchor: String
        switch self {
        case .fullDiskAccess:   anchor = "Privacy_AllFiles"
        case .photosAutomation: anchor = "Privacy_Automation"
        case .photosLibrary:    anchor = "Privacy_Photos"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

/// Queries and (where the API allows) requests the three grants. Read-only checks are cheap
/// and side-effect-free; the request paths surface the system consent prompts.
enum PermissionsService {

    static let photosBundleID = "com.apple.Photos"

    /// A full read-only snapshot (no prompts).
    static func current(libraryPath: String? = nil) -> PermissionsReport {
        PermissionsReport(
            fullDiskAccess: Permissions.fullDiskAccessLikely(libraryPath: libraryPath) ? .granted : .denied,
            photosAutomation: photosAutomation(prompt: false),
            photosLibrary: photosLibrary()
        )
    }

    // MARK: Photos Automation (Apple Events)

    /// Determine — and optionally request — permission to send Apple Events to Photos.
    /// `prompt: true` shows the system "PurpleAttic wants to control Photos" dialog. Apple's
    /// API can hang if the target app isn't frontmost, so callers should launch/activate
    /// Photos first and invoke the prompting form **off the main thread**.
    static func photosAutomation(prompt: Bool) -> GrantState {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: photosBundleID).aeDesc else {
            return .unknown
        }
        let status = AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, prompt)
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        default:
            return .unknown   // e.g. procNotFound (-600) when Photos isn't running
        }
    }

    /// Launch/activate Photos, then trigger the Automation consent prompt off-main (the API
    /// can block). Reports the resulting state back on the main queue.
    static func requestPhotosAutomation(_ completion: @escaping (GrantState) -> Void) {
        let photosURL = URL(fileURLWithPath: "/System/Applications/Photos.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: photosURL, configuration: config) { _, _ in
            DispatchQueue.global(qos: .userInitiated).async {
                let state = photosAutomation(prompt: true)
                DispatchQueue.main.async { completion(state) }
            }
        }
    }

    // MARK: Photos Library (PhotoKit)

    static func photosLibrary() -> GrantState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: return .granted
        case .denied, .restricted:  return .denied
        case .notDetermined:        return .notDetermined
        @unknown default:           return .unknown
        }
    }

    static func requestPhotosLibrary(_ completion: @escaping (GrantState) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
            DispatchQueue.main.async { completion(photosLibrary()) }
        }
    }

    // MARK: Settings

    static func openSettings(for kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
