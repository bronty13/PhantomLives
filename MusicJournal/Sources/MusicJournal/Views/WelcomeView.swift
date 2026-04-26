// WelcomeView.swift
// Shown when the user has not yet connected Spotify (no refresh token in Keychain).
// Presents the app branding and a single "Connect Spotify" CTA button.

import SwiftUI

/// Onboarding/login screen displayed before Spotify authentication.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // App icon visual — dark green gradient with gold music note
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.07, green: 0.2, blue: 0.12),
                                     Color(red: 0.03, green: 0.05, blue: 0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                Image(systemName: "music.note")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Color(red: 0.82, green: 0.63, blue: 0.2))
            }
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)

            VStack(spacing: 8) {
                Text("Music Journal")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Your personal music journal.\nSync playlists from Spotify and annotate your collection.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Button {
                appState.spotifyAuth.loginError = nil
                appState.spotifyAuth.startLogin()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                    Text("Connect Spotify")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.11, green: 0.73, blue: 0.33))  // Spotify green

            if let error = appState.spotifyAuth.loginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
