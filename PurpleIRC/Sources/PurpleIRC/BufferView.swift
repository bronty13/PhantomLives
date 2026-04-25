import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

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

    /// Multi-line paste detection. When the user pastes content with a
    /// newline, we stash it here and show a confirmation dialog instead of
    /// flooding the channel — most servers throttle or kick on bursts.
    @State private var pastedMultiline: String? = nil
    /// "Send line by line" sheet. Editable so the user can prune lines or
    /// add a /command line wrapper before sending.
    @State private var showingMultilineEditor: Bool = false
    @State private var multilineEditorText: String = ""

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

    /// Rendered row stream — either a real chat line or a synthetic summary
    /// row produced by collapsing consecutive join/part/quit/nick lines.
    /// SwiftUI's ForEach diffs on the `id`, so summaries reuse the first
    /// member's UUID as a stable key.
    enum RenderedRow: Identifiable {
        case line(ChatLine)
        case summary(id: UUID, entries: [ChatLine])
        var id: UUID {
            switch self {
            case .line(let l):           return l.id
            case .summary(let id, _):    return id
            }
        }
    }

    /// Walk `buffer.lines` once, coalescing runs of join/part/quit/nick into
    /// a single summary entry. The grouping resets when (a) a non-membership
    /// line breaks the run, (b) the user setting is off, or (c) only one
    /// membership line is in the run (rendering a summary for one event is
    /// noisy). A 5-minute window prevents two unrelated batches separated by
    /// hours of silence from being lumped together.
    private var renderedRows: [RenderedRow] {
        let lines = buffer.lines
        guard model.settings.settings.collapseJoinPart else {
            return lines.map { .line($0) }
        }
        var out: [RenderedRow] = []
        out.reserveCapacity(lines.count)
        var run: [ChatLine] = []
        for line in lines {
            if Self.isMembershipKind(line.kind),
               (run.isEmpty || line.timestamp.timeIntervalSince(run.last!.timestamp) < 300) {
                run.append(line)
                continue
            }
            flushRun(&run, into: &out)
            out.append(.line(line))
        }
        flushRun(&run, into: &out)
        return out
    }

    private func flushRun(_ run: inout [ChatLine], into out: inout [RenderedRow]) {
        defer { run.removeAll(keepingCapacity: false) }
        guard !run.isEmpty else { return }
        // Single-event runs render as the original line — a "1 user joined"
        // pill is more noise than the raw line.
        if run.count == 1 {
            out.append(.line(run[0]))
            return
        }
        out.append(.summary(id: run[0].id, entries: run))
    }

    private static func isMembershipKind(_ kind: ChatLine.Kind) -> Bool {
        switch kind {
        case .join, .part, .quit, .nick: return true
        default:                          return false
        }
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
            // When more than one connection is live, surface the network
            // the active buffer belongs to. Otherwise "alice on Undernet"
            // and "alice on Dalnet" look identical in the header.
            if model.connections.count > 1, let conn = model.activeConnection {
                Text("on \(conn.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
                    ForEach(renderedRows) { row in
                        switch row {
                        case .line(let line):
                            MessageRow(line: line, highlight: isFindMatch(line.id))
                                .id(line.id)
                        case .summary(let id, let entries):
                            JoinPartSummaryRow(entries: entries)
                                .id(id)
                        }
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
        let isAway = isAway(stripModePrefix(user))
        HStack(spacing: 4) {
            Text(symbol)
                .font(model.chatFont.bold())
                .foregroundStyle(Self.colorForMode(mode))
                .frame(width: 12, alignment: .center)
            // Single-line + truncation prevents long nicks from wrapping
            // inside the fixed-width user list pane (~180pt). Tooltip
            // surfaces the full nick on hover so nothing is hidden.
            Text(user)
                .font(model.chatFont)
                .foregroundStyle(mode == nil ? .primary : Self.colorForMode(mode))
                .opacity(isAway ? 0.45 : 1.0)
                .strikethrough(isAway, color: .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(user)
            if isAway {
                Image(systemName: "moon.zzz.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// Lookup against the active connection's `awayByNick` map (populated by
    /// the IRCv3 `away-notify` cap). Falls back to false when we don't know.
    private func isAway(_ nick: String) -> Bool {
        guard let conn = model.activeConnection else { return false }
        return conn.awayByNick[nick.lowercased()] != nil
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
        // WHOIS / WHOWAS replies are mirrored back to this channel
        // automatically (registerWhoisOrigin in IRCConnection), so the
        // user sees the answer without leaving the buffer.
        Button("WHOIS \(nick)") { model.sendInput("/whois \(nick)") }
        Button("WHOWAS \(nick)") { model.sendInput("/whowas \(nick)") }
        Divider()
        if isInAddressBook(nick) {
            Button("Remove from address book") {
                removeFromAddressBook(nick)
            }
        } else {
            Button("Add to address book (notify when online)") {
                addToAddressBook(nick, watch: true)
            }
            Button("Add to address book") {
                addToAddressBook(nick, watch: false)
            }
        }
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

    /// Look up whether the nick already exists in the user's address book.
    /// Case-insensitive match — IRC nicks are case-insensitive on the wire.
    private func isInAddressBook(_ nick: String) -> Bool {
        model.settings.settings.addressBook.contains {
            $0.nick.caseInsensitiveCompare(nick) == .orderedSame
        }
    }

    /// Add a nick to the address book with the given watch flag. If a
    /// matching entry already exists this is a no-op (callers gate on
    /// `isInAddressBook` already).
    private func addToAddressBook(_ nick: String, watch: Bool) {
        guard !isInAddressBook(nick) else { return }
        var entry = AddressEntry()
        entry.nick = nick
        entry.watch = watch
        model.settings.upsertAddress(entry)
    }

    /// Remove every address-book entry whose nick matches (case-insensitive).
    private func removeFromAddressBook(_ nick: String) {
        let matches = model.settings.settings.addressBook.filter {
            $0.nick.caseInsensitiveCompare(nick) == .orderedSame
        }
        for entry in matches {
            model.settings.removeAddress(id: entry.id)
        }
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
                    // Background anchor that flips on continuous spell-check
                    // on the window's shared field editor. Every TextField
                    // in this window inherits the underline behaviour for
                    // the rest of the session.
                    .background(SpellCheckActivator())
                    .onSubmit(submit)
                    .onChange(of: input) { oldValue, newValue in
                        // Multi-line paste detection. SwiftUI TextField
                        // collapses pasted text into a single line on macOS
                        // 14+, but a paste of "a\nb\nc" arrives here intact.
                        // Catch it before the user accidentally floods the
                        // channel — present a confirmation with options.
                        if newValue.contains("\n") || newValue.contains("\r") {
                            pastedMultiline = newValue
                            input = ""
                            return
                        }
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
        // Initial focus on appear + after every situation that could
        // steal it away (buffer switch, app/window activation, scene
        // phase change). Runs through `refocusInput` so the false→true
        // refresh trick fires even when @FocusState was already true.
        .task { refocusInput() }
        .onChange(of: bufferIndex) { _, _ in refocusInput() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refocusInput() }
        }
        // macOS scenePhase is iOS-flavoured and doesn't fire reliably for
        // Cmd+Tab activation, so subscribe to AppKit's own signals too.
        // Either notification firing is enough; both are belt-and-suspenders.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refocusInput()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in
            refocusInput()
        }
        .confirmationDialog(
            "Paste \(multilineLineCount) lines?",
            isPresented: Binding(
                get: { pastedMultiline != nil },
                set: { if !$0 { pastedMultiline = nil } }),
            titleVisibility: .visible
        ) {
            Button("Send all \(multilineLineCount) lines") {
                if let text = pastedMultiline { sendLines(text) }
                pastedMultiline = nil
            }
            Button("Open multi-line editor…") {
                multilineEditorText = pastedMultiline ?? ""
                pastedMultiline = nil
                showingMultilineEditor = true
            }
            Button("Cancel", role: .cancel) {
                pastedMultiline = nil
            }
        } message: {
            Text("Sending each line as a separate message will likely flood the channel. Most servers will throttle or disconnect.")
        }
        .sheet(isPresented: $showingMultilineEditor) {
            MultilineEditorSheet(
                text: $multilineEditorText,
                onSend: { text in
                    sendLines(text)
                    showingMultilineEditor = false
                },
                onCancel: { showingMultilineEditor = false }
            )
        }
    }

    /// Number of non-empty lines in the pending paste, for the confirmation
    /// dialog title. Trailing blank lines are ignored — most pastes end with
    /// a newline that would otherwise inflate the count.
    private var multilineLineCount: Int {
        guard let text = pastedMultiline else { return 0 }
        return text.split(omittingEmptySubsequences: true,
                          whereSeparator: { $0 == "\n" || $0 == "\r" }).count
    }

    /// Send a multi-line block one PRIVMSG at a time. Empty lines are
    /// dropped. Each line goes through `model.sendInput` so /commands
    /// embedded in the paste still work.
    private func sendLines(_ text: String) {
        let lines = text.split(omittingEmptySubsequences: true,
                               whereSeparator: { $0 == "\n" || $0 == "\r" })
        for line in lines {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            model.sendInput(s)
        }
        history.append(text)
        if history.count > 200 { history.removeFirst() }
        historyPos = history.count
    }

    /// Force focus into the input box. SwiftUI ignores `inputFocused = true`
    /// when the state is already true (no-op diff), so the false→true bounce
    /// is required to actually re-grant first-responder when the user
    /// returns to the app. The double-async lets macOS finish its own
    /// first-responder dance before we override.
    private func refocusInput() {
        DispatchQueue.main.async {
            inputFocused = false
            DispatchQueue.main.async {
                inputFocused = true
            }
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
        // refocusInput's false→true bounce makes sure we actually re-grant
        // first-responder even if the FocusState was already true.
        refocusInput()
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

    /// Render the chat-line timestamp using the user's configured
    /// `timestampFormat`. Recomputed per row so changes in Appearance
    /// take effect immediately, no relaunch required. Falls back to the
    /// 24-hour default when the pattern is empty.
    private var formattedTimestamp: String {
        let pattern = model.settings.settings.timestampFormat.isEmpty
            ? "HH:mm:ss"
            : model.settings.settings.timestampFormat
        let f = DateFormatter()
        f.dateFormat = pattern
        return f.string(from: line.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let badge = leadingBadge {
                Text(badge.glyph).foregroundStyle(badge.color).font(model.chatCaptionFont)
            } else {
                timestampText
            }
            if leadingBadge != nil {
                timestampText
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

    /// Timestamp text with size-locked layout. Previously had a fixed
    /// 40 pt frame which was correct for the default 13 pt body but
    /// caused "10:05" to wrap into "10:0\n5" once the user bumped the
    /// chat font size. `lineLimit(1)` + `fixedSize(horizontal:)` lets
    /// the column be exactly as wide as the formatted string and never
    /// any wider, so vertical alignment with messages stays clean.
    private var timestampText: some View {
        Text(formattedTimestamp)
            .font(model.chatCaptionFont)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .monospacedDigit()
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
                nickTag("<\(nick)>", nick: nick,
                        color: isSelf ? theme.ownNickColor : colorForNick(nick, theme: theme),
                        font: model.chatFont,
                        suppressMenu: isSelf)
                Text(renderedText(linkColor: .accentColor))
                    .font(.system(.body))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .action(let nick):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                nickTag("* \(nick) ", nick: nick,
                        color: colorForNick(nick, theme: theme),
                        font: model.chatFont,
                        italic: true)
                Text(renderedText(linkColor: .accentColor)).italic()
            }
        case .notice(let from):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                nickTag("-\(from)- ", nick: from,
                        color: theme.noticeColor,
                        font: model.chatFont)
                Text(renderedText(linkColor: theme.noticeColor))
                    .font(model.chatFont)
            }
        case .join(let nick):
            nickTag("→ \(nick) joined",
                    nick: nick,
                    color: theme.joinColor,
                    font: model.chatCaptionFont)
        case .part(let nick, let reason):
            nickTag("← \(nick) left\(reason.map { " (\($0))" } ?? "")",
                    nick: nick,
                    color: theme.partColor,
                    font: model.chatCaptionFont)
        case .quit(let nick, let reason):
            nickTag("← \(nick) quit\(reason.map { " (\($0))" } ?? "")",
                    nick: nick,
                    color: theme.partColor,
                    font: model.chatCaptionFont)
        case .nick(let old, let new):
            nickTag("\(old) → \(new)",
                    nick: new,
                    color: theme.nickNickColor,
                    font: model.chatCaptionFont)
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

    /// A nick rendered inline in a message row. Identical visual to a plain
    /// styled `Text`, but right-clicking it opens a context menu with WHOIS /
    /// query / op / etc. — same options the user-list pane offers. The
    /// `suppressMenu` flag turns off the menu for the user's own nick on
    /// their own messages so right-clicking on yourself doesn't offer to
    /// kick or ban yourself.
    @ViewBuilder
    private func nickTag(_ text: String, nick: String, color: Color,
                         font: Font, italic: Bool = false,
                         suppressMenu: Bool = false) -> some View {
        let bare = stripModePrefix(nick)
        let body = Text(text)
            .foregroundStyle(color)
            .font(font)
            .italic(italic)
        if suppressMenu {
            body
        } else {
            body
                .contextMenu { nickMenu(for: bare) }
                .help("Right-click for actions on \(bare)")
        }
    }

    /// Strips the leading IRC mode prefix (~ & @ % +) from a nick. The MessageRow
    /// generally receives bare nicks already, but the user-list pane stores
    /// prefixed nicks and we use the same helper everywhere for safety.
    private func stripModePrefix(_ s: String) -> String {
        var r = s
        while let first = r.first, "~&@%+".contains(first) {
            r.removeFirst()
        }
        return r
    }

    /// Right-click menu offered when the user clicks on a nick rendered
    /// inside a message body. Mirrors the user-list-pane menu so muscle
    /// memory carries over from one place to the other.
    @ViewBuilder
    private func nickMenu(for nick: String) -> some View {
        Button("Open query with \(nick)") { model.sendInput("/query \(nick)") }
        Button("WHOIS \(nick)")            { model.sendInput("/whois \(nick)") }
        Button("WHOWAS \(nick)")           { model.sendInput("/whowas \(nick)") }
        Divider()
        Button("CTCP VERSION") { model.sendInput("/ctcp \(nick) VERSION") }
        Button("CTCP PING")    { model.sendInput("/ctcp \(nick) PING \(Int(Date().timeIntervalSince1970))") }
        Divider()
        Button("Op (+o)")     { model.sendInput("/op \(nick)") }
        Button("Voice (+v)")  { model.sendInput("/voice \(nick)") }
        Button("Kick")        { model.sendInput("/kick \(nick)") }
        Button("Ban")         { model.sendInput("/ban \(nick)!*@*") }
        Divider()
        Button("Ignore \(nick)!*@*") { model.sendInput("/ignore \(nick)!*@*") }
        Divider()
        Button("Copy nick") {
            #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(nick, forType: .string)
            #endif
        }
    }
}

/// Compact summary row that replaces a run of consecutive join / part /
/// quit / nick lines. Click to disclose the underlying lines so a curious
/// user can still see who exactly came and went.
struct JoinPartSummaryRow: View {
    let entries: [ChatLine]
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(summary)
                    .font(.system(.callout, design: .default))
                    .foregroundStyle(.secondary)
                    .italic()
                Spacer()
                Text(rangeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }

            if expanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { line in
                        MessageRow(line: line, highlight: false)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.vertical, 1)
    }

    /// Human summary like "3 joined, 2 left, alice→alice_". Counts each
    /// kind separately so a netsplit doesn't read as "5 events".
    private var summary: String {
        var joins = 0, parts = 0, quits = 0
        var renames: [(String, String)] = []
        for e in entries {
            switch e.kind {
            case .join:                       joins += 1
            case .part:                       parts += 1
            case .quit:                       quits += 1
            case .nick(let old, let new):     renames.append((old, new))
            default: break
            }
        }
        var pieces: [String] = []
        if joins > 0 { pieces.append("\(joins) joined") }
        if parts > 0 { pieces.append("\(parts) parted") }
        if quits > 0 { pieces.append("\(quits) quit") }
        if !renames.isEmpty {
            let preview = renames.prefix(2).map { "\($0.0)→\($0.1)" }.joined(separator: ", ")
            let extra = renames.count > 2 ? " (+\(renames.count - 2))" : ""
            pieces.append("renames: \(preview)\(extra)")
        }
        return pieces.joined(separator: " · ")
    }

    private var rangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        guard let first = entries.first?.timestamp,
              let last = entries.last?.timestamp,
              first != last else {
            return entries.first.map { f.string(from: $0.timestamp) } ?? ""
        }
        return "\(f.string(from: first))–\(f.string(from: last))"
    }
}

/// Modal editor for multi-line content the user pasted into the input. They
/// can prune lines, edit them, or just hit Send to deliver every non-empty
/// line one-by-one. Designed for pasting code snippets, ASCII art, etc.
struct MultilineEditorSheet: View {
    @Binding var text: String
    let onSend: (String) -> Void
    let onCancel: () -> Void

    private var nonEmptyLineCount: Int {
        text.split(omittingEmptySubsequences: true,
                   whereSeparator: { $0 == "\n" || $0 == "\r" }).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Multi-line message")
                    .font(.headline)
                Spacer()
                Text("\(nonEmptyLineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            SpellCheckedTextEditor(text: $text)
                .padding(8)

            Divider()

            HStack {
                Text("Each line is sent as a separate message. /commands work too.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Send all") { onSend(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(nonEmptyLineCount == 0)
            }
            .padding()
        }
        .frame(minWidth: 540, minHeight: 320)
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
