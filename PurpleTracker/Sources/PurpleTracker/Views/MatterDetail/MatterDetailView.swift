import SwiftUI
import AppKit
import GRDB

struct MatterDetailView: View {
    let matter: Matter
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var tab: Tab = .overview
    @State private var draft: Matter?

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case description = "Description"
        case notes = "Notes"
        case time = "Time"
        case attachments = "Attachments"
        case resolution = "Resolution"
        case lessons = "Lessons"
        var id: String { rawValue }
    }

    var body: some View {
        let typeColor = app.typesById[matter.typeId].flatMap { Color(hex: $0.colorHex) } ?? .accentColor
        VStack(spacing: 0) {
            header(typeColor: typeColor)
                .padding()
                .background(typeColor.opacity(0.12))
            Divider()
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .overview:    OverviewTab(matter: bindingMatter)
                    case .description: MarkdownTab(field: \.descriptionMd, matter: bindingMatter, label: "Description")
                    case .notes:       NotesTab()
                    case .time:        TimeTab(matter: matter)
                    case .attachments: AttachmentsTab()
                    case .resolution:  MarkdownTab(field: \.resolutionMd, matter: bindingMatter, label: "Resolution")
                    case .lessons:     MarkdownTab(field: \.lessonsMd,   matter: bindingMatter, label: "Lessons Learned")
                    }
                }
                .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    ExportService.copyBrief(matter)
                } label: { Label("Copy Brief", systemImage: "rectangle.on.rectangle") }
                    .help("Copy Matter ID • Title • Date Opened • Status")

                Menu {
                    Button("Markdown (.md)") { exportFile(.markdown) }
                    Button("PDF (.pdf)")     { exportFile(.pdf) }
                    Button("Word (.docx)")   { exportFile(.docx) }
                    Divider()
                    Button("Copy Markdown to Clipboard") {
                        ExportService.copyMarkdown(matter,
                            types: app.types,
                            notes: app.notes,
                            timeEntries: app.timeEntries,
                            attachments: [],   // metadata only — full BLOBs not needed for clipboard
                            settings: settingsStore.settings)
                    }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
            }
        }
    }

    @ViewBuilder
    private func header(typeColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                MatterIDBadge(matterId: matter.id, color: typeColor)
                Spacer()
                statusMenu(color: typeColor)
            }
            HStack(alignment: .center, spacing: 12) {
                TextField("Title", text: bindingMatter.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .onSubmit { commitDraft() }

                if let type = app.typesById[matter.typeId] {
                    Menu {
                        ForEach(app.types) { t in
                            Button(t.name) { changeType(to: t.id) }
                        }
                    } label: {
                        Label(type.name, systemImage: "tag.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            HStack {
                if let due = matter.dueAt {
                    Label("Due \(due.formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(due < Date() && matter.status != "Closed" ? .red : .secondary)
                }
                if let p = app.peopleById[matter.requestorAssociateId],
                   !matter.requestorAssociateId.isEmpty {
                    Label(p.displayNameWithTitle, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Requestor — Settings → People to manage roster")
                }
                Spacer()
                if let secs = app.totalSecondsByMatter[matter.id] {
                    Label("Total \(TimeFormat.hm(secs))", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusMenu(color: Color) -> some View {
        Menu {
            ForEach(app.statusValues, id: \.name) { sv in
                Button(sv.name) {
                    try? app.updateMatterStatus(matter, to: sv.name)
                }
            }
        } label: {
            Text(matter.status)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(color.opacity(0.25))
                .foregroundStyle(color)
                .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func changeType(to typeId: String) {
        var m = matter
        m.typeId = typeId
        try? app.updateMatter(m)
    }

    /// Two-way binding into the Matter that auto-saves on every mutation.
    /// Kept simple — for the title field we save on `onSubmit` to avoid
    /// hitting the DB on every keystroke; for everything else the wrapping
    /// editors handle their own commit cadence.
    private var bindingMatter: Binding<Matter> {
        Binding(
            get: { matter },
            set: { newValue in
                draft = newValue
                try? app.updateMatter(newValue)
            }
        )
    }

    private func commitDraft() {
        if let d = draft { try? app.updateMatter(d) }
    }

    private func exportFile(_ fmt: ExportService.Format) {
        do {
            // Pull the full attachment payloads for inclusion in the export.
            let pool = DatabaseService.shared.dbPool
            let atts = try pool.read { db in
                try Attachment.filter(Column("matter_id") == matter.id).fetchAll(db)
            }
            let url = try ExportService.exportToFile(
                format: fmt,
                matter: matter,
                types: app.types,
                notes: app.notes,
                timeEntries: app.timeEntries,
                attachments: atts,
                settings: settingsStore.settings,
                settingsStore: settingsStore
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

// (GRDB imported at top of file)
