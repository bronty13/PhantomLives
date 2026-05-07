import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 220)
        } content: {
            MatterListView()
                .frame(minWidth: 320)
        } detail: {
            if let m = app.selectedMatter {
                MatterDetailView(matter: m)
            } else {
                ContentUnavailableView(
                    "No Matter Selected",
                    systemImage: "doc.text",
                    description: Text("Choose a Matter from the list, or press ⌘N to create one.")
                )
            }
        }
        .alert("Error",
               isPresented: Binding(
                get: { app.errorMessage != nil },
                set: { if !$0 { app.errorMessage = nil } }
               )) {
            Button("OK", role: .cancel) { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}
