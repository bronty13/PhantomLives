import SwiftUI

struct BufferView: View {
    @EnvironmentObject var model: ChatModel
    let bufferIndex: Int

    @State private var input: String = ""
    @State private var history: [String] = []
    @State private var historyPos: Int = 0
    @State private var completion: TabCompletion? = nil

    struct TabCompletion {
        let typedPrefix: String   // text before the completed word (includes trailing space when non-empty)
        let partial: String       // original partial the user typed (before first tab)
        let candidates: [String]  // sorted matching nicks
        var index: Int
        let suffix: String        // ": " when first word, " " otherwise
    }

    var buffer: Buffer { model.buffers[bufferIndex] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                messagesPane
                if buffer.isChannel {
                    Divider()
                    userListPane
                        .frame(width: 180)
                }
            }
            Divider()
            inputBar
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName).foregroundStyle(.secondary)
            Text(buffer.displayName).font(.headline)
            if !buffer.topic.isEmpty {
                Text("— \(buffer.topic)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if buffer.kind != .server {
                Button(action: { model.closeCurrentBuffer() }) {
                    Label("Close", systemImage: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close this buffer")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var iconName: String {
        switch buffer.kind {
        case .server: return "server.rack"
        case .channel: return "number"
        case .query: return "person.fill"
        }
    }

    private var messagesPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(buffer.lines) { line in
                        MessageRow(line: line).id(line.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: buffer.lines.count) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var userListPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Users (\(buffer.users.count))")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            List(buffer.users, id: \.self) { user in
                Text(user).font(.system(.body, design: .monospaced))
            }
            .listStyle(.plain)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("\(model.nick):")
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
            TextField(placeholder, text: $input)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onSubmit(submit)
                .onChange(of: input) { _, _ in
                    // Any manual edit that breaks the expected tail invalidates
                    // the active completion; performTabComplete will recompute.
                    if let c = completion, !input.hasSuffix(c.suffix)
                        || !input.dropLast(c.suffix.count).hasSuffix(c.candidates[c.index]) {
                        completion = nil
                    }
                }
                .onKeyPress(.tab) {
                    performTabComplete()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    if !history.isEmpty, historyPos > 0 {
                        historyPos -= 1
                        input = history[historyPos]
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    if historyPos < history.count - 1 {
                        historyPos += 1
                        input = history[historyPos]
                    } else {
                        historyPos = history.count
                        input = ""
                    }
                    return .handled
                }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var placeholder: String {
        switch buffer.kind {
        case .server: return "Type /command (e.g. /join #swift)…"
        case .channel: return "Message \(buffer.name) — or /command"
        case .query: return "Message \(buffer.name) — or /command"
        }
    }

    private func submit() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        history.append(text)
        if history.count > 200 { history.removeFirst() }
        historyPos = history.count
        model.sendInput(text)
        input = ""
        completion = nil
    }

    private func performTabComplete() {
        // Cycle through candidates if a completion is still active.
        if let c = completion, !c.candidates.isEmpty {
            let expected = c.typedPrefix + c.candidates[c.index] + c.suffix
            if input == expected {
                var next = c
                next.index = (c.index + 1) % c.candidates.count
                input = c.typedPrefix + c.candidates[next.index] + c.suffix
                completion = next
                return
            }
        }

        // Fresh completion: pull the trailing word (text after the last space).
        let spaceIdx = input.lastIndex(of: " ")
        let typedPrefix: String
        let partial: String
        if let spaceIdx {
            typedPrefix = String(input[...spaceIdx])
            partial = String(input[input.index(after: spaceIdx)...])
        } else {
            typedPrefix = ""
            partial = input
        }
        guard !partial.isEmpty else { return }

        // Candidate pool: channel user list for channels, the other party for
        // queries, plus own nick. Deduped case-insensitively, prefix-matched.
        var pool = buffer.users
        if buffer.kind == .query { pool.append(buffer.name) }
        pool.append(model.nick)
        let partialLower = partial.lowercased()
        var seen = Set<String>()
        let candidates = pool
            .filter { $0.lowercased().hasPrefix(partialLower) }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.lowercased() < $1.lowercased() }

        guard let first = candidates.first else { return }
        let suffix = typedPrefix.isEmpty ? ": " : " "
        input = typedPrefix + first + suffix
        completion = TabCompletion(
            typedPrefix: typedPrefix,
            partial: partial,
            candidates: candidates,
            index: 0,
            suffix: suffix
        )
    }
}

struct MessageRow: View {
    @EnvironmentObject var model: ChatModel
    let line: ChatLine

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let badge = leadingBadge {
                Text(badge.glyph).foregroundStyle(badge.color).font(.system(.caption, design: .monospaced))
            } else {
                Text(Self.timeFmt.string(from: line.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
            if leadingBadge != nil {
                Text(Self.timeFmt.string(from: line.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(.vertical, leadingBadge != nil ? 2 : 0)
        .padding(.horizontal, leadingBadge != nil ? 4 : 0)
        .background(highlightBackground)
        .overlay(alignment: .leading) {
            if let badge = leadingBadge {
                Rectangle().fill(badge.color).frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .textSelection(.enabled)
    }

    private struct HighlightBadge {
        let glyph: String
        let color: Color
    }

    // Mention takes precedence over watchlist highlight when both apply.
    private var leadingBadge: HighlightBadge? {
        if line.isMention { return HighlightBadge(glyph: "@", color: .orange) }
        if isFromWatchedUser { return HighlightBadge(glyph: "★", color: .purple) }
        return nil
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if line.isMention {
            Color.orange.opacity(0.18)
        } else if isFromWatchedUser {
            Color.purple.opacity(0.12)
        } else {
            Color.clear
        }
    }

    private var isFromWatchedUser: Bool {
        let watched = Set(model.watchlist.watched.map { $0.lowercased() })
        switch line.kind {
        case .privmsg(let nick, let isSelf) where !isSelf:
            return watched.contains(nick.lowercased())
        case .action(let nick):
            return watched.contains(nick.lowercased())
        case .join(let nick), .part(let nick, _), .quit(let nick, _):
            return watched.contains(nick.lowercased())
        default:
            return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch line.kind {
        case .info:
            Text("— \(line.text)")
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        case .error:
            Text("! \(line.text)")
                .foregroundStyle(.red)
                .font(.system(.body, design: .monospaced))
        case .motd:
            Text(line.text)
                .foregroundStyle(.secondary)
                .font(.system(.callout, design: .monospaced))
        case .privmsg(let nick, let isSelf):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("<\(nick)>")
                    .foregroundStyle(isSelf ? .accentColor : colorForNick(nick))
                    .font(.system(.body, design: .monospaced))
                Text(IRCFormatter.renderWithLinks(line.text))
                    .font(.system(.body))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .action(let nick):
            (Text("* \(nick) ").foregroundStyle(colorForNick(nick)).italic()
             + Text(IRCFormatter.renderWithLinks(line.text)).italic())
        case .notice(let from):
            (Text("-\(from)- ").foregroundStyle(.purple).font(.system(.body, design: .monospaced))
             + Text(IRCFormatter.renderWithLinks(line.text, linkColor: .purple))
                .font(.system(.body, design: .monospaced)))
        case .join(let nick):
            Text("→ \(nick) joined")
                .foregroundStyle(.green)
                .font(.system(.caption, design: .monospaced))
        case .part(let nick, let reason):
            Text("← \(nick) left\(reason.map { " (\($0))" } ?? "")")
                .foregroundStyle(.orange)
                .font(.system(.caption, design: .monospaced))
        case .quit(let nick, let reason):
            Text("← \(nick) quit\(reason.map { " (\($0))" } ?? "")")
                .foregroundStyle(.orange)
                .font(.system(.caption, design: .monospaced))
        case .nick(let old, let new):
            Text("\(old) → \(new)")
                .foregroundStyle(.blue)
                .font(.system(.caption, design: .monospaced))
        case .topic:
            Text(line.text)
                .foregroundStyle(.blue)
                .font(.system(.body, design: .monospaced))
        case .raw:
            Text(line.text)
                .foregroundStyle(.secondary)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func colorForNick(_ nick: String) -> Color {
        let palette: [Color] = [.pink, .teal, .indigo, .mint, .orange, .cyan, .brown, .purple]
        var hash: UInt32 = 2166136261
        for b in nick.utf8 {
            hash = (hash ^ UInt32(b)) &* 16777619
        }
        return palette[Int(hash % UInt32(palette.count))]
    }
}

struct RawLogView: View {
    @EnvironmentObject var model: ChatModel
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Raw Protocol Log").font(.headline)
                Spacer()
                Button("Clear") { model.rawLog.removeAll() }
                Button("Close") { model.showRawLog = false }
            }
            .padding()
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.rawLog.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.hasPrefix(">>") ? .blue : .primary)
                                .textSelection(.enabled)
                                .id(i)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.rawLog.count) { _, _ in
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 440)
    }
}
