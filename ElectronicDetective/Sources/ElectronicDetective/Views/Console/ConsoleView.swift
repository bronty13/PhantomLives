import SwiftUI

/// The on-screen recreation of the angled brown console. Drawn entirely in
/// SwiftUI shapes — no raster image required. M1 wires the keys into
/// `ConsoleViewModel`; M3 adds the bevel highlights and key-click audio.
struct ConsoleView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var model = ConsoleViewModel()

    var body: some View {
        VStack(spacing: 20) {
            consoleHousing
        }
        .onAppear { model.bind(appState: appState) }
    }

    private var consoleHousing: some View {
        VStack(spacing: 18) {
            LEDDisplayView(line: model.line)
                .padding(.horizontal, 24)
                .padding(.top, 22)
            KeypadView { key in model.handle(key: key) }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(
                    colors: [Color(red: 0.42, green: 0.27, blue: 0.16),
                             Color(red: 0.28, green: 0.17, blue: 0.10)],
                    startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 18, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(.black.opacity(0.4), lineWidth: 1)
        )
        .frame(maxWidth: 540)
    }
}
