import SwiftUI

/// Full-window screen lock shown when `AppState.appLocked` is true.
/// The user re-authenticates with Touch ID / device password via
/// `VaultAuthService`; on success the screen dismisses and the
/// regular UI returns. The keystore's passphrase-mode lock (if a
/// passphrase is set) is handled separately by `KeyStore` — the
/// Settings → Security tab is where the user enters the passphrase
/// after this screen dismisses.
///
/// The view auto-invokes the Touch ID prompt on appear so the user
/// doesn't have to click anything in the common case; a button is
/// also offered for the failure path (cancelled, fingerprint
/// mis-read, etc.) so the user can retry without leaving the screen.
///
/// Polish layer (2026-05-20):
/// - `LockScreenError` enum types each failure mode with its own
///   copy + SF Symbol so the user gets a specific cue rather than a
///   generic "cancelled or failed" caption.
/// - After 3 consecutive failures the auto-prompt suppresses itself
///   (next prompt requires an explicit Unlock-button tap), so the
///   user has time to read the error instead of getting blasted
///   with the system dialog again.
/// - After 5 consecutive failures a 30 s cooldown engages — the
///   Unlock button disables and a countdown caption appears. This
///   is in-memory only (quitting the app resets the counter); a
///   bad actor with quit-relaunch access has bigger problems than
///   the lock screen anyway.
/// - When biometry-only mode is on, the screen surfaces a help
///   line explaining how to recover (quit + relaunch + Settings)
///   so a stuck Touch ID doesn't leave the user with no path
///   forward.
struct AppLockScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var attempting = false
    @State private var lastError: LockScreenError?
    @State private var failureCount: Int = 0
    @State private var cooldownRemaining: Int = 0
    @State private var cooldownTimer: Timer?

    /// After this many consecutive failures, stop auto-prompting on
    /// appear/return so the user can read the error.
    private let suppressAutoPromptAfter: Int = 3

    /// After this many consecutive failures, gate the Unlock button
    /// behind a cooldown. Limits a casual shoulder-surfer guessing
    /// the Mac password.
    private let cooldownAfterFailures: Int = 5
    private let cooldownSeconds: Int = 30

    /// Suppress the auto-prompt on appear once the failure count
    /// crosses the threshold. The user can still tap Unlock to
    /// retry.
    private var autoPromptSuppressed: Bool {
        failureCount >= suppressAutoPromptAfter
    }

    private var cooldownActive: Bool {
        cooldownRemaining > 0
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Group {
                if let error = lastError {
                    Image(systemName: error.symbol)
                        .foregroundStyle(error.symbolColor)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tint)
                }
            }
            .font(.system(size: 56, weight: .light))
            Text("PurpleLife is locked")
                .font(.title2).bold()
            Text(promptCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if let error = lastError {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(error.symbolColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            if cooldownActive {
                Text("Too many attempts. Wait \(cooldownRemaining) second\(cooldownRemaining == 1 ? "" : "s") and try again.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button {
                Task { await authenticate() }
            } label: {
                Label("Unlock", systemImage: "touchid")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(attempting || cooldownActive)
            if appState.keyStore.hasPassphrase {
                Text("Your data also has a passphrase. After this screen dismisses, open Settings → Security and enter your passphrase to fully unlock.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 6)
            }
            if autoPromptSuppressed {
                stuckHelpText
                    .padding(.top, 10)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Auto-prompt the moment the screen appears, unless the
            // user has already failed enough times to earn a moment
            // of quiet. Once suppressed, only the explicit Unlock
            // button re-enters the prompt loop.
            if !autoPromptSuppressed {
                Task { await authenticate() }
            }
        }
        .onDisappear {
            cooldownTimer?.invalidate()
            cooldownTimer = nil
        }
    }

    /// Tailored hint shown after the user has hit the auto-prompt
    /// suppression threshold. Biometry-only users get the specific
    /// quit-and-relaunch recovery; everyone else gets the
    /// generic "try again" framing.
    @ViewBuilder
    private var stuckHelpText: some View {
        if appState.settings.biometryOnlyMode {
            VStack(spacing: 4) {
                Text("Stuck without Touch ID?")
                    .font(.caption.weight(.semibold))
                Text("Quit PurpleLife (⌘Q), relaunch, then open Settings → Security to disable biometry-only mode. Your data isn't touched.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 50)
            }
        } else {
            Text("If Touch ID keeps failing, type your Mac login password when the system prompt asks for it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 50)
        }
    }

    private var promptCaption: String {
        if appState.settings.biometryOnlyMode {
            return "Re-authenticate with Touch ID to continue. Biometry-only mode is on — Mac password fallback is disabled."
        }
        return "Re-authenticate with Touch ID or your device password to continue."
    }

    private func authenticate() async {
        guard !attempting else { return }
        guard !cooldownActive else { return }
        attempting = true
        defer { attempting = false }
        let result = await VaultAuthService.authenticate(
            reason: "Unlock PurpleLife",
            biometryOnly: appState.settings.biometryOnlyMode
        )
        switch result {
        case .success:
            lastError = nil
            failureCount = 0
            cooldownRemaining = 0
            cooldownTimer?.invalidate()
            cooldownTimer = nil
            appState.unlockApp()
        case .userCancelled:
            lastError = .cancelled
            failureCount += 1
            maybeStartCooldown()
        case .failed(let detail):
            lastError = appState.settings.biometryOnlyMode
                ? .biometryFailed(detail)
                : .failed(detail)
            failureCount += 1
            maybeStartCooldown()
        case .unavailable(let detail):
            lastError = appState.settings.biometryOnlyMode
                ? .biometryUnavailable(detail)
                : .unavailable(detail)
            failureCount += 1
            maybeStartCooldown()
        }
    }

    /// Engage the cooldown after enough failures. Idempotent — calling
    /// again while a cooldown is running is a no-op (the user got an
    /// extra failure during the cooldown window; the existing timer
    /// keeps counting down).
    private func maybeStartCooldown() {
        guard failureCount >= cooldownAfterFailures else { return }
        guard cooldownTimer == nil else { return }
        cooldownRemaining = cooldownSeconds
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            Task { @MainActor in
                if cooldownRemaining > 0 { cooldownRemaining -= 1 }
                if cooldownRemaining <= 0 {
                    timer.invalidate()
                    cooldownTimer = nil
                    // Don't auto-prompt when the cooldown ends — the
                    // user is in a "stop blasting me" state already.
                    // They tap Unlock when ready.
                }
            }
        }
    }
}

/// Typed lock-screen error state. Each case carries its own user-
/// facing copy and SF Symbol so the rendered screen tells the user
/// what specifically went wrong, not just "something failed". Kept
/// here (in the view file) rather than in a shared models file
/// because no other view consumes this; promoting it would just
/// add an import.
enum LockScreenError: Equatable {
    /// User explicitly cancelled the system auth dialog.
    case cancelled
    /// Generic auth failure (wrong password too many times in
    /// non-biometry mode, biometry mis-read with password fallback).
    case failed(String)
    /// Auth policy unavailable on this Mac — extremely rare. Most
    /// common when a non-biometry Mac has no login password configured.
    case unavailable(String)
    /// Biometry-only mode failed (fingerprint mis-read, biometry
    /// lockout from repeated failure, biometry temporarily
    /// unavailable). Distinct from `.failed` so the polish copy can
    /// nudge the user toward the quit-and-disable recovery.
    case biometryFailed(String)
    /// Biometry-only mode requested but the Mac has no enrolled
    /// fingerprint. Distinct from `.unavailable` so we can specifically
    /// tell the user to disable biometry-only mode.
    case biometryUnavailable(String)

    var symbol: String {
        switch self {
        case .cancelled:           return "lock.fill"
        case .failed:              return "exclamationmark.triangle.fill"
        case .unavailable:         return "lock.slash.fill"
        case .biometryFailed:      return "touchid"
        case .biometryUnavailable: return "lock.slash.fill"
        }
    }

    var symbolColor: Color {
        switch self {
        case .cancelled:           return .secondary
        case .failed:              return .orange
        case .unavailable:         return .red
        case .biometryFailed:      return .orange
        case .biometryUnavailable: return .red
        }
    }

    var message: String {
        switch self {
        case .cancelled:
            return "Authentication cancelled. Tap Unlock to try again."
        case .failed(let detail):
            return "Authentication failed: \(detail)"
        case .unavailable(let detail):
            return "Authentication unavailable: \(detail). Add a Touch ID fingerprint or a login password in System Settings."
        case .biometryFailed(let detail):
            return "Touch ID failed: \(detail). Try again, or quit and disable biometry-only mode in Settings → Security."
        case .biometryUnavailable(let detail):
            return "Touch ID isn't configured on this Mac — biometry-only mode can't authenticate. \(detail). Quit PurpleLife, relaunch, and turn off biometry-only mode from Settings → Security."
        }
    }
}
