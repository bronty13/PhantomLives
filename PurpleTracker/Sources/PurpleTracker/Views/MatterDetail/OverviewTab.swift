import SwiftUI
import AppKit

struct OverviewTab: View {
    @Binding var matter: Matter
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            datesAndCode
            Divider()
            initiativesAndGoalsSection
            Divider()
            requestorSection
            Divider()
            interestedPartiesSection
            Divider()
            externalInterestedPartiesSection
            Divider()
            references
            Divider()
            externals
            Divider()
            cadenceSection
        }
    }

    /// Multi-select chips for initiatives + goals. The user can tag a Matter
    /// with any combination of pre-configured Initiatives (Settings →
    /// Initiatives) and Goals (Settings → Goals).
    private var initiativesAndGoalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            tagPicker(
                title: "Initiatives",
                systemImage: "flag.fill",
                options: app.initiatives.map { ($0.id, $0.name) },
                selectedIds: app.matterInitiativeIds[matter.id] ?? [],
                emptyHint: "Configure in Settings → Initiatives",
                onChange: { ids in
                    try? app.setMatterInitiatives(matterId: matter.id, ids: ids)
                }
            )
            tagPicker(
                title: "Goals",
                systemImage: "target",
                options: app.goals.map { ($0.id, $0.name) },
                selectedIds: app.matterGoalIds[matter.id] ?? [],
                emptyHint: "Configure in Settings → Goals",
                onChange: { ids in
                    try? app.setMatterGoals(matterId: matter.id, ids: ids)
                }
            )
        }
    }

    @ViewBuilder
    private func tagPicker(
        title: String,
        systemImage: String,
        options: [(id: String, name: String)],
        selectedIds: Set<String>,
        emptyHint: String,
        onChange: @escaping (Set<String>) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage).font(.headline)
                Spacer()
                if !options.isEmpty {
                    Menu {
                        ForEach(options, id: \.id) { opt in
                            let isSelected = selectedIds.contains(opt.id)
                            Button {
                                var next = selectedIds
                                if isSelected { next.remove(opt.id) } else { next.insert(opt.id) }
                                onChange(next)
                            } label: {
                                if isSelected { Label(opt.name, systemImage: "checkmark") }
                                else          { Text(opt.name) }
                            }
                        }
                    } label: { Label("Tag", systemImage: "plus.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            if options.isEmpty {
                Text(emptyHint).font(.caption).foregroundStyle(.secondary)
            } else if selectedIds.isEmpty {
                Text("None selected").font(.caption).foregroundStyle(.secondary)
            } else {
                let chips = options.filter { selectedIds.contains($0.id) }
                FlowLayout(spacing: 6) {
                    ForEach(chips, id: \.id) { opt in
                        HStack(spacing: 4) {
                            Text(opt.name).font(.caption.weight(.medium))
                            Button {
                                var next = selectedIds
                                next.remove(opt.id)
                                onChange(next)
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.primary)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private var interestedPartiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Interested Parties").font(.headline)
            interestedPartyRow(label: "IP 1", id: $matter.interestedParty1AssociateId)
            interestedPartyRow(label: "IP 2", id: $matter.interestedParty2AssociateId)
            interestedPartyRow(label: "IP 3", id: $matter.interestedParty3AssociateId)
            interestedPartyRow(label: "IP 4", id: $matter.interestedParty4AssociateId)
            interestedPartyRow(label: "IP 5", id: $matter.interestedParty5AssociateId)
        }
    }

    private func interestedPartyRow(label: String, id: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label).frame(width: 80, alignment: .trailing).foregroundStyle(.secondary)
            PersonPicker(selectedId: id,
                         placeholder: "Type a name…",
                         clearHelp: "Clear \(label)")
        }
    }

    private var externalInterestedPartiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("External Interested Parties").font(.headline)
            externalIPRow(label: "External IP 1", text: $matter.externalInterestedParty1)
            externalIPRow(label: "External IP 2", text: $matter.externalInterestedParty2)
            externalIPRow(label: "External IP 3", text: $matter.externalInterestedParty3)
            externalIPRow(label: "External IP 4", text: $matter.externalInterestedParty4)
            externalIPRow(label: "External IP 5", text: $matter.externalInterestedParty5)
        }
    }

    private func externalIPRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
            TextField("Name / contact", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var requestorSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Requestor").frame(width: 80, alignment: .trailing).foregroundStyle(.secondary)
            RequestorPicker(selectedId: Binding(
                get: { matter.requestorAssociateId },
                set: { matter.requestorAssociateId = $0 }
            ))
        }
    }

    private var datesAndCode: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Created").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                Text(matter.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text("Modified").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                Text(matter.modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
            GridRow {
                Text("Accessed").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                Text(matter.accessedAt.formatted(date: .abbreviated, time: .shortened))
                Text("Due").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                DatePicker("", selection: Binding(
                    get: { matter.dueAt ?? Date() },
                    set: { matter.dueAt = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            GridRow {
                Text("Time Code").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                TextField("", text: $matter.timeTrackingCode)
                    .textFieldStyle(.roundedBorder)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    private var references: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Stores").font(.headline)
            pathRow(label: "Primary", binding: $matter.fileStorePrimary, isPrimary: true)
            pathRow(label: "Secondary", binding: $matter.fileStoreSecondary, isPrimary: false)
        }
    }

    private func pathRow(label: String, binding: Binding<String>, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).frame(width: 80, alignment: .trailing).foregroundStyle(.secondary)
                TextField("", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Create") {
                    _ = try? FileStoreService.createDirectory(at: binding.wrappedValue)
                    FileStoreService.reveal(path: binding.wrappedValue)
                }
                Button("Reveal") { FileStoreService.reveal(path: binding.wrappedValue) }
                // Open-in editor menu — Finder, VS Code, Obsidian. URL schemes
                // are no-ops if the editor isn't installed; that's harmless.
                Menu {
                    Button("Open in Finder") { FileStoreService.reveal(path: binding.wrappedValue) }
                    Button("Open in VS Code") {
                        let p = (binding.wrappedValue as NSString).expandingTildeInPath
                        let escaped = p.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? p
                        if let u = URL(string: "vscode://file\(escaped)") { NSWorkspace.shared.open(u) }
                    }
                    Button("Open in Obsidian") {
                        let p = (binding.wrappedValue as NSString).expandingTildeInPath
                        let escaped = p.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? p
                        if let u = URL(string: "obsidian://open?path=\(escaped)") { NSWorkspace.shared.open(u) }
                    }
                } label: { Image(systemName: "arrow.up.forward.app") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(binding.wrappedValue, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
            }
            // Lightweight existence/freshness indicator. Calls FileManager
            // synchronously — fine for the small folders the app deals with.
            let s = FileStoreStatusService.status(forPath: binding.wrappedValue)
            HStack(spacing: 6) {
                Spacer().frame(width: 88)
                Image(systemName: s.exists ? "checkmark.circle.fill" : "questionmark.circle")
                    .foregroundStyle(s.exists ? .green : .secondary)
                if s.exists {
                    Text("\(s.fileCount) item\(s.fileCount == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let m = s.lastModified {
                        Text("• modified \(m.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("not yet created")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var externals: some View {
        let s = settingsStore.settings
        return VStack(alignment: .leading, spacing: 10) {
            Text("External References").font(.headline)
            externalRow(label: s.external1Label, number: $matter.external1Number, url: $matter.external1Url)
            externalRow(label: s.external2Label, number: $matter.external2Number, url: $matter.external2Url)
            externalRow(label: s.external3Label, number: $matter.external3Number, url: $matter.external3Url)
        }
    }

    private func externalRow(label: String, number: Binding<String>, url: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 180, alignment: .trailing).foregroundStyle(.secondary)
            TextField("Number", text: number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
            TextField("URL", text: url)
                .textFieldStyle(.roundedBorder)
                .onChange(of: url.wrappedValue) { _, newValue in
                    // Autofill the Number field when a SNOW or ADO URL is
                    // pasted in and Number is currently empty (or matches
                    // a previous detection — never overwrites manual values).
                    if number.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty,
                       let m = URLAutofillService.detect(newValue) {
                        switch m {
                        case .snow(let n), .ado(let n):
                            number.wrappedValue = n
                        }
                    }
                }
            Button {
                if let u = URL(string: url.wrappedValue), !url.wrappedValue.isEmpty {
                    NSWorkspace.shared.open(u)
                }
            } label: { Image(systemName: "arrow.up.right.square") }
                .disabled(URL(string: url.wrappedValue) == nil || url.wrappedValue.isEmpty)
        }
    }

    @ViewBuilder
    private var cadenceSection: some View {
        if let type = app.typesById[matter.typeId], type.isCadenced {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cadence").font(.headline)
                CadenceEditor(matter: $matter)
            }
        }
    }
}

private struct CadenceEditor: View {
    @Binding var matter: Matter
    @EnvironmentObject var app: AppState
    @State private var kind: CadenceKind = .weekly
    @State private var customDays: Int = 7
    @State private var loaded = false

    var body: some View {
        HStack {
            Picker("Repeat", selection: $kind) {
                ForEach(CadenceKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .frame(maxWidth: 240)
            if kind == .custom {
                Stepper("every \(customDays) day(s)", value: $customDays, in: 1...365)
            }
            Button("Save Cadence") {
                let id = matter.cadenceId ?? UUID().uuidString
                let c = Cadence(id: id, kind: kind, customIntervalDays: kind == .custom ? customDays : nil)
                try? app.saveCadence(c)
                if matter.cadenceId == nil {
                    matter.cadenceId = id
                }
            }
        }
        .onAppear {
            guard !loaded, let cid = matter.cadenceId,
                  let c = try? DatabaseService.shared.fetchCadence(id: cid) else {
                loaded = true; return
            }
            kind = c.kind
            customDays = c.customIntervalDays ?? 7
            loaded = true
        }
    }
}
