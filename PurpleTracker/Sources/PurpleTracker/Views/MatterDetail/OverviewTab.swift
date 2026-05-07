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
            references
            Divider()
            externals
            Divider()
            cadenceSection
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
        HStack {
            Text(label).frame(width: 80, alignment: .trailing).foregroundStyle(.secondary)
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            if isPrimary {
                Button("Create") {
                    try? FileStoreService.createDirectory(at: binding.wrappedValue)
                    FileStoreService.reveal(path: binding.wrappedValue)
                }
            }
            Button("Reveal") { FileStoreService.reveal(path: binding.wrappedValue) }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(binding.wrappedValue, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
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
