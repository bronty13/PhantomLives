import SwiftUI

/// Standalone window that streams join / part / quit / nick events across
/// every connected network, useful as a presence monitor that lives next
/// to the main app. Reads from `ChatModel.activityFeed` so opening the
/// window doesn't re-subscribe to anything — the feed is always being
/// captured in the background.
struct WatchMonitorView: View {
    @EnvironmentObject var model: ChatModel

    @State private var kindFilter: ActivityEvent.Kind? = nil
    @State private var search: String = ""
    @State private var paused: Bool = false
    /// Frozen snapshot taken when the user pauses, so the live feed can
    /// keep accumulating in the background without disturbing what they're
    /// reading. Cleared when they unpause.
    @State private var pauseSnapshot: [ActivityEvent] = []

    private var sourceFeed: [ActivityEvent] {
        paused ? pauseSnapshot : model.activityFeed
    }

    private var filteredFeed: [ActivityEvent] {
        var out = sourceFeed
        if let k = kindFilter {
            out = out.filter { $0.kind == k }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            out = out.filter { e in
                e.nick.lowercased().contains(q)
                    || (e.channel?.lowercased().contains(q) ?? false)
                    || (e.userHost?.lowercased().contains(q) ?? false)
                    || (e.detail?.lowercased().contains(q) ?? false)
                    || e.networkName.lowercased().contains(q)
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            statusBar
        }
        .frame(minWidth: 540, minHeight: 360)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(Color.purple)
            Text("Watch Monitor").font(.headline)
            Spacer(minLength: 12)
            // Kind filter — picker keeps the toolbar compact even with all
            // four kinds + "All".
            Picker("", selection: $kindFilter) {
                Text("All").tag(ActivityEvent.Kind?.none)
                ForEach(ActivityEvent.Kind.allCases, id: \.self) { k in
                    Text(label(for: k)).tag(ActivityEvent.Kind?.some(k))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            TextField("Find nick / channel / host", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            Button {
                if paused {
                    paused = false
                    pauseSnapshot.removeAll()
                } else {
                    pauseSnapshot = model.activityFeed
                    paused = true
                }
            } label: {
                Label(paused ? "Resume" : "Pause",
                      systemImage: paused ? "play.fill" : "pause.fill")
            }
            Button {
                model.clearActivityFeed()
                pauseSnapshot.removeAll()
            } label: {
                Label("Clear", systemImage: "trash")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if filteredFeed.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(emptyMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredFeed) { e in
                            row(e).id(e.id)
                            Divider()
                        }
                        // Anchor for auto-scroll-to-newest.
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: filteredFeed.count) { _, _ in
                    // Don't auto-scroll while paused — the user is reading.
                    guard !paused else { return }
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(statusText)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if paused {
                Label("Paused", systemImage: "pause.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func row(_ e: ActivityEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.timeFmt.string(from: e.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)

            Text(label(for: e.kind))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(color(for: e.kind).opacity(0.18)))
                .foregroundStyle(color(for: e.kind))
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.nick)
                        .font(.system(.body, design: .monospaced).bold())
                    if let channel = e.channel {
                        Text(channel)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let detail = e.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if let host = e.userHost {
                    Text(host)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Text(e.networkName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyMessage: String {
        if model.activityFeed.isEmpty {
            return "No activity yet. Joins, parts, quits, and nick changes from every connected network land here."
        }
        return "No matches for the current filter."
    }

    private var statusText: String {
        let total = model.activityFeed.count
        let shown = filteredFeed.count
        if shown == total { return "\(total) event\(total == 1 ? "" : "s")" }
        return "\(shown) of \(total) shown"
    }

    private func label(for kind: ActivityEvent.Kind) -> String {
        switch kind {
        case .join: return "join"
        case .part: return "part"
        case .quit: return "quit"
        case .nick: return "nick"
        }
    }

    private func color(for kind: ActivityEvent.Kind) -> Color {
        switch kind {
        case .join: return .green
        case .part: return .orange
        case .quit: return .red
        case .nick: return .purple
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
