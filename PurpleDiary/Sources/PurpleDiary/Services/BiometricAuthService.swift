import Foundation
import LocalAuthentication

/// Touch ID / device-password gate for the app lock. Wraps a single
/// `LAContext` per call — a fresh context each time so a successful auth
/// doesn't persist past the call site and a denied prompt resets cleanly on
/// retry.
///
/// Policy is picked per-call from `policy(biometryOnly:)`:
///
/// - `false` (default) → `.deviceOwnerAuthentication`: Touch ID when
///   available, falling back automatically to the user's Mac login password.
///   The safe default — a Mac without Touch ID can still unlock.
/// - `true` → `.deviceOwnerAuthenticationWithBiometrics`: Touch ID only, no
///   fallback. Users who enable this in Settings → Security require a working
///   biometry sensor; recovery if the sensor breaks is to quit, relaunch, and
///   disable the toggle (the lock state is runtime-only, so the next launch is
///   unlocked unless lock-on-launch demands the passphrase).
@MainActor
enum BiometricAuthService {

    enum AuthResult: Equatable {
        case success
        case userCancelled
        case unavailable(String) // no biometrics + no passcode (bare Mac)
        case failed(String)      // wrong password too many times, etc.
    }

    /// Pure policy selection, extracted so unit tests can verify the mapping
    /// without touching `LAContext` (which needs a real device prompt and has
    /// no XCTest hook). Keep it standalone — it's the testability seam.
    static func policy(biometryOnly: Bool) -> LAPolicy {
        biometryOnly
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
    }

    /// Prompt the user to authenticate. The reason string is shown in the
    /// system dialog ("PurpleDiary is trying to <reason>"); keep it short and
    /// verb-y. Returns on the main actor.
    static func authenticate(reason: String, biometryOnly: Bool = false) async -> AuthResult {
        let context = LAContext()
        context.localizedFallbackTitle = biometryOnly ? "" : "Use password"
        context.localizedCancelTitle = "Cancel"

        let chosenPolicy = policy(biometryOnly: biometryOnly)

        var policyError: NSError?
        guard context.canEvaluatePolicy(chosenPolicy, error: &policyError) else {
            return .unavailable(policyError?.localizedDescription
                ?? "Authentication not available on this device.")
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
                    default:
                        continuation.resume(returning: .failed(
                            evalError?.localizedDescription ?? "Authentication failed."))
                    }
                }
            }
        }
    }

    /// Convenience: is any biometry/passcode policy available on this Mac?
    /// Used by the Security tab to pre-flight the biometry-only toggle.
    static func canAuthenticate(biometryOnly: Bool) -> Bool {
        LAContext().canEvaluatePolicy(policy(biometryOnly: biometryOnly), error: nil)
    }
}
