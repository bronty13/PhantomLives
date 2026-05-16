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
struct AppLockScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var attempting = false
    @State private var lastErrorDetail: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("PurpleLife is locked")
                .font(.title2).bold()
            Text("Re-authenticate with Touch ID or your device password to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if let detail = lastErrorDetail {
                Text(detail)
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
            .disabled(attempting)
            if appState.keyStore.hasPassphrase {
                Text("Your data also has a passphrase. After this screen dismisses, open Settings → Security and enter your passphrase to fully unlock.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 6)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Auto-prompt the moment the screen appears. If the OS
            // denies (no biometrics + no passcode set) the user lands
            // on the button to retry; the unavailable case is rare on
            // a Mac that's even able to run PurpleLife.
            Task { await authenticate() }
        }
    }

    private func authenticate() async {
        guard !attempting else { return }
        attempting = true
        defer { attempting = false }
        let result = await VaultAuthService.authenticate(reason: "Unlock PurpleLife")
        switch result {
        case .success:
            lastErrorDetail = nil
            appState.unlockApp()
        case .userCancelled, .failed:
            lastErrorDetail = "Authentication cancelled or failed. Try again."
        case .unavailable(let detail):
            lastErrorDetail = "Authentication unavailable: \(detail). Add a Touch ID fingerprint or a login password in System Settings."
        }
    }
}
