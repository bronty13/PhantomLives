import SwiftUI
import AppKit

struct BatchRenameView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @AppStorage("batchRenameTemplate") private var template: String = "{date}_{orig}_{counter:04}{ext}"
    @AppStorage("batchRenameStartCounter") private var startCounter: Int = 1
    @State private var scope: Scope = .allCatalogued

    enum Scope: String, CaseIterable, Identifiable {
        case allCatalogued, selectedOnly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .allCatalogued: return "All catalogued"
            case .selectedOnly:  return "Selected clip only"
            }
        }
    }

    private var sourceAssets: [Asset] {
        switch scope {
        case .allCatalogued: return appState.assets
        case .selectedOnly:
            if let a = appState.selectedAsset { return [a] }
            return []
        }
    }

    private var plans: [BatchRenamePlan] {
        BatchRenameService.plan(
            template: template,
            items: sourceAssets,
            startCounter: startCounter
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    scopePicker
                    templateField
                    tokenReference
                    Divider()
                    previewSection
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    private var header: some View {
        HStack {
            Image(systemName: "character.cursor.ibeam")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Batch Rename").font(.title2.bold())
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var scopePicker: some View {
        Picker("Apply to", selection: $scope) {
            ForEach(Scope.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
    }

    private var templateField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Template").font(.headline)
            TextField("", text: $template)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Text("Counter starts at")
                Stepper(value: $startCounter, in: 1...10000) {
                    Text("\(startCounter)")
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .frame(maxWidth: 200)
                Spacer()
            }
            .font(.caption)
        }
    }

    private var tokenReference: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tokens").font(.caption.bold()).foregroundStyle(.secondary)
            Text("`{orig}` `{ext}` `{date}` `{date:yyyyMMdd}` `{counter}` `{counter:04}` `{codec}` `{fps}` `{w}` `{h}` `{size_mb}`")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                let willChange = plans.filter { !$0.isNoop && !$0.conflicts }.count
                let conflicts = plans.filter { $0.conflicts }.count
                Text("\(willChange) will be renamed · \(conflicts) conflict\(conflicts == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
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
            Button("Rename \(plans.filter { !$0.isNoop && !$0.conflicts }.count) clips") {
                runRename()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(plans.filter { !$0.isNoop && !$0.conflicts }.isEmpty)
        }
        .padding(16)
    }

    private func runRename() {
        do {
            let moves = try BatchRenameService.apply(plans)
            for move in moves {
                try? appState.db.updateAssetPath(oldPath: move.old, newPath: move.new)
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
