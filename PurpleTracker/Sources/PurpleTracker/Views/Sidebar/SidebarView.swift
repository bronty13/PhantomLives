import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List {
            Section("Overview") {
                row("Today", "sun.max", section: .today)
                row("All Matters", "tray.full", section: .all)
                row("Due Soon",    "clock",     section: .dueSoon)
                row("Overdue",     "exclamationmark.triangle", section: .overdue)
            }
            Section("Status") {
                ForEach(app.statusValues, id: \.name) { sv in
                    row(sv.name, "circle.fill", section: .status(sv.name))
                }
            }
            Section("Type") {
                ForEach(app.types) { t in
                    HStack {
                        Circle()
                            .fill(Color(hex: t.colorHex) ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(t.name)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .background(
                        rowBackground(for: .type(t.id))
                    )
                    .onTapGesture { app.sidebarSection = .type(t.id) }
                }
            }
            if !app.savedSearches.isEmpty {
                Section("Saved Searches") {
                    ForEach(app.savedSearches) { s in
                        row(s.name, "magnifyingglass.circle", section: .savedSearch(s.id))
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    try? app.deleteSavedSearch(id: s.id)
                                }
                            }
                    }
                }
            }
            Section("Tools") {
                row("Weekly Timesheet", "calendar.badge.clock", section: .weeklyTimesheet)
                row("Time Dashboard",   "chart.bar.xaxis",      section: .timeDashboard)
                row("Analytics",        "chart.pie",            section: .analytics)
                row("Capacity",         "person.3",             section: .capacity)
            }
            Section("Third Parties") {
                row("All Third Parties", "building.2", section: .thirdPartiesAll)
            }
            Section {
                row("Trash (\(app.trashedMatters.count))", "trash", section: .trash)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            // Drop a .eml on the sidebar to create a new Matter from the
            // email — title becomes Subject, description becomes the body.
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url, url.pathExtension.lowercased() == "eml",
                          let raw = try? String(contentsOf: url) else { return }
                    let parsed = EmailParser.parse(raw)
                    DispatchQueue.main.async {
                        guard let firstType = app.types.first else { return }
                        do {
                            var m = try app.createMatter(typeId: firstType.id, title: parsed.subject)
                            m.descriptionMd = "**From:** \(parsed.from)\n\n\(parsed.body)"
                            try app.updateMatter(m)
                        } catch {
                            app.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            return true
        }
        .listStyle(.sidebar)
        .navigationTitle("PurpleTracker")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(app.types) { t in
                        Button(t.name) {
                            _ = try? app.createMatter(typeId: t.id)
                        }
                    }
                } label: {
                    Label("New Matter", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Save Current Search…") { showSaveSearch = true }
                        .disabled(app.searchQuery.isEmpty)
                    Divider()
                    Button("Export Calendar (.ics)…") { exportICS() }
                    Button("Run Integrity Check…")  { runIntegrity() }
                    Divider()
                    Button("Copy Time by Initiative (Markdown)") { copyTimeByTag(.initiative) }
                    Button("Copy Time by Goal (Markdown)")       { copyTimeByTag(.goal) }
                } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
            }
        }
        .alert("Save Search", isPresented: $showSaveSearch) {
            TextField("Name", text: $saveSearchName)
            Button("Save") {
                guard !saveSearchName.isEmpty else { return }
                var c = SearchCriteria()
                c.text = app.searchQuery
                let s = SavedSearch(id: UUID().uuidString, name: saveSearchName,
                                    queryJson: "{}", sortOrder: app.savedSearches.count)
                var ss = s; ss.criteria = c
                try? app.saveSearch(ss)
                saveSearchName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Integrity Check", isPresented: $showIntegrity) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(integrityReport)
        }
        .alert("Calendar Exported", isPresented: $showICS) {
            Button("Reveal in Finder") {
                if let u = icsURL {
                    NSWorkspace.shared.activateFileViewerSelecting([u])
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Subscribe in Calendar.app: File → New Calendar Subscription → file://" +
                 (icsURL?.path ?? ""))
        }
    }

    @State private var showSaveSearch: Bool = false
    @State private var saveSearchName: String = ""
    @State private var showIntegrity: Bool = false
    @State private var integrityReport: String = ""
    @State private var showICS: Bool = false
    @State private var icsURL: URL? = nil

    private func exportICS() {
        do {
            let url = try ICSExporter.write(matters: app.matters,
                                            statusValues: app.statusValues,
                                            settingsStore: app.settingsStore)
            icsURL = url
            showICS = true
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }

    private func runIntegrity() {
        do {
            let ids = Set(app.people.map(\.id))
            let r = try IntegrityCheckService.run(peopleIds: ids)
            integrityReport = r.summary
            showIntegrity = true
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }

    private func copyTimeByTag(_ group: TimeByTagReport.GroupBy) {
        let entries = (try? DatabaseService.shared.fetchAllTimeEntries()) ?? []
        let md = TimeByTagReport.render(
            group: group,
            matters: app.matters,
            entries: entries,
            initiatives: app.initiatives,
            goals: app.goals,
            matterInitiativeIds: app.matterInitiativeIds,
            matterGoalIds: app.matterGoalIds
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    @ViewBuilder
    private func row(_ title: String, _ icon: String, section: AppState.SidebarSection) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
        }
        .contentShape(Rectangle())
        .background(rowBackground(for: section))
        .onTapGesture { app.sidebarSection = section }
    }

    private func rowBackground(for section: AppState.SidebarSection) -> some View {
        Group {
            if app.sidebarSection == section {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.20))
            } else {
                Color.clear
            }
        }
    }
}
