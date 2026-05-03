import SwiftUI

@main
struct SizzleBotApp: App {
    @StateObject private var characterStore = CharacterStore()
    @StateObject private var ollamaService = OllamaService()
    @StateObject private var ollamaSetup = OllamaSetup()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(characterStore)
                .environmentObject(ollamaService)
                .environmentObject(ollamaSetup)
                .frame(minWidth: 800, minHeight: 560)
                .task { await ollamaSetup.run() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView()
                .environmentObject(characterStore)
                .environmentObject(ollamaService)
                .environmentObject(ollamaSetup)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var ollamaSetup: OllamaSetup
    @EnvironmentObject var characterStore: CharacterStore
    @EnvironmentObject var ollamaService: OllamaService

    var body: some View {
        switch ollamaSetup.state {
        case .ready:
            ContentView()
                .environmentObject(characterStore)
                .environmentObject(ollamaService)
                .task { await ollamaService.checkConnection() }

        case .notInstalled, .failed:
            SetupView(setup: ollamaSetup)

        default:
            SetupView(setup: ollamaSetup)
        }
    }
}
