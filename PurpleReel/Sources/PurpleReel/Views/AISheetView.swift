import SwiftUI
import AppKit

struct AISheetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let state: AISheetState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            content
                .padding(16)
            Spacer()
            footer
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    // MARK: - State-specific UI

    @ViewBuilder
    private var content: some View {
        switch state {
        case .transcribing(let filename):
            progressView(text: "Transcribing \(filename) with MLX Whisper…")
        case .transcriptReady(let doc, let assetName):
            transcriptReadyView(doc: doc, assetName: assetName)
        case .describing(let filename):
            progressView(text: "Drafting description for \(filename)…")
        case .describeReady(let text, let assetName):
            describeReadyView(text: text, assetName: assetName)
        case .findingSimilar(let progress, let total):
            similarProgressView(progress: progress, total: total)
        case .similarReady(let count):
            similarReadyView(count: count)
        case .error(let message):
            errorView(message: message)
        }
    }

    private func progressView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
            Text(text)
            Text("All processing is local — no data leaves your machine.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func transcriptReadyView(doc: TranscriptDocument, assetName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript saved").font(.headline)
            Text("\(doc.segments.count) segments · model: \(doc.modelName) · \(assetName)")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(doc.segments, id: \.index) { seg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(formatTC(seg.start))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(seg.text)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .background(Color.secondary.opacity(0.06),
                         in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func describeReadyView(text: String, assetName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description saved").font(.headline)
            Text(assetName).font(.caption).foregroundStyle(.secondary)
            Text(text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06),
                             in: RoundedRectangle(cornerRadius: 6))
            Text("The description has been written to this clip's metadata pane.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func similarProgressView(progress: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: total > 0 ? Double(progress) / Double(total) : 0)
                .progressViewStyle(.linear)
            Text("Hashing middle frames: \(progress) of \(total)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func similarReadyView(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Found \(count) cluster\(count == 1 ? "" : "s") of similar takes")
                .font(.headline)
            if appState.similarClusters.isEmpty {
                Text("No near-duplicate takes were detected. The Hamming threshold (10/64 bits) treats minor reframing / exposure changes as 'similar'.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.similarClusters) { cluster in
                            ClusterRow(cluster: cluster)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Something went wrong").font(.headline)
            }
            Text(message)
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06),
                             in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var footer: some View {
        HStack {
            Text(appState.aiStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Header

    private var title: String {
        switch state {
        case .transcribing, .transcriptReady: return "Whisper Transcription"
        case .describing, .describeReady: return "Auto-Describe"
        case .findingSimilar, .similarReady: return "Similar Takes"
        case .error: return "AI Error"
        }
    }

    private var icon: String {
        switch state {
        case .transcribing, .transcriptReady: return "text.bubble"
        case .describing, .describeReady: return "sparkles"
        case .findingSimilar, .similarReady: return "rectangle.stack"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func formatTC(_ seconds: Double) -> String {
        let t = Int(seconds)
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}

private struct ClusterRow: View {
    let cluster: SimilarTakeCluster

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(.yellow)
                Text(cluster.bestAsset.filename).bold()
                Spacer()
                Text(cluster.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(cluster.assets.filter { $0.path != cluster.bestAsset.path },
                     id: \.path) { asset in
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(asset.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06),
                     in: RoundedRectangle(cornerRadius: 6))
    }
}
