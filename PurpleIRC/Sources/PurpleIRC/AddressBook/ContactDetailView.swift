import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Right pane of the Address Book workspace: the detailed editor for
/// the currently-selected contact. Sectioned scroll view stitched
/// together from the smaller per-section views in this directory.
///
/// Roughly mirrors the layout of the now-deleted
/// `Setup/AddressBookSetup.swift::AddressEntryEditor`, plus the
/// Person-model additions (linked nicks, per-contact alerts, the
/// merged activity timeline + hostmask history), so users who knew
/// the old editor will find every section they expect plus a few
/// new ones.
struct ContactDetailView: View {
    @Binding var entry: AddressEntry
    @EnvironmentObject var model: ChatModel

    @State private var matches: ContactMatchResult = ContactMatchResult()
    @State private var showAddTagPopover: Bool = false

    var body: some View {
        Form {
            // MARK: Identity
            Section("Identity") {
                HStack(spacing: 16) {
                    ContactAvatar(entry: entry, size: 80)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Display nickname", text: $entry.nick)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                        if hasDuplicateNick {
                            Label("Another contact already uses this nickname.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        TextField("Short note (one line)", text: $entry.note)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 12) {
                            Button {
                                pickPhoto()
                            } label: {
                                Label("Choose photo…", systemImage: "photo")
                            }
                            if entry.photoData != nil {
                                Button(role: .destructive) {
                                    entry.photoData = nil
                                } label: {
                                    Label("Remove photo", systemImage: "xmark.circle")
                                }
                            }
                            Toggle("Notify when online", isOn: $entry.watch)
                                .toggleStyle(.switch)
                        }
                    }
                    Spacer()
                }
                .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                    handlePhotoDrop(providers)
                    return true
                }
            }

            // MARK: Linked nicks (Person model)
            Section {
                ContactLinkedNicksSection(entry: $entry)
            } header: {
                Text("Linked nicks across networks")
            } footer: {
                Text("Each binding is one (network, nick) pair this contact answers to. Use \"All networks\" for the legacy any-network sentinel — it preserves the pre-1.0.242 \"watch this nick everywhere\" behaviour.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Per-contact alert overrides
            Section {
                ContactAlertOverridesSection(entry: $entry)
            } header: {
                Text("Alert overrides")
            }

            // MARK: Tags
            Section {
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
                }
            } header: { Text("Tags") }

            // MARK: Activity sparkline
            if !entry.nick.isEmpty {
                Section {
                    ContactActivitySparkline(
                        bins: model.recentMessageDayBins(nick: entry.nick, days: 14)
                    )
                } header: { Text("Recent activity (14-day sparkline)") }
            }

            // MARK: Activity timeline
            Section {
                ContactActivityTimelineSection(entry: entry)
            } header: { Text("Activity timeline (merged across networks)") }

            // MARK: Shared channels
            Section {
                ContactSharedChannelsSection(entry: entry)
            } header: { Text("Channels in common") }

            // MARK: Hostmask history
            Section {
                ContactHostmaskHistorySection(entry: entry)
            } header: { Text("Hostmask history") }

            // MARK: Cross-store matches
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
                        model.sendInput("/query \(nick)")
                    }
                )
            } header: {
                Text("Matches in seen log + chat logs")
            }

            // MARK: Attachments
            Section("Attachments") {
                if entry.attachments.isEmpty {
                    Text("No attachments. Drop any file here or click **Attach file…**.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(entry.attachments) { ref in
                        AttachmentRow(
                            ref: ref,
                            onOpen: { openAttachment(ref) },
                            onReveal: { revealAttachment(ref) },
                            onRemove: { removeAttachment(ref) }
                        )
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

            // MARK: Notes (Markdown)
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

    // MARK: - Duplicate guard

    private var hasDuplicateNick: Bool {
        AddressEntry.nickClashes(
            entry.nick,
            in: model.settings.settings.addressBook,
            excluding: entry.id
        )
    }

    // MARK: - Markdown

    private static func markdown(_ src: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: src, options: opts) {
            return parsed
        }
        return AttributedString(src)
    }

    // MARK: - Cross-store matches

    private func loadMatches() {
        let nick = entry.nick.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else {
            matches = ContactMatchResult()
            return
        }
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
        seenHits.sort {
            if $0.isExact != $1.isExact { return $0.isExact && !$1.isExact }
            return $0.seen.timestamp > $1.seen.timestamp
        }
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
                if entry.nick.trimmingCharacters(in: .whitespaces) == needle {
                    self.matches = ContactMatchResult(seen: seenHits, logs: logHits)
                }
            }
        }
        matches = ContactMatchResult(seen: seenHits, logs: matches.logs)
    }

    // MARK: - Photo + attachment helpers (lifted from old editor)

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

    private func handlePhotoDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage else { return }
                    // Downscale on the main actor: it uses NSImage.lockFocus,
                    // which is AppKit drawing and unsafe on the arbitrary
                    // background queue this completion fires on.
                    Task { @MainActor in
                        guard let data = PhotoUtilities.downscaleAndEncode(img) else { return }
                        entry.photoData = data
                    }
                }
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let urlData = item as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    // loadDownscaled also lockFocus-draws, so run it on main.
                    Task { @MainActor in
                        guard let data = PhotoUtilities.loadDownscaled(from: url) else { return }
                        entry.photoData = data
                    }
                }
                return
            }
        }
    }

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

    private func openAttachment(_ ref: BlobStore.AttachmentRef) {
        let id = ref.id
        Task {
            guard let url = await model.blobStore.writeToTempFile(id) else { return }
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func revealAttachment(_ ref: BlobStore.AttachmentRef) {
        let id = ref.id
        Task {
            guard let url = await model.blobStore.writeToTempFile(id) else { return }
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func removeAttachment(_ ref: BlobStore.AttachmentRef) {
        entry.attachments.removeAll { $0.id == ref.id }
        let id = ref.id
        Task {
            await model.blobStore.delete(id)
        }
    }
}
