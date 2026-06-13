import SwiftUI

struct LogView: View {
    @ObservedObject var controller: SyncController
    @State private var text: String = ""
    @State private var tailOnly = true
    @State private var liveTail = true

    // Ticks while the window is open; we reload on each tick when live-tail is on.
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
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
                .onChange(of: text) { _, _ in
                    if liveTail { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 320)
        .onAppear(perform: reload)
        .onReceive(ticker) { _ in if liveTail { reload() } }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Toggle("Live tail", isOn: $liveTail)
                .toggleStyle(.switch)
                .help("Auto-refresh and follow the end of the log every 1.5s")
            Toggle("Last 200 lines", isOn: $tailOnly)
                .toggleStyle(.checkbox)
            Spacer()
            Button { controller.revealLogInFinder() } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Button { controller.openLogInConsole() } label: {
                Label("Open in Console", systemImage: "terminal")
            }
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
        let fresh = controller.readLog()
        if fresh != text { text = fresh }   // avoid needless view churn when unchanged
    }
}
