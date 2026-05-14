import Foundation
import LocalAuthentication

/// Touch ID / device-password gate for the Vault section. Wraps a
/// single `LAContext` per call — fresh context each time so a successful
/// auth doesn't persist past the call site and a denied prompt resets
/// cleanly on retry.
///
/// `.deviceOwnerAuthentication` is the policy: Touch ID when available,
/// otherwise falls back automatically to the user's Mac login password.
/// We deliberately don't use `.deviceOwnerAuthenticationWithBiometrics`
/// because that has no fallback when biometrics fail or aren't
/// configured — leaving users with a Touch ID-less Mac unable to open
/// the Vault at all.
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

    /// Prompt the user to authenticate. The reason string is shown in
    /// the system dialog ("PurpleLife is trying to <reason>"); keep it
    /// short and verb-y. Returns on the main actor.
    static func authenticate(reason: String) async -> AuthResult {
        let context = LAContext()
        context.localizedFallbackTitle = "Use password"
        context.localizedCancelTitle = "Cancel"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // No biometrics AND no device passcode configured — vanishingly
            // rare on macOS, but possible on a fresh local-account Mac that
            // skipped passcode setup. The Vault is effectively unprotectable
            // in that state; surface it rather than silently letting the
            // user in (which would defeat the gate's whole purpose).
            return .unavailable(policyError?.localizedDescription ?? "Authentication not available on this device.")
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
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
