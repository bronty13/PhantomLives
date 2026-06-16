import SwiftUI

/// Three-step Import to Photos sheet: choose a filter, watch progress, see a report.
/// Photos/videos only — audio is excluded (it's keep-exported to a folder instead).
struct ImportWizardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .filter
    @State private var filter: ImportFilter = .all
    private enum Step { case filter, progress, report }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import to Photos").font(.title2.weight(.semibold))
            Divider()
            switch step {
            case .filter:   filterStep
            case .progress: progressStep
            case .report:   reportStep
            }
        }
        .padding(20)
        .frame(width: 460, height: 430)
        .onChange(of: appState.importProgress?.finished) { _, finished in
            if finished == true { step = .report }
        }
    }

    // MARK: - Step 1: filter

    private var filterStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which photos and videos should be imported?").font(.headline)
            Picker("", selection: $filter) {
                ForEach(ImportFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            let count = appState.importCandidates(filter).count
            Text("\(count) item\(count == 1 ? "" : "s") will be imported.")
                .font(.callout).foregroundStyle(.secondary)

            if appState.exiftoolPath == nil {
                Label("exiftool not found — titles, captions, and keywords won't be embedded. Install with `brew install exiftool`.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Label("Audio files are excluded — keep them to copy into your Kept Audio folder.",
                  systemImage: "waveform")
                .font(.caption).foregroundStyle(.secondary)

            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Begin Import") { appState.runImport(filter: filter); step = .progress }
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0)
            }
        }
    }

    // MARK: - Step 2: progress

    private var progressStep: some View {
        let p = appState.importProgress
        return VStack(alignment: .leading, spacing: 14) {
            Text("Importing…").font(.headline)
            ProgressView(value: Double(p?.done ?? 0), total: Double(max(p?.total ?? 1, 1)))
                .tint(theme.accentColor)
            Text("\(p?.done ?? 0) of \(p?.total ?? 0)")
                .font(.callout).foregroundStyle(.secondary)
            if let current = p?.current, !current.isEmpty {
                Text(current).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Step 3: report

    private var reportStep: some View {
        let p = appState.importProgress
        return VStack(alignment: .leading, spacing: 14) {
            Text("Import Complete").font(.headline)
            HStack(spacing: 20) {
                stat("Succeeded", p?.succeeded ?? 0, .green)
                stat("Failed", p?.failed ?? 0, (p?.failed ?? 0) > 0 ? .red : .secondary)
            }
            if let failures = p?.failures, !failures.isEmpty {
                Text("Failures").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(failures.indices, id: \.self) { i in
                            Text("• \(failures[i].name): \(failures[i].reason)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            Spacer()
            HStack {
                Button("Open Photos") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
                }
                Spacer()
                Button("Done") { appState.importProgress = nil; dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack {
            Text("\(value)").font(.system(size: 30, weight: .bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
