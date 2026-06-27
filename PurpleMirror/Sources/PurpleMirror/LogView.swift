import SwiftUI

struct LogView: View {
    @ObservedObject var model: JobsModel
    @State private var text: String = ""
    @State private var tailOnly = true
    @State private var liveTail = true

    // Ticks while the window is open; we reload on each tick when live-tail is on.
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            JobSidebar(model: model)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(displayed)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .id("end")
                    }
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: text) { _, _ in if liveTail { proxy.scrollTo("end", anchor: .bottom) } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 360)
        .onAppear(perform: reload)
        .onChange(of: model.selectedJobID) { _, _ in reload() }
        .onReceive(ticker) { _ in if liveTail { reload() } }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if let job = model.selectedJob {
                Image(systemName: job.health.symbol).foregroundStyle(job.health.color)
                Text(job.displayName).font(.headline).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Toggle("Live tail", isOn: $liveTail).toggleStyle(.switch)
                .help("Auto-refresh and follow the end of the log every 1.5s")
            Toggle("Last 200 lines", isOn: $tailOnly).toggleStyle(.checkbox)
            Button { model.selectedJob?.revealLogInFinder() } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .disabled(!(model.selectedJob?.hasLocalLog ?? false))
            Button { model.selectedJob?.openLogInConsole() } label: {
                Label("Open in Console", systemImage: "terminal")
            }
            .disabled(!(model.selectedJob?.hasLocalLog ?? false))
            .help((model.selectedJob?.isLocalHost ?? true) ? "" : "Remote job — the log is read over SSH; Reveal/Console are local-only.")
        }
        .padding(10)
    }

    private var displayed: String {
        guard tailOnly else { return text.isEmpty ? "(empty)" : text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(200)
        return tail.isEmpty ? "(empty)" : tail.joined(separator: "\n")
    }

    private func reload() {
        // Host-aware: local read or `cat` over ssh, so fetch off the main thread.
        let job = model.selectedJob
        Task {
            let fresh = await job?.loadLog() ?? "(no job selected)"
            if fresh != text { text = fresh }   // avoid needless view churn when unchanged
        }
    }
}
