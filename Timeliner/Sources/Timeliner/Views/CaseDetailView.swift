import SwiftUI

struct CaseDetailView: View {
    @EnvironmentObject private var appState: AppState
    let aCase: Case

    enum Tab: Hashable { case timeline, events, people, notes }
    @State private var tab: Tab = .timeline
    @State private var editingCase = false
    @State private var pendingDelete = false
    @State private var newEventDate = Date()
    @State private var showingNewEvent = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
        }
        .navigationTitle(aCase.title.isEmpty ? "Untitled case" : aCase.title)
        .sheet(isPresented: $editingCase) {
            CaseEditorSheet(aCase: aCase).environmentObject(appState)
        }
        .sheet(isPresented: $showingNewEvent) {
            EventEditorSheet(
                event: Event.newDraft(caseId: aCase.id, date: newEventDate),
                isNew: true
            )
            .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newEventRequested)) { _ in
            newEventDate = Date()
            showingNewEvent = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteCaseRequested)) { note in
            if let id = note.object as? String, id == aCase.id {
                pendingDelete = true
            }
        }
        .alert("Delete case?", isPresented: $pendingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? appState.deleteCase(id: aCase.id)
            }
        } message: {
            Text("All events, people, and tag links for this case will be removed.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    CaseStatusBadge(status: aCase.statusEnum)
                    if aCase.pinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Text(aCase.title.isEmpty ? "Untitled case" : aCase.title)
                    .font(.title.weight(.semibold))
                if !aCase.caseDescription.isEmpty {
                    MarkdownText(text: aCase.caseDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    editingCase = true
                } label: {
                    Label("Edit Case", systemImage: "pencil")
                }
                Button {
                    newEventDate = Date()
                    showingNewEvent = true
                } label: {
                    Label("New Event", systemImage: "calendar.badge.plus")
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
        .padding(20)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("Timeline",  systemImage: "calendar.day.timeline.left", value: .timeline)
            tabButton("Events",    systemImage: "list.bullet",                value: .events)
            tabButton("People",    systemImage: "person.2.fill",              value: .people)
            tabButton("Notes",     systemImage: "doc.text",                   value: .notes)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func tabButton(_ title: String, systemImage: String, value: Tab) -> some View {
        Button {
            tab = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.callout)
            .fontWeight(tab == value ? .semibold : .regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(tab == value ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tab == value ? Color.accentColor.opacity(0.18) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .timeline:
            TimelineView(caseId: aCase.id)
        case .events:
            EventListView(caseId: aCase.id)
        case .people:
            CasePeopleView(caseId: aCase.id)
        case .notes:
            CaseNotesView(aCase: aCase)
        }
    }
}

// MARK: - Case editor sheet

struct CaseEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Case

    init(aCase: Case) {
        _draft = State(initialValue: aCase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Case").font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                        TextField("Title", text: $draft.title)
                            .textFieldStyle(.roundedBorder)
                        TextEditor(text: $draft.caseDescription)
                            .frame(minHeight: 120, maxHeight: 240)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
                        Picker("Status", selection: Binding(
                            get: { draft.statusEnum },
                            set: { draft.statusEnum = $0 }
                        )) {
                            ForEach(CaseStatus.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Pin to top of sidebar", isOn: $draft.pinned)
                    }
                    .formStyle(.grouped)
                    AttachmentList(parent: .caseRecord, parentId: draft.id)
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    try? appState.updateCase(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(minWidth: 540, idealWidth: 620, maxWidth: 820,
               minHeight: 460, idealHeight: 560, maxHeight: 800)
    }
}

// MARK: - Notes tab (just renders the case description as markdown for now;
// dedicated rich notes tooling lands in Phase 2)

struct CaseNotesView: View {
    let aCase: Case

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if aCase.caseDescription.isEmpty {
                    Text("No notes yet. Use **Edit Case** above to add a synopsis or running notes (markdown supported).")
                        .foregroundStyle(.secondary)
                } else {
                    MarkdownText(text: aCase.caseDescription)
                        .font(.body)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}
