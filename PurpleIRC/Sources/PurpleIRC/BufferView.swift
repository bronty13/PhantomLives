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

    // Slash-command picker state.
    @State private var commandSuggestionIndex: Int = 0
    /// Input string at the moment the user pressed Esc — keeps the picker
    /// dismissed until they edit the input again. Reset whenever the input
    /// changes shape.
    @State private var pickerDismissedFor: String? = nil

    /// Drives focus on the input field. Granted on appear, when the buffer
    /// changes, and when the app re-activates so the user can always start
    /// typing without clicking first.
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    struct TabCompletion {
        let typedPrefix: String   // text before the completed word (includes trailing space when non-empty)
        let partial: String       // original partial the user typed (before first tab)
        let candidates: [String]  // sorted matching nicks
        var index: Int
        let suffix: String        // ": " when first word, " " otherwise
    }

    /// Defensive bounds-check — when the active buffer is removed (e.g.
    /// the user picks "Leave channel" from the sidebar context menu),
    /// SwiftUI can briefly re-evaluate this view's body with a stale
    /// `bufferIndex` before ContentView swaps in a new BufferView. A
    /// force-subscript would crash on that one frame; the placeholder
    /// disappears in the very next render pass.
    var buffer: Buffer {
        let bs = model.buffers
        if bufferIndex < bs.count { return bs[bufferIndex] }
        return Buffer(name: "", kind: .server)
    }

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
            // Theme-driven surface — fixed themes (Solarized, Sepia, Dracula,
            // Paper, etc.) supply their own colour; "follow OS" themes
            // (Classic, High Contrast) fall through to .textBackgroundColor.
            .background(model.theme.chatBackground)
            .foregroundStyle(model.theme.chatForeground)
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
            // Rank-sorted so ops cluster at the top — matches every classic
            // IRC client and makes scanning for chanops much faster.
            List(buffer.usersSortedByRank, id: \.self) { user in
                userRow(user)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        model.sendInput("/query \(stripModePrefix(user))")
                    }
                    .contextMenu { userContextMenu(for: user) }
            }
            .listStyle(.plain)
        }
    }

    /// One row in the user list: fixed-width mode glyph (so nicks align)
    /// + nick text. Glyph takes its colour from the rank so a glance at
    /// the list tells you who the operators / voiced users are.
    @ViewBuilder
    private func userRow(_ user: String) -> some View {
        let mode = buffer.highestMode(for: user)
        let symbol: String = {
            guard let mode, let glyph = Buffer.modeSymbol[mode] else { return " " }
            return String(glyph)
        }()
        HStack(spacing: 4) {
            Text(symbol)
                .font(model.chatFont.bold())
                .foregroundStyle(Self.colorForMode(mode))
                .frame(width: 12, alignment: .center)
            Text(user)
                .font(model.chatFont)
                .foregroundStyle(mode == nil ? .primary : Self.colorForMode(mode))
        }
    }

    /// Colour palette for rank glyphs. Picked to read on both light and dark
    /// themes without being too loud — op orange is the anchor because it's
    /// by far the most common privileged rank in real channels.
    private static func colorForMode(_ mode: Character?) -> Color {
        switch mode {
        case "q": return .purple     // ~ owner
        case "a": return .red        // & admin
        case "o": return .orange     // @ op
        case "h": return Color(red: 0.80, green: 0.65, blue: 0.20) // % halfop (muted yellow)
        case "v": return .blue       // + voice
        default:  return .primary
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
                commandSuggestionList
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                Text("\(model.nick):")
                    .foregroundStyle(.secondary)
                    .font(model.chatFont)
                TextField(placeholder, text: $input)
                    .textFieldStyle(.plain)
                    .font(model.chatFont)
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .onChange(of: input) { oldValue, newValue in
                        // Tab-completion invalidation.
                        if let c = completion, !input.hasSuffix(c.suffix)
                            || !input.dropLast(c.suffix.count).hasSuffix(c.candidates[c.index]) {
                            completion = nil
                        }
                        // Any edit re-engages the slash picker that the user
                        // might have dismissed earlier — only the *exact*
                        // dismissed string keeps it hidden.
                        if newValue != pickerDismissedFor {
                            pickerDismissedFor = nil
                        }
                        // Reset highlight when the matching set changes.
                        if oldValue != newValue {
                            commandSuggestionIndex = 0
                        }
                    }
                    .onKeyPress(.tab) {
                        if showingCommandHints, let pick = currentSuggestion() {
                            commit(suggestion: pick)
                            return .handled
                        }
                        performTabComplete()
                        return .handled
                    }
                    // Return must be intercepted *before* onSubmit so a
                    // highlighted suggestion gets applied instead of sent
                    // verbatim. When the picker isn't open we return .ignored
                    // so SwiftUI's onSubmit fires as normal.
                    .onKeyPress(.return) {
                        if showingCommandHints, let pick = currentSuggestion() {
                            commit(suggestion: pick)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if showingCommandHints {
                            commandSuggestionIndex = max(0, commandSuggestionIndex - 1)
                            return .handled
                        }
                        if !history.isEmpty, historyPos > 0 {
                            historyPos -= 1
                            input = history[historyPos]
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if showingCommandHints {
                            commandSuggestionIndex = min(commandHintMatches.count - 1, commandSuggestionIndex + 1)
                            return .handled
                        }
                        if historyPos < history.count - 1 {
                            historyPos += 1
                            input = history[historyPos]
                        } else {
                            historyPos = history.count
                            input = ""
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if showingCommandHints {
                            // Stash the current input string so the picker
                            // stays dismissed until the user types more.
                            pickerDismissedFor = input
                            return .handled
                        }
                        return .ignored
                    }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .task { inputFocused = true }
        .onChange(of: bufferIndex) { _, _ in inputFocused = true }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { inputFocused = true }
        }
    }

    // MARK: - Slash-command picker

    /// Vertical picker visible only when (a) the input is `/something` with
    /// no space yet, (b) it matches at least one command, and (c) the user
    /// hasn't pressed Esc on the current input. Same shape as Claude's
    /// slash menu — arrow keys move highlight, Enter / Tab commit.
    private var showingCommandHints: Bool {
        guard input.hasPrefix("/"), !input.contains(" ") else { return false }
        guard pickerDismissedFor != input else { return false }
        return !commandHintMatches.isEmpty
    }

    /// Matches for the current /prefix. Cached via a computed property so
    /// SwiftUI's diffing doesn't recompute on unrelated state changes.
    private var commandHintMatches: [CommandCatalog.Entry] {
        let typed = String(input.dropFirst())  // drop the leading "/"
        return Array(CommandCatalog.matches(prefix: typed).prefix(8))
    }

    /// Whichever entry the highlight cursor is currently on — nil if the
    /// list is empty or the cursor somehow drifted out of bounds.
    private func currentSuggestion() -> CommandCatalog.Entry? {
        let m = commandHintMatches
        guard !m.isEmpty else { return nil }
        return m[min(max(0, commandSuggestionIndex), m.count - 1)]
    }

    /// Replace the typed `/prefix` with `/cmd ` so the user can keep
    /// typing args. Resets every related state knob.
    private func commit(suggestion entry: CommandCatalog.Entry) {
        input = "/\(entry.id) "
        completion = nil
        pickerDismissedFor = nil
        commandSuggestionIndex = 0
    }

    @ViewBuilder
    private var commandSuggestionList: some View {
        let matches = commandHintMatches
        VStack(spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                suggestionRow(entry, isSelected: index == commandSuggestionIndex) {
                    commandSuggestionIndex = index
                    commit(suggestion: entry)
                }
                if index < matches.count - 1 {
                    Divider()
                }
            }
            Divider()
            HStack {
                Text("↑↓ to move · ⏎ Tab to commit · Esc to dismiss")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("/help for details")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .shadow(color: .black.opacity(0.08), radius: 4, y: -1)
    }

    @ViewBuilder
    private func suggestionRow(_ entry: CommandCatalog.Entry,
                               isSelected: Bool,
                               onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("/\(entry.id)")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                if !entry.args.isEmpty {
                    Text(entry.args)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                }
                Spacer()
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        pickerDismissedFor = nil
        // Keep focus after sending so the next message is one keystroke away.
        inputFocused = true
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
                Text(badge.glyph).foregroundStyle(badge.color).font(model.chatCaptionFont)
            } else {
                Text(Self.timeFmt.string(from: line.timestamp))
                    .font(model.chatCaptionFont)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
            if leadingBadge != nil {
                Text(Self.timeFmt.string(from: line.timestamp))
                    .font(model.chatCaptionFont)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(.vertical, leadingBadge != nil ? 2 : (model.settings.settings.relaxedRowSpacing ? 3 : 0))
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
                .font(model.chatFont)
        case .error:
            Text("! \(line.text)")
                .foregroundStyle(theme.errorColor)
                .font(model.chatFont)
        case .motd:
            Text(line.text)
                .foregroundStyle(theme.motdColor)
                .font(model.chatFont)
        case .privmsg(let nick, let isSelf):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("<\(nick)>")
                    .foregroundStyle(isSelf ? theme.ownNickColor : colorForNick(nick, theme: theme))
                    .font(model.chatFont)
                Text(renderedText(linkColor: .accentColor))
                    .font(.system(.body))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .action(let nick):
            (Text("* \(nick) ").foregroundStyle(colorForNick(nick, theme: theme)).italic()
             + Text(renderedText(linkColor: .accentColor)).italic())
        case .notice(let from):
            (Text("-\(from)- ").foregroundStyle(theme.noticeColor).font(model.chatFont)
             + Text(renderedText(linkColor: theme.noticeColor))
                .font(model.chatFont))
        case .join(let nick):
            Text("→ \(nick) joined")
                .foregroundStyle(theme.joinColor)
                .font(model.chatCaptionFont)
        case .part(let nick, let reason):
            Text("← \(nick) left\(reason.map { " (\($0))" } ?? "")")
                .foregroundStyle(theme.partColor)
                .font(model.chatCaptionFont)
        case .quit(let nick, let reason):
            Text("← \(nick) quit\(reason.map { " (\($0))" } ?? "")")
                .foregroundStyle(theme.partColor)
                .font(model.chatCaptionFont)
        case .nick(let old, let new):
            Text("\(old) → \(new)")
                .foregroundStyle(theme.nickNickColor)
                .font(model.chatCaptionFont)
        case .topic:
            Text(line.text)
                .foregroundStyle(theme.nickNickColor)
                .font(model.chatFont)
        case .raw:
            Text(line.text)
                .foregroundStyle(theme.infoColor)
                .font(model.chatCaptionFont)
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
                                .font(model.chatCaptionFont)
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
