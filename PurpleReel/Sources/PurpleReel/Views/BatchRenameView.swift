import SwiftUI
import AppKit

/// "Batch Rename" dialog (Kyno-parity, Image #88-91). Named filename
/// presets drive the rename, surfaced via a Picker that includes the
/// system catalog + the user's saved customs + a "Manage…" leaf.
/// The custom-name TextField only appears when the picked preset's
/// template includes `${customName}`.
struct BatchRenameView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Sticky preset selection — restores the user's last pick on
    /// re-open. Default = "Custom Name" (Kyno's default per Image #88).
    @AppStorage("batchRenamePresetID") private var presetID: String = "sys-custom"
    @AppStorage("batchRenameCustomName") private var customName: String = ""
    @AppStorage("batchRenameStartCounter") private var startCounter: Int = 1
    @State private var scope: Scope = .selectedOnly
    @State private var showManageSheet: Bool = false

    enum Scope: String, CaseIterable, Identifiable {
        case allCatalogued, selectedOnly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .allCatalogued: return "All catalogued"
            case .selectedOnly:  return "Selected only"
            }
        }
    }

    private var sourceAssets: [Asset] {
        switch scope {
        case .allCatalogued: return appState.assets
        case .selectedOnly:
            let multi = appState.selectedAssetPaths
            if !multi.isEmpty {
                return appState.assets.filter { multi.contains($0.path) }
            }
            if let a = appState.selectedAsset { return [a] }
            return []
        }
    }

    private var currentPreset: FilenameRenamePreset {
        BatchRenamePresets.find(id: presetID)
            ?? FilenameRenamePresetCatalog.system.first!
    }

    private var templateUsesCustomName: Bool {
        currentPreset.template.contains("${customName}")
    }

    private var plans: [BatchRenamePlan] {
        BatchRenameService.plan(
            template: currentPreset.template,
            items: sourceAssets,
            startCounter: startCounter,
            customName: customName,
            markerTitleLookup: markerTitleLookup
        )
    }

    /// C22 — DB-backed resolver for the `${markerTitle}` token.
    /// Returns the first catalogued marker's note text for an asset,
    /// nil if the asset has no rowId yet or no markers. The service
    /// applies its own filename-safe sanitization on the way out.
    private var markerTitleLookup: (Asset) -> String? {
        { asset in
            guard let rowId = asset.rowId else { return nil }
            return (try? appState.db.markers(assetId: rowId))?.first?.note
        }
    }

    /// One-asset preview that drives the live Example label without
    /// rebuilding the whole plan. Uses the first asset in scope,
    /// falling back to a synthetic placeholder when nothing is
    /// selected (so the dialog can still show a meaningful Example
    /// before the user picks any clips).
    private var exampleName: String {
        guard let first = sourceAssets.first else {
            return placeholderExample()
        }
        let plan = BatchRenameService.plan(
            template: currentPreset.template,
            items: [first],
            startCounter: startCounter,
            customName: customName,
            markerTitleLookup: markerTitleLookup
        )
        return plan.first?.proposedName ?? "—"
    }

    private func placeholderExample() -> String {
        let synthetic = Asset(
            rowId: nil, path: "/tmp/example.mov",
            filename: "example.mov", sizeBytes: 0,
            modifiedAt: Date(), codec: "avc1",
            widthPx: 1920, heightPx: 1080,
            durationSeconds: 60, frameRate: 29.97,
            sha1: nil, addedAt: Date()
        )
        let plan = BatchRenameService.plan(
            template: currentPreset.template,
            items: [synthetic],
            startCounter: startCounter,
            customName: customName.isEmpty ? "MyClip" : customName
        )
        return plan.first?.proposedName ?? ""
    }

    private var willRenameCount: Int {
        plans.filter { !$0.isNoop && !$0.conflicts }.count
    }

    private var conflictCount: Int {
        plans.filter { $0.conflicts }.count
    }

    private var hasEmptyOutput: Bool {
        templateUsesCustomName && customName.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    scopeRow
                    presetRow
                    if templateUsesCustomName { customNameRow }
                    exampleRow
                }
                .padding(20)
                Divider()
                previewSection.padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 560)
        .sheet(isPresented: $showManageSheet) {
            ManageFilenamePresetsSheet()
        }
    }

    private var header: some View {
        HStack {
            Text("Batch Rename").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var scopeRow: some View {
        GridRow {
            Text("Apply to:").foregroundStyle(.secondary)
            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var presetRow: some View {
        GridRow {
            Text("File name pattern:").foregroundStyle(.secondary)
            HStack {
                Picker("", selection: $presetID) {
                    Section {
                        ForEach(FilenameRenamePresetCatalog.system) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    let userPresets = BatchRenamePresets.loadUser()
                    if !userPresets.isEmpty {
                        Section("Custom") {
                            ForEach(userPresets) { p in
                                Text(p.name).tag(p.id)
                            }
                        }
                    }
                    Divider()
                    // Sentinel id — clicking opens the Manage sheet
                    // and snaps the selection back to the previous
                    // preset so the picker doesn't end up showing
                    // "Manage…" as the active row.
                    Text("Manage…").tag("__manage__")
                }
                .labelsHidden()
                .frame(maxWidth: 320, alignment: .leading)
                .onChange(of: presetID) { _, new in
                    if new == "__manage__" {
                        // Restore previous selection; the Picker should
                        // not stay parked on the action item.
                        if let valid = BatchRenamePresets.combined().first {
                            presetID = valid.id
                        }
                        showManageSheet = true
                    }
                }
                Spacer()
            }
        }
    }

    private var customNameRow: some View {
        GridRow {
            Text("Custom Name:").foregroundStyle(.secondary)
            TextField("", text: $customName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var exampleRow: some View {
        GridRow(alignment: .top) {
            Text("Example:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(exampleName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                if hasEmptyOutput {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Output file has an empty name")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                if conflictCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(conflictCount) collision(s) detected — see preview below")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preview").font(.headline)
                Spacer()
                Text("\(willRenameCount) will be renamed · \(conflictCount) conflict\(conflictCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Start at \(startCounter)",
                         value: $startCounter, in: 1...10000)
                    .font(.caption)
                    .frame(maxWidth: 180)
            }
            if plans.isEmpty {
                Text("No clips in scope.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plans) { plan in
                    PreviewRow(plan: plan)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Start Renaming") { runRename() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(willRenameCount == 0 || hasEmptyOutput)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func runRename() {
        do {
            let moves = try BatchRenameService.apply(plans)
            for move in moves {
                try? appState.db.updateAssetPath(oldPath: move.old,
                                                   newPath: move.new)
            }
            Task { await appState.rescan() }
            dismiss()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Rename failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

private struct PreviewRow: View {
    let plan: BatchRenamePlan
    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(plan.originalURL.lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(plan.proposedName)
                .font(.caption.monospaced())
                .foregroundStyle(plan.conflicts ? .red : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if plan.conflicts {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help("Destination already exists or collides with another item in this batch")
        } else if plan.isNoop {
            Image(systemName: "equal.circle")
                .foregroundStyle(.secondary)
                .help("No change")
        } else {
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .foregroundStyle(.tint)
        }
    }
}
