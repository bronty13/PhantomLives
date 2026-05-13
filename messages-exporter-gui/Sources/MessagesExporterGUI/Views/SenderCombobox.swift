import SwiftUI

/// Replaces the plain "type a contact name" TextField with a combobox
/// that enumerates conversation partners directly from chat.db (no
/// Contacts.framework, no extra TCC prompt — the existing FDA grant
/// already covers it). Two modes:
///
///   - **Picked sender**: clicking a dropdown row sets `pickedHandle`
///     to that sender's raw chat.db handle. Submitted to the CLI via
///     `--handle` for an exact, unambiguous query.
///   - **Typed fallback**: typing anything else (without picking) clears
///     `pickedHandle` and the typed text is sent as the legacy positional
///     `contact` argument. Same fuzzy-match behavior as before.
///
/// The chevron is the deliberate "browse" action. Live-filter while
/// typing surfaces the dropdown automatically; ⌘. or click-outside
/// dismisses it. Empty input shows the recents list.
struct SenderCombobox: View {
    @Environment(\.missionTheme) private var t

    @Binding var contact: String
    @Binding var pickedHandle: String?

    /// Senders loaded from chat.db (most-recent-first). Empty until the
    /// background load completes — see `.task` below.
    @State private var allSenders: [Sender] = []
    /// One-line message shown under the field when the load fails
    /// (chat.db missing, FDA denied, schema drift). Nil on success.
    @State private var loadDiagnostic: String?
    @State private var isLoading = true
    @State private var isOpen = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            comboField
                // Popover (rather than an inline overlay or ZStack) so
                // the dropdown renders in its own window above every-
                // thing else. Inline rendering loses to the Grid layout:
                // sibling GridRows below the Contact row are drawn after
                // us and end up on top, partially occluding the list.
                // Popover sidesteps that entirely.
                .popover(isPresented: $isOpen,
                         attachmentAnchor: .rect(.bounds),
                         arrowEdge: .top) {
                    dropdown
                        .frame(minWidth: 460, maxWidth: 520)
                }
            if let diag = loadDiagnostic {
                Text(diag)
                    .font(MissionFont.mono(10))
                    .foregroundStyle(t.amber)
                    .lineLimit(2)
                    .help("The picker couldn't enumerate senders from chat.db. Typing a name still works — the CLI falls back to its AddressBook substring match.")
            }
        }
        .task { await load() }
    }

    // MARK: - Field

    private var comboField: some View {
        HStack(spacing: 8) {
            avatarBubble
            TextField("Search senders or type a name…", text: $contact)
                .textFieldStyle(.plain)
                .font(MissionFont.sans(14, weight: .medium))
                .foregroundStyle(t.ink)
                .focused($fieldFocused)
                .onSubmit { isOpen = false }
                .onChange(of: contact) { _, _ in
                    // Typing anything new wipes the picked-handle latch
                    // (otherwise --handle would still go to the CLI
                    // with stale, no-longer-matching text in the field).
                    pickedHandle = nil
                    isOpen = true
                }
                .onChange(of: fieldFocused) { _, focused in
                    // Auto-open when the user clicks into the field —
                    // empty-typed shows the recents list, typed input
                    // filters live. Without this, the dropdown would
                    // only appear via the chevron, which is discoverable
                    // but not obvious.
                    if focused { isOpen = true }
                }
            if pickedHandle != nil {
                Text("via --handle")
                    .font(MissionFont.mono(9, weight: .medium))
                    .foregroundStyle(t.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(t.accentSoft)
                    )
                    .help("Exact handle selected from the dropdown. The CLI will use --handle and skip AddressBook fuzzy matching.")
            }
            Button {
                isOpen.toggle()
                if isOpen { fieldFocused = true }
            } label: {
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(MissionFont.sans(11, weight: .semibold))
                    .foregroundStyle(t.inkMute)
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Close sender list" : "Browse senders from chat.db")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(t.cardFillStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(t.rule, lineWidth: 1)
        )
    }

    private var avatarBubble: some View {
        let display = pickedHandle == nil ? contact : (contact.isEmpty ? "?" : contact)
        let initials = display
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.42, green: 0.55, blue: 0.95),
                        Color(red: 0.74, green: 0.36, blue: 0.78)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials.isEmpty ? "?" : initials)
                .font(MissionFont.sans(11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 26, height: 26)
    }

    // MARK: - Dropdown

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isLoading ? "Loading senders…" : header)
                    .font(MissionFont.kicker(9))
                    .tracking(1.0)
                    .foregroundStyle(t.inkMute)
                Spacer()
                Text("\(visibleSenders.count)")
                    .font(MissionFont.mono(10))
                    .foregroundStyle(t.inkMute)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider().opacity(0.4)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(20)
                    .frame(maxWidth: .infinity)
            } else if visibleSenders.isEmpty {
                Text("No senders match.")
                    .font(MissionFont.sans(12))
                    .foregroundStyle(t.inkMute)
                    .padding(20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleSenders.prefix(50)) { sender in
                            row(sender)
                            Divider().opacity(0.25)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        // Popover provides its own window chrome (rounded corners,
        // arrow, shadow) so we don't paint our own background here.
    }

    private var header: String {
        contact.trimmingCharacters(in: .whitespaces).isEmpty
            ? "RECENT SENDERS"
            : "MATCHES"
    }

    /// Filtered + sorted senders shown in the dropdown. Empty filter →
    /// show all (already sorted most-recent-first by SendersService).
    /// Typed input → case-insensitive substring match against the
    /// display name AND the raw handle so a user searching "+1 555" or
    /// "alice" both hit the right rows.
    private var visibleSenders: [Sender] {
        let q = contact.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allSenders }
        return allSenders.filter { s in
            (s.displayName?.lowercased().contains(q) ?? false)
                || s.handle.lowercased().contains(q)
        }
    }

    private func row(_ s: Sender) -> some View {
        Button {
            pick(s)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.displayName ?? s.handle)
                        .font(MissionFont.sans(13, weight: .medium))
                        .foregroundStyle(t.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(s.handle)
                            .font(MissionFont.mono(10))
                            .foregroundStyle(t.inkMute)
                            .lineLimit(1)
                        serviceBadge(s.service)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(s.messageCount)")
                        .font(MissionFont.mono(11, weight: .medium))
                        .foregroundStyle(t.ink)
                    Text(s.lastMessageDate.map { Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()) } ?? "—")
                        .font(MissionFont.mono(9))
                        .foregroundStyle(t.inkMute)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func serviceBadge(_ service: String) -> some View {
        let label = service.uppercased()
        let isIMessage = label.contains("IMESSAGE")
        Text(label.prefix(8))
            .font(MissionFont.mono(8, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(isIMessage ? t.accent : t.amber)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill((isIMessage ? t.accent : t.amber).opacity(0.12))
            )
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    // MARK: - Actions

    private func pick(_ s: Sender) {
        // Fill the field with whatever's most user-friendly (the display
        // name when AddressBook resolved it, otherwise the raw handle).
        // Submit to the CLI via the exact handle regardless.
        contact = s.displayName ?? s.handle
        pickedHandle = s.handle
        isOpen = false
        fieldFocused = false
    }

    private func load() async {
        let result = await Task.detached(priority: .userInitiated) {
            let ab = AddressBookLookup.buildLookup()
            let senders = SendersService.enumerate(addressBook: ab.map)
            return (senders.senders, senders.diagnostic, ab.diagnostic)
        }.value
        await MainActor.run {
            self.allSenders = result.0
            self.loadDiagnostic = result.1   // chat.db error if any
            self.isLoading = false
        }
    }
}
