import SwiftUI

/// Step 7 — show progress while the runner streams events. The
/// model collects events into `rowEvents`; this view renders the
/// progress bar + last few status lines.
struct RunStep: View {
    @ObservedObject var model: ImportWizardModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
            Text("Importing…").font(.headline)
            if let total = model.progressTotal, total > 0 {
                ProgressView(value: Double(model.progressDone), total: Double(total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 360)
                Text("\(model.progressDone) / \(total)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            } else {
                ProgressView().progressViewStyle(.linear).frame(maxWidth: 360)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

struct DoneStep: View {
    @ObservedObject var model: ImportWizardModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Import complete").font(.title3).bold()
            if let s = model.summary {
                Text("\(s.inserted) inserted · \(s.updated) updated · \(s.skipped) skipped · \(s.failed) failed")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f s", s.duration))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .onAppear { appState.reloadAll() }
    }
}

struct ErrorStep: View {
    @ObservedObject var model: ImportWizardModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text("Import failed").font(.title3).bold()
            if let err = model.lastError {
                Text(err)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
