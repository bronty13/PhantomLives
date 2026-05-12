import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Contact tags

/// Inline chip row used in two places: read-only mini chips on the
/// address-book sidebar rows, and removable chips inside the editor.
/// Resolved against the live `allTags` array each render so renames /
/// deletions propagate without any cache.
struct ContactTagChipRow: View {
    let tagIDs: [UUID]
    let allTags: [ContactTag]
    /// True for the sidebar mini-chip mode — small, no remove button.
    var compact: Bool = false
    var onRemove: ((UUID) -> Void)? = nil

    var body: some View {
        let resolved = tagIDs.compactMap { id in allTags.first(where: { $0.id == id }) }
        // Wrapping flow layout via VStack-of-HStacks so chips wrap to a
        // second line when the editor is narrow. SwiftUI gained a real
        // FlowLayout in macOS 14, but this stays widely compatible.
        FlowChips(items: resolved, compact: compact, onRemove: onRemove)
    }
}

/// Tiny flow-layout for chip rows. macOS 13's `Layout` would be cleaner,
/// but a hand-rolled version keeps the deployment target flexible and
/// is small enough to justify the duplication.
private struct FlowChips: View {
    let items: [ContactTag]
    let compact: Bool
    let onRemove: ((UUID) -> Void)?

    var body: some View {
        // Use ViewThatFits/HStack? Falling back to a simple HStack with
        // wrapping via the iOS-style "tags" pattern: layout via
        // GeometryReader + offsets. For our small counts (typically <10)
        // a single horizontal scroll is fine and avoids layout math.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items) { tag in
                    ContactTagChip(tag: tag, compact: compact, onRemove: onRemove)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

struct ContactTagChip: View {
    let tag: ContactTag
    var compact: Bool = false
    var onRemove: ((UUID) -> Void)? = nil

    /// Resolved chip color — the user's custom hex when set, otherwise
    /// the default purple. Falls back to purple if the hex is unparseable
    /// so a corrupt settings.json field never blanks the chip out.
    private var color: Color {
        guard let hex = tag.colorHex, let c = Color(hex: hex) else { return .purple }
        return c
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(compact ? .system(size: 8) : .caption2)
            Text(tag.name.isEmpty ? "(unnamed)" : tag.name)
                .font(compact ? .system(size: 10) : .caption)
                .lineLimit(1)
            if let onRemove {
                Button {
                    onRemove(tag.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove tag from this contact (tag itself stays defined)")
            }
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(color.opacity(compact ? 0.12 : 0.18))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .help(tag.detail.isEmpty ? tag.name : "\(tag.name) — \(tag.detail)")
    }
}

/// Popover used by the "Add tag…" button on AddressEntryEditor. Lists
/// every defined tag with a checkmark for ones already on this contact;
/// also lets the user mint a brand-new tag inline so they don't have
/// to context-switch to the manager sheet for one-off labels.
struct ContactTagAddPopover: View {
    let assigned: [UUID]
    @ObservedObject var settings: SettingsStore
    let onPick: (UUID) -> Void

    @State private var newName: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick a tag").font(.headline)
            if settings.settings.contactTags.isEmpty {
                Text("No tags defined yet. Create one below or use **Manage tags…** at the top of the Address Book tab.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedTags) { tag in
                            Button {
                                onPick(tag.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: assigned.contains(tag.id)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(assigned.contains(tag.id)
                                                         ? Color.purple
                                                         : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tag.name.isEmpty ? "(unnamed)" : tag.name)
                                        if !tag.detail.isEmpty {
                                            Text(tag.detail)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 3)
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            .disabled(assigned.contains(tag.id))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            Divider()
            HStack {
                TextField("New tag name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createAndPick() }
                Button("Create") { createAndPick() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var sortedTags: [ContactTag] {
        settings.settings.contactTags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func createAndPick() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // If a tag with this name already exists (case-insensitive),
        // pick that one rather than minting a duplicate. Matches the
        // "no duplicates" rule enforced elsewhere and avoids the
        // accidental "I typed Friend twice" footgun.
        if let existing = settings.settings.contactTags.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == trimmed.lowercased()
        }) {
            onPick(existing.id)
            newName = ""
            dismiss()
            return
        }
        let hex = ContactTag.nextDefaultColorHex(
            existing: settings.settings.contactTags)
        let tag = ContactTag(name: trimmed, colorHex: hex)
        settings.upsertTag(tag)
        onPick(tag.id)
        newName = ""
        dismiss()
    }
}

/// Manage-tags sheet. Master/detail layout: list of tags on the left,
/// edit pane on the right. Delete cascades through `SettingsStore.deleteTag`
/// (strips the id from every contact's `tagIDs`).
struct ContactTagManagerView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    /// Set so cmd-click / shift-click can multi-select. Editor only
    /// renders when exactly one tag is selected.
    @State private var selection: Set<UUID> = []
    /// IDs queued for the multi-delete confirmation. Tag deletes always
    /// confirm (they cascade across every contact, so a misclick is
    /// expensive), regardless of whether one or many are selected.
    @State private var confirmDeleteIDs: [UUID] = []
    /// Live ColorPicker state for the selected tag. Held separately
    /// from `tag.colorHex` because Color↔hex round-trips through a
    /// Binding(get:set:) drift and lose user picks (same lesson as
    /// HighlightRuleEditor).
    @State private var pickerColor: Color = .purple

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tag")
                    .foregroundStyle(Color.purple)
                Text("Manage contact tags").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                listPane
                Divider()
                editorPane
            }
        }
        .frame(minWidth: 620, minHeight: 380)
        .confirmationDialog(
            confirmDeleteIDs.count == 1
                ? "Delete \"\(confirmDeleteTags.first?.name ?? "")\"?"
                : "Delete \(confirmDeleteIDs.count) tags?",
            isPresented: Binding(
                get: { !confirmDeleteIDs.isEmpty },
                set: { if !$0 { confirmDeleteIDs = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete from every contact", role: .destructive) {
                performDelete(ids: confirmDeleteIDs)
                confirmDeleteIDs = []
            }
            Button("Cancel", role: .cancel) {
                confirmDeleteIDs = []
            }
        } message: {
            Text(confirmDeleteIDs.count == 1
                 ? "Removes the tag definition and strips it from every contact that currently has it. The contacts themselves stay; only the tag goes away."
                 : "Removes \(confirmDeleteIDs.count) tag definitions and strips each from every contact that currently has them. The contacts themselves stay; only the tags go away.")
        }
    }

    private var confirmDeleteTags: [ContactTag] {
        confirmDeleteIDs.compactMap { id in
            settings.settings.contactTags.first(where: { $0.id == id })
        }
    }

    /// Bulk delete with the same selection-before-mutation discipline
    /// the address-book pane uses. Picks a surviving neighbour for the
    /// new selection so the editor pane lands somewhere useful instead
    /// of dropping back to the empty placeholder.
    private func performDelete(ids: [UUID]) {
        let removeSet = Set(ids)
        let remaining = settings.settings.contactTags.filter { !removeSet.contains($0.id) }
        selection = Set(remaining.first.map { [$0.id] } ?? [])
        for id in ids {
            settings.deleteTag(id: id)
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            if settings.settings.contactTags.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Click + to add your first tag, then assign it to contacts from the Address Book editor.")
                )
                .padding(20)
            } else {
                List(selection: $selection) {
                    ForEach(sortedTags) { tag in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.name.isEmpty ? "(unnamed)" : tag.name)
                                .font(.body)
                            HStack(spacing: 6) {
                                Text("\(usageCount(of: tag.id)) contact\(usageCount(of: tag.id) == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if !tag.detail.isEmpty {
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(tag.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .tag(tag.id)
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    let hex = ContactTag.nextDefaultColorHex(
                        existing: settings.settings.contactTags)
                    let name = ContactTag.nextDefaultName(
                        existing: settings.settings.contactTags)
                    let tag = ContactTag(name: name, colorHex: hex)
                    settings.upsertTag(tag)
                    selection = [tag.id]
                } label: { Image(systemName: "plus") }
                Button {
                    let ids = Array(selection)
                    guard !ids.isEmpty else { return }
                    confirmDeleteIDs = ids
                } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                    .help(selection.count > 1
                          ? "Delete the \(selection.count) selected tags from every contact"
                          : "Delete the selected tag from every contact")
                Spacer()
                if selection.count > 1 {
                    Text("\(selection.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var editorPane: some View {
        // Look up by id every time. Captured indices crash when the
        // array shrinks underneath a pending TextField binding (which
        // is what we hit in 1.0.108's first cut on delete). Only
        // renders for single-selection — multi-selection is a delete
        // staging area, not an editing context.
        if selection.count == 1,
           let id = selection.first,
           settings.settings.contactTags.contains(where: { $0.id == id }) {
            Form {
                Section("Tag") {
                    TextField("Name", text: nameBinding(for: id))
                        .textFieldStyle(.roundedBorder)
                    if ContactTag.nameClashes(
                        currentTag(for: id)?.name ?? "",
                        in: settings.settings.contactTags,
                        excluding: id
                    ) {
                        Label("Another tag already uses this name.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Color") {
                    Toggle("Custom color", isOn: customColorBinding(for: id))
                    if currentTag(for: id)?.colorHex != nil {
                        HStack {
                            ColorPicker("Chip color", selection: $pickerColor, supportsOpacity: false)
                                .onChange(of: pickerColor) { _, new in
                                    // Only persist while the toggle is
                                    // on. Without the guard, toggling off
                                    // and back on would overwrite the
                                    // saved color with the picker default.
                                    if let i = indexFor(id),
                                       settings.settings.contactTags[i].colorHex != nil {
                                        settings.settings.contactTags[i].colorHex = new.hexRGB
                                    }
                                }
                            ContactTagChip(tag: currentTag(for: id) ?? .init(name: "preview"))
                        }
                    } else {
                        Text("Default purple. Toggle **Custom color** above to pick your own.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Section("Description (optional)") {
                    TextEditor(text: detailBinding(for: id))
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                    Text("Shown as a tooltip on the chip and next to the name in this manager. Plain text only.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Section("Usage") {
                    let users = contactsUsingTag(id: id)
                    if users.isEmpty {
                        Text("No contacts have this tag yet.")
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(users) { c in
                            Text(c.nick.isEmpty ? "(unnamed)" : c.nick)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { syncPickerColor(id: id) }
            .onChange(of: selection) { _, new in
                if new.count == 1, let only = new.first {
                    syncPickerColor(id: only)
                }
            }
        } else if selection.count > 1 {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tag.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("\(selection.count) tags selected")
                    .font(.headline)
                Text("Click − to delete them all from every contact, or pick a single tag to edit.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack {
                Spacer()
                Text("Select a tag, or click + to add one.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Safe id-based binding helpers
    //
    // Looking the index up inside the binding's get/set closures (rather
    // than capturing it once) means deleting a tag underneath an active
    // TextField is safe — the closures simply find no row and become
    // no-ops instead of indexing an array out of bounds.

    private func indexFor(_ id: UUID) -> Int? {
        settings.settings.contactTags.firstIndex(where: { $0.id == id })
    }

    private func currentTag(for id: UUID) -> ContactTag? {
        settings.settings.contactTags.first(where: { $0.id == id })
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { currentTag(for: id)?.name ?? "" },
            set: { newValue in
                if let i = indexFor(id) {
                    settings.settings.contactTags[i].name = newValue
                }
            }
        )
    }

    private func detailBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { currentTag(for: id)?.detail ?? "" },
            set: { newValue in
                if let i = indexFor(id) {
                    settings.settings.contactTags[i].detail = newValue
                }
            }
        )
    }

    private func customColorBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { currentTag(for: id)?.colorHex != nil },
            set: { enabled in
                guard let i = indexFor(id) else { return }
                if enabled {
                    let hex = settings.settings.contactTags[i].colorHex ?? "#7E57C2"
                    settings.settings.contactTags[i].colorHex = hex
                    pickerColor = Color(hex: hex) ?? .purple
                } else {
                    settings.settings.contactTags[i].colorHex = nil
                }
            }
        )
    }

    private func syncPickerColor(id: UUID) {
        let hex = currentTag(for: id)?.colorHex
        pickerColor = (hex.flatMap { Color(hex: $0) }) ?? .purple
    }

    private var sortedTags: [ContactTag] {
        settings.settings.contactTags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func usageCount(of id: UUID) -> Int {
        settings.settings.addressBook.reduce(0) { $0 + ($1.tagIDs.contains(id) ? 1 : 0) }
    }

    private func contactsUsingTag(id: UUID) -> [AddressEntry] {
        settings.settings.addressBook.filter { $0.tagIDs.contains(id) }
    }
}

