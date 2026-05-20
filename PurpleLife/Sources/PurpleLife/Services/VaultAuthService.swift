import Foundation
import LocalAuthentication

/// Touch ID / device-password gate for the Vault section. Wraps a
/// single `LAContext` per call — fresh context each time so a successful
/// auth doesn't persist past the call site and a denied prompt resets
/// cleanly on retry.
///
/// Policy is picked per-call from `policy(biometryOnly:)`:
///
/// - `false` (default) → `.deviceOwnerAuthentication`: Touch ID when
///   available, falling back automatically to the user's Mac login
///   password. This is the safe-by-default mode — a Mac without Touch
///   ID can still open the Vault.
/// - `true` → `.deviceOwnerAuthenticationWithBiometrics`: Touch ID only,
///   no fallback. Users who enable this in Settings → Security require
///   a working biometry sensor; recovery if the sensor breaks is to
///   quit the app, relaunch, and disable the toggle from Settings (the
///   `appLocked` state is runtime-only, so the next launch is unlocked
///   by default).
///
/// The Vault auth is intentionally session-scoped: `AppState.vaultRevealed`
/// is runtime-only and resets to `false` on every launch, so this
/// service is called once per unveil. There's no token caching, no
/// expiry timer — the user explicitly locks via the menu or the app
/// restart locks for them.
@MainActor
enum VaultAuthService {

    enum AuthResult: Equatable {
        case success
        case userCancelled
        case unavailable(String) // no biometrics + no passcode (extreme; bare Mac)
        case failed(String)      // wrong password too many times, etc.
    }

    /// Pure policy selection for `authenticate(reason:biometryOnly:)`.
    /// Extracted so unit tests can verify the mapping without touching
    /// `LAContext` (which requires a real device prompt and has no
    /// XCTest hook). Do not fold this back into the call site —
    /// keeping it standalone is the testability seam.
    static func policy(biometryOnly: Bool) -> LAPolicy {
        biometryOnly
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
    }

    /// Prompt the user to authenticate. The reason string is shown in
    /// the system dialog ("PurpleLife is trying to <reason>"); keep it
    /// short and verb-y. Returns on the main actor.
    ///
    /// `biometryOnly` plumbs `AppSettings.biometryOnlyMode` through to
    /// the policy choice. Pass it explicitly at every call site rather
    /// than reading a singleton — keeps the call graph local and the
    /// function easy to test.
    static func authenticate(reason: String, biometryOnly: Bool = false) async -> AuthResult {
        let context = LAContext()
        context.localizedFallbackTitle = biometryOnly ? "" : "Use password"
        context.localizedCancelTitle = "Cancel"

        let chosenPolicy = policy(biometryOnly: biometryOnly)

        var policyError: NSError?
        guard context.canEvaluatePolicy(chosenPolicy, error: &policyError) else {
            // Two reasons this fires:
            // (a) Non-biometry mode on a fresh local-account Mac that
            //     skipped passcode setup — vanishingly rare. The Vault is
            //     effectively unprotectable in that state; surface it
            //     rather than silently letting the user in.
            // (b) Biometry-only mode on a Mac without an enrolled Touch
            //     ID fingerprint. The Settings → Security toggle runs
            //     this same check on tab-appear and disables itself with
            //     a caption, so production hits to this path should be
            //     rare (e.g. fingerprint removed while the app was
            //     running). The user's recovery is quit → relaunch →
            //     toggle off.
            return .unavailable(policyError?.localizedDescription ?? "Authentication not available on this device.")
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(chosenPolicy, localizedReason: reason) { success, evalError in
                Task { @MainActor in
                    if success {
                        continuation.resume(returning: .success)
                        return
                    }
                    let laError = evalError as? LAError
                    switch laError?.code {
                    case .userCancel, .appCancel, .systemCancel:
                        continuation.resume(returning: .userCancelled)
                    case .authenticationFailed, .userFallback, .biometryLockout, .biometryNotAvailable, .biometryNotEnrolled:
                        continuation.resume(returning: .failed(evalError?.localizedDescription ?? "Authentication failed."))
                    default:
                        continuation.resume(returning: .failed(evalError?.localizedDescription ?? "Authentication failed."))
                    }
                }
            }
        }
    }
}
