import SwiftUI

struct ContentView: View {
    @EnvironmentObject var characterStore: CharacterStore
    @EnvironmentObject var ollamaService: OllamaService
    @StateObject private var conversationStore = ConversationStore()

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(conversationStore)
        } detail: {
            if let character = characterStore.selectedCharacter {
                ChatView(character: character)
                    .environmentObject(conversationStore)
                    .id(character.id)
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            Task { await ollamaService.checkConnection() }
        }
    }
}
