import Foundation
import LocalAuthentication

/// Thin wrapper around `LAContext` so the Security tab and the unlock path
/// don't reach into `LocalAuthentication` directly. Three responsibilities:
///
///   * `isAvailable` — whether this Mac *has biometric hardware*. Hardware
///     existence is decoupled from "currently able to evaluate" so the UI
///     surfaces a usable toggle even when the policy check is being picky
///     (ad-hoc signed builds, hardened-runtime quirks, etc.).
///   * `availabilityDetail` — human-readable diagnostic so the Setup tab
///     can explain why a toggle is greyed out instead of leaving the user
///     guessing.
///   * `verify(reason:)` — prompt the user; resolves true on success.
///
/// Touch ID here is a gate in front of the Keychain-cached DEK — we don't
/// derive a key from it. So even if biometry is bypassed, the attacker still
/// needs a live Keychain session (or the passphrase). Classic defence in depth.
@MainActor
enum BiometricGate {

    /// True when this Mac has biometric hardware (Touch ID / Face ID /
    /// Optic ID), regardless of whether `canEvaluatePolicy` currently
    /// succeeds. Earlier code gated on the policy check, but on ad-hoc
    /// signed builds and a few macOS versions that returns false even
    /// when Touch ID is fully set up. Falling back to `biometryType`
    /// keeps the UI honest about hardware presence; `verify(...)` is
    /// where the actual readiness gets re-checked at prompt time.
    static var isAvailable: Bool {
        let ctx = LAContext()
        // Force LAContext to populate biometryType — on macOS the value
        // is only valid after at least one canEvaluatePolicy call.
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return ctx.biometryType != .none
    }

    /// Diagnostic — short string for the UI when the toggle row needs to
    /// explain why it's there but disabled. Reports the actual LAError
    /// code instead of a generic "not available" so the user can act on
    /// it (enrol a finger, unlock biometry, etc.).
    static var availabilityDetail: String {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            switch ctx.biometryType {
            case .touchID:  return "Touch ID is ready."
            case .faceID:   return "Face ID is ready."
            case .opticID:  return "Optic ID is ready."
            case .none:     return "Biometric hardware ready."
            @unknown default: return "Biometric hardware ready."
            }
        }
        // canEvaluatePolicy failed — translate the error code.
        let laErr = (err as? LAError)?.code
        switch laErr {
        case .biometryNotEnrolled:
            return "Touch ID hardware found but no fingerprints are enrolled — add one in System Settings."
        case .biometryLockout:
            return "Touch ID is locked out from too many failed attempts. Use your password to unlock the Mac, then re-try."
        case .biometryNotAvailable:
            return "macOS reports biometry as not available. This can happen on ad-hoc-signed builds; falls back to your device password."
        case .passcodeNotSet:
            return "Set a login password in System Settings to use Touch ID."
        case nil:
            return "Touch ID hardware not detected."
        default:
            return "LocalAuthentication policy check failed (LAError \(laErr?.rawValue ?? -1))."
        }
    }

    /// Prompt the user for Touch ID. Falls back to device password when
    /// biometry is locked out (5 wrong fingers in a row) by using
    /// `deviceOwnerAuthentication` instead of the biometry-only policy.
    /// Returns true on success.
    static func verify(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedReason = reason
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return false
        }
        do {
            return try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
