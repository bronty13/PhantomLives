import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("👻")
                .font(.system(size: 72))
            Text("SizzleBot")
                .font(.largeTitle.bold())
            Text("Select a character to start a conversation")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
