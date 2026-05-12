import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Address Book

struct AddressBookSetup: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var model: ChatModel
    /// Set so the contact list supports cmd-click / shift-click multi-select.
    /// Bulk delete operates on every id in this set; the editor pane only
    /// renders when exactly one id is selected (so there's no ambiguity
    /// about which entry the form is editing).
    @State private var selection: Set<UUID> = []
    /// True while the "Manage tags" sheet is presented. Bound to the
    /// toolbar button so users can add, edit, or delete tags without
    /// leaving the Address Book tab.
    @State private var showTagManager: Bool = false
    /// IDs currently queued for the multi-delete confirmation dialog.
    /// Empty = dialog hidden. Single deletes skip the dialog (instant
    /// feedback matches the prior 1-click behaviour).
    @State private var confirmDeleteIDs: [UUID] = []

    var body: some View {
        VStack(spacing: 0) {
            alertOptionsBar
            Divider()
            contactsAndEditor
        }
        .sheet(isPresented: $showTagManager) {
            ContactTagManagerView(settings: settings)
        }
        .confirmationDialog(
            confirmDeleteIDs.count == 1
                ? "Delete this contact?"
                : "Delete \(confirmDeleteIDs.count) contacts?",
            isPresented: Binding(
                get: { !confirmDeleteIDs.isEmpty },
                set: { if !$0 { confirmDeleteIDs = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete(ids: confirmDeleteIDs)
                confirmDeleteIDs = []
            }
            Button("Cancel", role: .cancel) {
                confirmDeleteIDs = []
            }
        } message: {
            Text("Removes the selected contact\(confirmDeleteIDs.count == 1 ? "" : "s") from the address book. Their attachments and notes are also removed.")
        }
    }

    /// Bulk-remove every id in `ids`. Picks the next selection BEFORE
    /// mutating the array — same crash-class fix as 1.0.109 — and uses
    /// the surviving entries to land on a sensible neighbor.
    private func performDelete(ids: [UUID]) {
        let removeSet = Set(ids)
        let remaining = settings.settings.addressBook.filter { !removeSet.contains($0.id) }
        // Drop pending selection first so the editor pane unbinds before
        // anything mutates underneath it.
        selection = Set(remaining.first.map { [$0.id] } ?? [])
        for id in ids {
            settings.removeAddress(id: id)
        }
    }

    /// Global alert configuration that fires when a watched user comes
    /// online or our own nick is mentioned. Lives at the top of the
    /// Address Book tab so the contact list and the alerts they trigger
    /// stay in one place — used to be split between this tab and the
    /// Watchlist sheet.
    private var alertOptionsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(Color.purple)
                Text("Alerts").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showTagManager = true
                } label: {
                    Label("Manage tags\(settings.settings.contactTags.isEmpty ? "…" : " (\(settings.settings.contactTags.count))")",
                          systemImage: "tag")
                }
                .help("Define labels you can apply to any contact (deleting a tag removes it from every contact)")
                Text("Apply to every watched contact below + own-nick mentions")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 24) {
                Toggle("System notification",
                       isOn: $settings.settings.systemNotificationsOnWatchHit)
                Toggle("Play sound",
                       isOn: $settings.settings.playSoundOnWatchHit)
                Toggle("Bounce Dock",
                       isOn: $settings.settings.bounceDockOnWatchHit)
                Toggle("Alert on own nick",
                       isOn: $settings.settings.highlightOnOwnNick)
                Spacer()
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The original master/detail body, lifted out so the new alerts bar
    /// can sit above it without ballooning indentation.
    @ViewBuilder
    private var contactsAndEditor: some View {
        HStack(spacing: 0) {
            // Master pane — list of contacts. Watch toggle stays inline so
            // the user can flip alerts without opening the editor.
            VStack(spacing: 0) {
                if settings.settings.addressBook.isEmpty {
                    ContentUnavailableView(
                        "No contacts yet",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add nicknames to track. Toggle “Watch” to get alerts when they come online.")
                    )
                    .padding(20)
                } else {
                    List(selection: $selection) {
                        ForEach(settings.settings.addressBook) { entry in
                            HStack {
                                Image(systemName: entry.watch ? "bell.fill" : "bell.slash")
                                    .foregroundStyle(entry.watch ? Color.purple : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.nick.isEmpty ? "(unnamed)" : entry.nick)
                                        .font(.body)
                                    if !entry.note.isEmpty {
                                        Text(entry.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    if !entry.tagIDs.isEmpty {
                                        // Inline tag chips so users can spot
                                        // tagged contacts without opening
                                        // the editor. Resolved against the
                                        // global tag list each render so a
                                        // rename or delete propagates live.
                                        ContactTagChipRow(
                                            tagIDs: entry.tagIDs,
                                            allTags: settings.settings.contactTags,
                                            compact: true
                                        )
                                    }
                                }
                                Spacer()
                                if !entry.richNotes.isEmpty {
                                    // Quick visual cue that the contact has
                                    // longer notes attached.
                                    Image(systemName: "doc.text")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            // Whole-row hit area so a click between the
                            // bell icon and the nick still counts as a tap.
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                openQuery(for: entry)
                            }
                            .tag(entry.id)
                        }
                    }
                }
                Divider()
                HStack {
                    Button {
                        let nick = AddressEntry.nextDefaultNick(
                            existing: settings.settings.addressBook)
                        let new = AddressEntry(nick: nick, watch: true)
                        settings.settings.addressBook.append(new)
                        selection = [new.id]
                    } label: { Image(systemName: "plus") }
                    Button {
                        let ids = Array(selection)
                        guard !ids.isEmpty else { return }
                        if ids.count == 1 {
                            // Single-contact delete keeps the prior
                            // one-click behaviour — no confirmation,
                            // matches what users expect from the +/−
                            // bottom bar idiom.
                            performDelete(ids: ids)
                        } else {
                            confirmDeleteIDs = ids
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection.isEmpty)
                        .help(selection.count > 1
                              ? "Delete the \(selection.count) selected contacts"
                              : "Delete the selected contact")
                    Spacer()
                    if selection.count > 1 {
                        Text("\(selection.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Detail pane — full editor for the selected contact. The
            // binding looks up the row by id every time (rather than
            // capturing an index once) so deleting the row underneath
            // an active TextField is a safe no-op instead of an
            // out-of-range crash. Only renders for single-selection so
            // the form is never ambiguous about which row it's editing.
            if selection.count == 1,
               let id = selection.first,
               settings.settings.addressBook.contains(where: { $0.id == id }) {
                AddressEntryEditor(entry: Binding(
                    get: {
                        settings.settings.addressBook
                            .first(where: { $0.id == id }) ?? AddressEntry()
                    },
                    set: { newValue in
                        if let i = settings.settings.addressBook.firstIndex(where: { $0.id == id }) {
                            settings.settings.addressBook[i] = newValue
                        }
                    }
                ))
            } else if selection.count > 1 {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "person.2.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("\(selection.count) contacts selected")
                        .font(.headline)
                    Text("Click − to delete them all, or pick a single contact to edit.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("Select a contact, or click + to add one.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            // The sidebar's "Edit address book entry…" passes the entry's
            // UUID via `pendingAddressBookSelection`. When set, jump to it
            // directly instead of the default first-row landing. Cleared
            // after consume so re-opening the tab doesn't re-fire.
            if let target = model.pendingAddressBookSelection,
               settings.settings.addressBook.contains(where: { $0.id == target }) {
                selection = [target]
                model.pendingAddressBookSelection = nil
            } else if selection.isEmpty,
                      let first = settings.settings.addressBook.first?.id {
                selection = [first]
            }
        }
        .onChange(of: model.pendingAddressBookSelection) { _, newValue in
            // Handles the case where Setup is already open and the
            // directive arrives mid-flight.
            guard let target = newValue,
                  settings.settings.addressBook.contains(where: { $0.id == target })
            else { return }
            selection = [target]
            model.pendingAddressBookSelection = nil
        }
    }

    /// Open a /query buffer for the contact's nick and dismiss the Setup
    /// sheet so the user lands directly in the conversation. Falls back
    /// silently if the entry has no nick yet.
    private func openQuery(for entry: AddressEntry) {
        let nick = entry.nick.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else { return }
        // Dismiss Setup first so the new buffer is what's on screen
        // when the /query routes through ChatModel — handing off the
        // input is what makes the buffer "open" if it didn't exist.
        model.showSetup = false
        DispatchQueue.main.async {
            model.sendInput("/query \(nick)")
        }
    }
}

/// Editor for a single AddressEntry. Short fields up top, Markdown editor
/// + live preview at the bottom. Splits into two panes when there's
/// vertical room so you can write and see the rendered version side-by-side.
struct AddressEntryEditor: View {
    @Binding var entry: AddressEntry
    @EnvironmentObject var model: ChatModel

    /// Cross-network seen + log matches for `entry.nick`. Recomputed
    /// whenever the nick changes — see `loadMatches()`.
    @State private var matches: ContactMatchResult = ContactMatchResult()
    /// True while a popover for adding tags is open. Backed by @State so
    /// the popover anchors next to the "Add tag" button.
    @State private var showAddTagPopover: Bool = false

    /// True when the current nickname collides (case-insensitive) with
    /// some other contact in the address book. Surfaces a non-blocking
    /// warning under the field — the user is free to keep typing, but
    /// the visual cue catches accidental duplicates the moment they
    /// happen.
    private var hasDuplicateNick: Bool {
        AddressEntry.nickClashes(
            entry.nick,
            in: model.settings.settings.addressBook,
            excluding: entry.id
        )
    }

    var body: some View {
        Form {
            Section("Photo") {
                HStack(spacing: 16) {
                    ContactAvatar(entry: entry, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                pickPhoto()
                            } label: {
                                Label("Choose photo…", systemImage: "photo.on.rectangle")
                            }
                            if entry.photoData != nil {
                                Button(role: .destructive) {
                                    entry.photoData = nil
                                } label: {
                                    Label("Remove", systemImage: "xmark.circle")
                                }
                            }
                        }
                        Text(entry.photoData != nil
                             ? "Photo embedded in settings.json (downscaled to ≤256 px, JPEG)."
                             : "No photo. Falls back to the auto-tinted initial avatar.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                    return true
                }
            }
            Section("Contact") {
                TextField("Nickname", text: $entry.nick)
                    .textFieldStyle(.roundedBorder)
                if hasDuplicateNick {
                    Label("Another contact already uses this nickname.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Alert when this nick comes online", isOn: $entry.watch)
                TextField("Short note (shown next to the nick)", text: $entry.note)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Tags") {
                if entry.tagIDs.isEmpty {
                    Text("No tags. Use the picker below to label this contact (e.g. *Friend*, *Work*, *Channel-op*).")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ContactTagChipRow(
                        tagIDs: entry.tagIDs,
                        allTags: model.settings.settings.contactTags,
                        compact: false,
                        onRemove: { id in
                            entry.tagIDs.removeAll { $0 == id }
                        }
                    )
                }
                HStack {
                    Button {
                        showAddTagPopover = true
                    } label: {
                        Label("Add tag…", systemImage: "tag")
                    }
                    .popover(isPresented: $showAddTagPopover, arrowEdge: .bottom) {
                        ContactTagAddPopover(
                            assigned: entry.tagIDs,
                            settings: model.settings,
                            onPick: { id in
                                if !entry.tagIDs.contains(id) {
                                    entry.tagIDs.append(id)
                                }
                            }
                        )
                    }
                    Text("Defined in **Manage tags…** at the top of the Address Book tab. Deleting a tag removes it from every contact.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !entry.nick.isEmpty {
                Section {
                    ContactActivitySparkline(
                        bins: model.recentMessageDayBins(nick: entry.nick, days: 14)
                    )
                } header: {
                    Text("Activity")
                } footer: {
                    Text("Messages from \(entry.nick) on every connected network, binned by day. Drawn from the seen tracker — turn it on in Setup → Bot if these bars are flat.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section {
                ContactMatchesSection(
                    nick: entry.nick,
                    matches: matches,
                    onOpenSeenList: { conn in
                        model.activeConnectionID = conn.id
                        model.showSeenList = true
                    },
                    onOpenChatLogs: {
                        model.showChatLogs = true
                    },
                    onOpenQuery: { nick in
                        model.showSetup = false
                        DispatchQueue.main.async {
                            model.sendInput("/query \(nick)")
                        }
                    }
                )
            } header: {
                Text("Matches in seen log + chat logs")
            }

            Section("Attachments") {
                if entry.attachments.isEmpty {
                    Text("No attachments. Click **Attach file…** or drop any file into this section. Bytes live in the encrypted blob store; this list shows lightweight references.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(entry.attachments) { ref in
                        AttachmentRow(ref: ref) {
                            openAttachment(ref)
                        } onReveal: {
                            revealAttachment(ref)
                        } onRemove: {
                            removeAttachment(ref)
                        }
                    }
                }
                Button {
                    pickAttachment()
                } label: {
                    Label("Attach file…", systemImage: "paperclip")
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleAttachmentDrop(providers)
                return true
            }

            Section("Notes") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Markdown source")
                        .font(.caption).foregroundStyle(.secondary)
                    SpellCheckedTextEditor(text: $entry.richNotes)
                        .frame(minHeight: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                }
                if !entry.richNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview")
                            .font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            Text(Self.markdown(entry.richNotes))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(minHeight: 100, maxHeight: 200)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                    }
                }
                Text("Supports **bold**, *italic*, `code`, [links](https://example.com), and bullet lists with `-`. Notes are stored in settings.json so they're encrypted along with the rest of your config.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadMatches() }
        .onChange(of: entry.id) { _, _ in loadMatches() }
        .onChange(of: entry.nick) { _, _ in loadMatches() }
    }

    /// Recompute exact + fuzzy matches against every connected network's
    /// SeenStore and the LogStore index. Cheap enough to run on each
    /// nick edit — both stores keep their data in memory once warm.
    /// LogStore is an actor, so the read happens off the main actor in a
    /// detached Task.
    private func loadMatches() {
        let nick = entry.nick.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else {
            matches = ContactMatchResult()
            return
        }
        // Seen-store work is synchronous on the main actor.
        var seenHits: [ContactMatchResult.SeenHit] = []
        for conn in model.connections {
            let entries = model.botEngine.seenStore.entries(
                networkID: conn.id,
                networkSlug: SeenStore.slug(for: conn.displayName))
            for e in entries where ContactMatchResult.matches(needle: nick, candidate: e.nick) {
                seenHits.append(.init(
                    connection: conn,
                    networkName: conn.displayName,
                    seen: e,
                    isExact: e.nick.caseInsensitiveCompare(nick) == .orderedSame
                ))
            }
        }
        // Sort: exact matches first, then by recency.
        seenHits.sort {
            if $0.isExact != $1.isExact { return $0.isExact && !$1.isExact }
            return $0.seen.timestamp > $1.seen.timestamp
        }
        // Log lookup is async — kick off a Task and merge results back on
        // the main actor when ready. The view re-renders on `matches` set.
        let needle = nick
        let store = model.logStore
        Task {
            let result = await store.enumerateAllLogs()
            var logHits: [ContactMatchResult.LogHit] = []
            for entry in result.named where ContactMatchResult.matches(needle: needle, candidate: entry.buffer) {
                logHits.append(.init(
                    network: entry.network,
                    buffer: entry.buffer,
                    isExact: entry.buffer.caseInsensitiveCompare(needle) == .orderedSame
                ))
            }
            logHits.sort {
                if $0.isExact != $1.isExact { return $0.isExact && !$1.isExact }
                if $0.network != $1.network {
                    return $0.network.localizedCaseInsensitiveCompare($1.network) == .orderedAscending
                }
                return $0.buffer.localizedCaseInsensitiveCompare($1.buffer) == .orderedAscending
            }
            await MainActor.run {
                // Only commit if the editor is still on the same nick — a
                // fast typist could have moved on while the actor was busy.
                if entry.nick.trimmingCharacters(in: .whitespaces) == needle {
                    self.matches = ContactMatchResult(seen: seenHits, logs: logHits)
                }
            }
        }
        // Show the seen results immediately while the log results land.
        matches = ContactMatchResult(seen: seenHits, logs: matches.logs)
    }

    /// Parse the Markdown source into an `AttributedString` for preview.
    /// Falls back to plain text on parse failure so a stray `]` doesn't
    /// blank the entire preview.
    private static func markdown(_ src: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: src, options: opts) {
            return parsed
        }
        return AttributedString(src)
    }

    /// NSOpenPanel-driven photo picker. Filters to common image types,
    /// passes the chosen file through PhotoUtilities for downscale +
    /// JPEG re-encode so the inline storage stays small even when the
    /// user picks a 4K wallpaper.
    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose profile photo"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let data = PhotoUtilities.loadDownscaled(from: url) {
                Task { @MainActor in
                    entry.photoData = data
                }
            }
        }
    }

    /// NSOpenPanel-driven attachment picker. No type filter — any file
    /// is fair game. Routed through the BlobStore so the bytes are
    /// encrypted at rest the same way every other persistence path is.
    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Attach files to \(entry.nick.isEmpty ? "this contact" : entry.nick)"
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            let entryID = entry.id
            Task {
                for url in urls {
                    if let rec = await model.blobStore.store(fileURL: url, attachedTo: entryID) {
                        await MainActor.run {
                            entry.attachments.append(BlobStore.AttachmentRef(
                                id: rec.id,
                                filename: rec.filename,
                                contentType: rec.contentType,
                                sizeBytes: rec.sizeBytes
                            ))
                        }
                    }
                }
            }
        }
    }

    /// Drag-and-drop entry point for attachments. Accepts file URLs
    /// dragged from Finder, routes them through the BlobStore the
    /// same way the picker does.
    private func handleAttachmentDrop(_ providers: [NSItemProvider]) {
        let entryID = entry.id
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let urlData = item as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                Task {
                    if let rec = await model.blobStore.store(fileURL: url, attachedTo: entryID) {
                        await MainActor.run {
                            entry.attachments.append(BlobStore.AttachmentRef(
                                id: rec.id,
                                filename: rec.filename,
                                contentType: rec.contentType,
                                sizeBytes: rec.sizeBytes
                            ))
                        }
                    }
                }
            }
        }
    }

    /// "Open" — materialise the blob to a temp file and hand off to
    /// the OS via NSWorkspace. The OS picks the right handler based
    /// on file extension / UTType.
    private func openAttachment(_ ref: BlobStore.AttachmentRef) {
        let id = ref.id
        Task {
            guard let url = await model.blobStore.writeToTempFile(id) else { return }
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// "Reveal in Finder" — same temp-file materialisation as Open,
    /// then `activateFileViewerSelecting` so the user gets a Finder
    /// window with the file selected.
    private func revealAttachment(_ ref: BlobStore.AttachmentRef) {
        let id = ref.id
        Task {
            guard let url = await model.blobStore.writeToTempFile(id) else { return }
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    /// Remove the attachment from BOTH the inline ref list and the
    /// blob store. Keeping them in sync is the editor's job — the
    /// store doesn't reach back into AddressEntry.
    private func removeAttachment(_ ref: BlobStore.AttachmentRef) {
        entry.attachments.removeAll { $0.id == ref.id }
        let id = ref.id
        Task {
            await model.blobStore.delete(id)
        }
    }

    /// Drag-and-drop entry point. Accepts both `.image` (raw bitmap
    /// dragged from another app) and `.fileURL` (e.g. dragged from
    /// Finder). Resolves to a Data and routes through the same
    /// PhotoUtilities pipeline as the picker.
    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage,
                          let data = PhotoUtilities.downscaleAndEncode(img) else { return }
                    Task { @MainActor in
                        entry.photoData = data
                    }
                }
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let urlData = item as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil),
                          let data = PhotoUtilities.loadDownscaled(from: url) else { return }
                    Task { @MainActor in
                        entry.photoData = data
                    }
                }
                return
            }
        }
    }
}

