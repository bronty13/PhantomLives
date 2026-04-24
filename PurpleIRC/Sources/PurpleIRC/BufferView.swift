import SwiftUI

struct BufferView: View {
    @EnvironmentObject var model: ChatModel
    let bufferIndex: Int

    @State private var input: String = ""
    @State private var history: [String] = []
    @State private var historyPos: Int = 0
    @State private var completion: TabCompletion? = nil

    // Find-in-buffer state. ⌘F opens the bar, ⌘G cycles matches, Esc closes.
    @State private var showFind: Bool = false
    @State private var findQuery: String = ""
    @State private var findMatchIDs: [UUID] = []
    @State private var findMatchCursor: Int = 0
    @FocusState private var findFocused: Bool

    // Topic editor. Click the header topic to open an inline editor.
    @State private var editingTopic: Bool = false
    @State private var topicDraft: String = ""

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
            if showFind {
                findBar
                Divider()
            }
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
        .background(
            // Invisible shortcut surface: ⌘F / ⌘G / Esc handled here so the
            // textfield doesn't have to be focused for the global open/cycle.
            Button("") { toggleFind() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        )
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in buffer", text: $findQuery)
                .textFieldStyle(.plain)
                .focused($findFocused)
                .onSubmit { cycleFind(forward: true) }
                .onChange(of: findQuery) { _, _ in recomputeFindMatches() }
                .onKeyPress(.escape) {
                    closeFind(); return .handled
                }
            if !findMatchIDs.isEmpty {
                Text("\(findMatchCursor + 1) / \(findMatchIDs.count)")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !findQuery.isEmpty {
                Text("no matches").font(.caption).foregroundStyle(.secondary)
            }
            Button(action: { cycleFind(forward: false) }) {
                Image(systemName: "chevron.up")
            }.disabled(findMatchIDs.isEmpty)
            Button(action: { cycleFind(forward: true) }) {
                Image(systemName: "chevron.down")
            }
            .disabled(findMatchIDs.isEmpty)
            .keyboardShortcut("g", modifiers: .command)
            Button(action: closeFind) { Image(systemName: "xmark") }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName).foregroundStyle(.secondary)
            Text(buffer.displayName).font(.headline)
            if editingTopic {
                TextField("Channel topic", text: $topicDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitTopicEdit() }
                    .onKeyPress(.escape) {
                        editingTopic = false; return .handled
                    }
                Button("Set") { commitTopicEdit() }
                Button("Cancel") { editingTopic = false }
            } else {
                if buffer.isChannel {
                    Button(action: beginTopicEdit) {
                        Text(buffer.topic.isEmpty ? "(no topic — click to set)" : "— \(buffer.topic)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.plain)
                    .help("Click to edit topic")
                } else if !buffer.topic.isEmpty {
                    Text("— \(buffer.topic)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            Button(action: toggleFind) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Find in buffer (⌘F)")
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

    private func beginTopicEdit() {
        topicDraft = buffer.topic
        editingTopic = true
    }

    private func commitTopicEdit() {
        let t = topicDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingTopic = false
        guard buffer.isChannel else { return }
        if t.isEmpty {
            model.sendInput("/topic")
        } else {
            model.sendInput("/topic \(t)")
        }
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
                        MessageRow(line: line, highlight: isFindMatch(line.id))
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: buffer.lines.count) { _, _ in
                // New messages land during a find — recompute so the match
                // count stays accurate.
                if !findQuery.isEmpty { recomputeFindMatches() }
                if !showFind {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: findMatchCursor) { _, _ in
                guard !findMatchIDs.isEmpty,
                      findMatchCursor < findMatchIDs.count else { return }
                let id = findMatchIDs[findMatchCursor]
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func isFindMatch(_ id: UUID) -> Bool {
        guard !findMatchIDs.isEmpty,
              findMatchCursor < findMatchIDs.count else { return false }
        return findMatchIDs[findMatchCursor] == id
    }

    // MARK: - Find

    private func toggleFind() {
        if showFind { closeFind() } else { openFind() }
    }

    private func openFind() {
        showFind = true
        findFocused = true
        recomputeFindMatches()
    }

    private func closeFind() {
        showFind = false
        findQuery = ""
        findMatchIDs = []
        findMatchCursor = 0
    }

    private func recomputeFindMatches() {
        let q = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            findMatchIDs = []
            findMatchCursor = 0
            return
        }
        let lower = q.lowercased()
        // Match against the stripped text (no mIRC codes) so the user searches
        // what they see, not the raw wire bytes.
        findMatchIDs = buffer.lines
            .filter { IRCFormatter.stripCodes($0.text).lowercased().contains(lower) }
            .map { $0.id }
        findMatchCursor = 0
    }

    private func cycleFind(forward: Bool) {
        guard !findMatchIDs.isEmpty else { return }
        let n = findMatchIDs.count
        findMatchCursor = forward
            ? (findMatchCursor + 1) % n
            : (findMatchCursor - 1 + n) % n
    }

    private var userListPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Users (\(buffer.users.count))")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            List(buffer.users, id: \.self) { user in
                Text(user)
                    .font(.system(.body, design: .monospaced))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        // Double-click opens a private query with this nick.
                        model.sendInput("/query \(stripModePrefix(user))")
                    }
                    .contextMenu { userContextMenu(for: user) }
            }
            .listStyle(.plain)
        }
    }

    /// Right-click / long-press menu on a nick in the user list. Op/kick/etc.
    /// are all just /commands in the background so the command log stays the
    /// single source of truth.
    @ViewBuilder
    private func userContextMenu(for user: String) -> some View {
        let nick = stripModePrefix(user)
        Button("Open query") { model.sendInput("/query \(nick)") }
        Button("WHOIS") { model.sendInput("/whois \(nick)") }
        Divider()
        Button("Op (+o)") { model.sendInput("/op \(nick)") }
        Button("Deop (-o)") { model.sendInput("/deop \(nick)") }
        Button("Voice (+v)") { model.sendInput("/voice \(nick)") }
        Button("Devoice (-v)") { model.sendInput("/devoice \(nick)") }
        Divider()
        Button("Kick") { model.sendInput("/kick \(nick)") }
        Button("Ban") { model.sendInput("/ban \(nick)!*@*") }
        Divider()
        Button("Ignore") { model.sendInput("/ignore \(nick)!*@*") }
    }

    /// Channel user lists may include `@` / `+` / `%` prefixes — strip them
    /// before using the nick in a command.
    private func stripModePrefix(_ nick: String) -> String {
        let prefixes: Set<Character> = ["@", "+", "%", "~", "&"]
        var s = nick
        while let first = s.first, prefixes.contains(first) { s.removeFirst() }
        return s
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if showingCommandHints {
                commandHintBar
                    .transition(.opacity)
            }
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
    }

    // MARK: - Slash-command hint bar

    /// Shown above the input when the user is typing a slash command — we
    /// surface matching commands so /help isn't needed for routine lookups.
    private var showingCommandHints: Bool {
        guard input.hasPrefix("/"), !input.contains(" ") else { return false }
        return !commandHintMatches.isEmpty
    }

    /// Matches for the current /prefix. Cached via a computed property to
    /// avoid rebuilding on unrelated @State changes.
    private var commandHintMatches: [CommandCatalog.Entry] {
        let typed = String(input.dropFirst())  // drop the leading "/"
        return Array(CommandCatalog.matches(prefix: typed).prefix(6))
    }

    @ViewBuilder
    private var commandHintBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "command").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(commandHintMatches) { entry in
                        Button {
                            // Click a chip → complete to "/name " so the user
                            // can keep typing args without editing.
                            input = "/\(entry.id) "
                            completion = nil
                        } label: {
                            HStack(spacing: 4) {
                                Text("/\(entry.id)")
                                    .font(.system(.caption, design: .monospaced).bold())
                                if !entry.args.isEmpty {
                                    Text(entry.args)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .help(entry.summary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Tab to complete · /help for details")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .underPageBackgroundColor))
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

        // Slash-command completion path: when the line is just "/partial"
        // with no space yet, cycle through matching commands instead of
        // falling back to nick completion.
        if input.hasPrefix("/"), !input.contains(" ") {
            let typed = String(input.dropFirst())
            let cmds = CommandCatalog.matches(prefix: typed).map { $0.id }
            guard let first = cmds.first else { return }
            input = "/\(first) "
            completion = TabCompletion(
                typedPrefix: "/",
                partial: typed,
                candidates: cmds,
                index: 0,
                suffix: " "
            )
            return
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
    var highlight: Bool = false

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
        if matchedRule != nil { return HighlightBadge(glyph: "●", color: ruleColor ?? .yellow) }
        if isFromWatchedUser { return HighlightBadge(glyph: "★", color: .purple) }
        return nil
    }

    @ViewBuilder
    private var highlightBackground: some View {
        let theme = model.theme
        if highlight {
            theme.findBackground
        } else if line.isMention {
            theme.mentionBackground
        } else if let color = ruleColor {
            color.opacity(0.18)
        } else if matchedRule != nil {
            theme.mentionBackground
        } else if isFromWatchedUser {
            theme.watchlistBackground
        } else {
            Color.clear
        }
    }

    /// Resolve the HighlightRule tagged on this line (if any) via the shared
    /// settings store. Returns nil when the rule has been deleted since the
    /// line was rendered.
    private var matchedRule: HighlightRule? {
        guard let id = line.highlightRuleID else { return nil }
        return model.settings.settings.highlightRules.first { $0.id == id }
    }

    /// Parsed Color from the matched rule's `colorHex`. Nil when the rule has
    /// no custom color (fall back to mentionBackground) or the hex is malformed.
    private var ruleColor: Color? {
        guard let rule = matchedRule, let hex = rule.colorHex else { return nil }
        return Color(hex: hex)
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
        let theme = model.theme
        switch line.kind {
        case .info:
            Text("— \(line.text)")
                .foregroundStyle(theme.infoColor)
                .font(.system(.body, design: .monospaced))
        case .error:
            Text("! \(line.text)")
                .foregroundStyle(theme.errorColor)
                .font(.system(.body, design: .monospaced))
        case .motd:
            Text(line.text)
                .foregroundStyle(theme.motdColor)
                .font(.system(.callout, design: .monospaced))
        case .privmsg(let nick, let isSelf):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("<\(nick)>")
                    .foregroundStyle(isSelf ? theme.ownNickColor : colorForNick(nick, theme: theme))
                    .font(.system(.body, design: .monospaced))
                Text(renderedText(linkColor: .accentColor))
                    .font(.system(.body))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .action(let nick):
            (Text("* \(nick) ").foregroundStyle(colorForNick(nick, theme: theme)).italic()
             + Text(renderedText(linkColor: .accentColor)).italic())
        case .notice(let from):
            (Text("-\(from)- ").foregroundStyle(theme.noticeColor).font(.system(.body, design: .monospaced))
             + Text(renderedText(linkColor: theme.noticeColor))
                .font(.system(.body, design: .monospaced)))
        case .join(let nick):
            Text("→ \(nick) joined")
                .foregroundStyle(theme.joinColor)
                .font(.system(.caption, design: .monospaced))
        case .part(let nick, let reason):
            Text("← \(nick) left\(reason.map { " (\($0))" } ?? "")")
                .foregroundStyle(theme.partColor)
                .font(.system(.caption, design: .monospaced))
        case .quit(let nick, let reason):
            Text("← \(nick) quit\(reason.map { " (\($0))" } ?? "")")
                .foregroundStyle(theme.partColor)
                .font(.system(.caption, design: .monospaced))
        case .nick(let old, let new):
            Text("\(old) → \(new)")
                .foregroundStyle(theme.nickNickColor)
                .font(.system(.caption, design: .monospaced))
        case .topic:
            Text(line.text)
                .foregroundStyle(theme.nickNickColor)
                .font(.system(.body, design: .monospaced))
        case .raw:
            Text(line.text)
                .foregroundStyle(theme.infoColor)
                .font(.system(.caption, design: .monospaced))
        }
    }

    /// IRCFormatter render + URL detect + optional highlight-rule word tint.
    /// Pulled into one helper so privmsg/action/notice all share the overlay.
    private func renderedText(linkColor: Color) -> AttributedString {
        let base = IRCFormatter.renderWithLinks(line.text, linkColor: linkColor)
        guard !line.highlightRanges.isEmpty, let rule = matchedRule else { return base }
        // Explicit rule color wins; otherwise fall back to something visible
        // against both light and dark themes.
        let color = rule.colorHex.flatMap { Color(hex: $0) } ?? .orange
        return IRCFormatter.overlayHighlights(base, ranges: line.highlightRanges, color: color)
    }

    private func colorForNick(_ nick: String, theme: Theme) -> Color {
        var hash: UInt32 = 2166136261
        for b in nick.utf8 {
            hash = (hash ^ UInt32(b)) &* 16777619
        }
        let palette = theme.nickPalette
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
