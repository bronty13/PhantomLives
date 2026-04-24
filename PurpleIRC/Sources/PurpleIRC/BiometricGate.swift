import Foundation
import LocalAuthentication

/// Thin wrapper around `LAContext` so the Security tab and the unlock path
/// don't reach into `LocalAuthentication` directly. Two responsibilities:
///
///   * `isAvailable` — whether this Mac has a usable biometric policy.
///   * `verify(reason:)` — prompt the user; resolves true on success, false on
///     cancel / wrong finger / unavailable device.
///
/// Touch ID here is a gate in front of the Keychain-cached DEK — we don't
/// derive a key from it. So even if biometry is bypassed, the attacker still
/// needs a live Keychain session (or the passphrase). Classic defence in depth.
@MainActor
enum BiometricGate {

    /// True when the system has at least one biometric policy ready. On
    /// Intel Macs without Touch ID this is false and the UI degrades to
    /// passphrase-only.
    static var isAvailable: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                     error: &err)
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
