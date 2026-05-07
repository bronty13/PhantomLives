import SwiftUI

struct CaseListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let aCase = appState.selectedCase {
            CaseDetailView(aCase: aCase)
        } else {
            CaseGalleryView()
        }
    }
}

struct CaseGalleryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query: String = ""
    @State private var statusFilter: CaseStatus?
    @State private var showingNewCase = false
    @State private var pendingDeleteId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Filter bar
            HStack(spacing: 12) {
                TextField("Filter cases…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                Picker("", selection: $statusFilter) {
                    Text("All statuses").tag(CaseStatus?.none)
                    ForEach(CaseStatus.allCases, id: \.self) { s in
                        Text(s.label).tag(CaseStatus?.some(s))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 180)

                Spacer()

                Button {
                    showingNewCase = true
                } label: {
                    Label("New case", systemImage: "folder.fill.badge.plus")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if filteredCases.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(appState.cases.isEmpty ? "No cases yet." : "No cases match this filter.")
                        .foregroundStyle(.secondary)
                    if appState.cases.isEmpty {
                        Button("Create your first case") { showingNewCase = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 280), spacing: 14)
                    ], spacing: 14) {
                        ForEach(filteredCases) { c in
                            CaseCard(aCase: c, eventCount: appState.events.filter { $0.caseId == c.id }.count) {
                                appState.selectedCaseId = c.id
                            } onDelete: {
                                pendingDeleteId = c.id
                            } onTogglePin: {
                                try? appState.togglePin(caseId: c.id)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Cases")
        .sheet(isPresented: $showingNewCase) { NewCaseSheet().environmentObject(appState) }
        .alert("Delete case?",
               isPresented: Binding(get: { pendingDeleteId != nil },
                                     set: { if !$0 { pendingDeleteId = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteId { try? appState.deleteCase(id: id) }
                pendingDeleteId = nil
            }
        } message: {
            Text("All events, people, and tag links for this case will be removed. This can't be undone.")
        }
    }

    private var filteredCases: [Case] {
        var out = appState.cases
        if let s = statusFilter { out = out.filter { $0.statusEnum == s } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            out = out.filter { $0.title.lowercased().contains(q) || $0.caseDescription.lowercased().contains(q) }
        }
        return out
    }
}

private struct CaseCard: View {
    let aCase: Case
    let eventCount: Int
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CaseStatusBadge(status: aCase.statusEnum)
                    Spacer()
                    if aCase.pinned {
                        Image(systemName: "pin.fill").foregroundStyle(.orange)
                    }
                }
                Text(aCase.title.isEmpty ? "Untitled case" : aCase.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if !aCase.caseDescription.isEmpty {
                    Text(aCase.caseDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 4)
                HStack {
                    Label("\(eventCount) events", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(16)
            .frame(minHeight: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.secondary.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(aCase.pinned ? "Unpin" : "Pin", action: onTogglePin)
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        }
    }
}

struct NewCaseSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var status: CaseStatus = .active

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Case")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $description)
                    .frame(minHeight: 100, maxHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
                Picker("Status", selection: $status) {
                    ForEach(CaseStatus.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    do {
                        let aCase = try appState.createCase(title: title)
                        var c = aCase
                        c.caseDescription = description
                        c.statusEnum = status
                        try appState.updateCase(c)
                        appState.selectedSection = .allCases
                        dismiss()
                    } catch {
                        // Surface error via NSLog; the create flow is forgiving.
                        NSLog("Timeliner: createCase failed — \(error.localizedDescription)")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        // Bound size on every axis. Using only minWidth/minHeight lets SwiftUI
        // grow the sheet to whatever the Form+TextEditor wants, which on
        // first launch can balloon past the screen and trap the user with
        // off-screen buttons.
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 720,
               minHeight: 340, idealHeight: 380, maxHeight: 560)
    }
}
