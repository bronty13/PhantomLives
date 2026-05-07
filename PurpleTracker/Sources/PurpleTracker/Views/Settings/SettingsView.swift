import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            TypesSettingsView()
                .tabItem { Label("Types", systemImage: "tag") }
            StatusSettingsView()
                .tabItem { Label("Status", systemImage: "circle.grid.2x2") }
            ExternalRefsSettingsView()
                .tabItem { Label("External Refs", systemImage: "link") }
            FileStoreSettingsView()
                .tabItem { Label("File Store", systemImage: "folder") }
            PeopleSettingsView()
                .tabItem { Label("People", systemImage: "person.2") }
            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.timemachine") }
        }
        .padding()
    }
}
