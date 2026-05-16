import SwiftUI
import GRDB

/// Manage Tags sheet — reached from Schema Editor → More menu. Owns
/// the full cross-cutting vocabulary: rename, recolor, merge, delete.
/// All mutations go through `TagService`; per-record fan-out (merge /
/// delete) routes through `ObjectEngine.update` so undo, FTS, sync,
/// and the `record_tags` index all keep up.
struct TagManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var tags: [TagDef] = []
    @State private var usage: [String: Int] = [:]
    @State private var renamingId: String? = nil
    @State private var renamingDraft: String = ""
    @State private var renameError: String? = nil
    @State private var mergingTag: TagDef? = nil
    @State private var deletingTag: TagDef? = nil
    @State private var newTagDraft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if tags.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear(perform: reload)
        .alert("Delete tag?", isPresented: deleteAlertBinding, presenting: deletingTag) { tag in
            Button("Delete", role: .destructive) {
                TagService.delete(id: tag.id)
                deletingTag = nil
                reload()
            }
            Button("Cancel", role: .cancel) { deletingTag = nil }
        } message: { tag in
            let count = usage[tag.id] ?? 0
            Text(count == 0
                 ? "\u{201C}\(tag.name)\u{201D} isn't used by any records. Delete it from the vocabulary?"
                 : "\u{201C}\(tag.name)\u{201D} is on \(count) record\(count == 1 ? "" : "s"). Deleting it removes the tag from each.")
        }
        .sheet(item: $mergingTag) { source in
            MergeIntoSheet(source: source, others: tags.filter { $0.id != source.id }) { destinationId in
                TagService.merge(sourceId: source.id, into: destinationId)
                mergingTag = nil
                reload()
            } onCancel: {
                mergingTag = nil
            }
        }
    }

    // MARK: - Header / footer / empty

    private var header: some View {
        HStack {
            Text("Manage Tags").font(.title2).bold()
            Spacer()
            Text("\(tags.count) tag\(tags.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TextField("Add a new tag…", text: $newTagDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addNewTag)
            Button("Add", action: addNewTag)
                .disabled(newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tag")
                .font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("No tags yet.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Add a tag below, or open any record and use the tag pill row.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(tags) { tag in
                    row(for: tag)
                    Divider()
                }
            }
        }
    }

    // MARK: - Row

    private func row(for tag: TagDef) -> some View {
        let count = usage[tag.id] ?? 0
        return HStack(spacing: 12) {
            ColorPicker("", selection: colorBinding(for: tag))
                .labelsHidden()
                .frame(width: 28)
                .help("Tap to change the tag's color")

            if renamingId == tag.id {
                renameField(for: tag)
            } else {
                Text(tag.name)
                    .font(.body)
                    .onTapGesture(count: 2) { beginRename(tag) }
            }

            Spacer()

            Text("\(count) record\(count == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            Menu {
                Button("Rename")  { beginRename(tag) }
                Button("Merge into other tag…") { mergingTag = tag }
                Divider()
                Button("Delete", role: .destructive) { deletingTag = tag }
                    .disabled(false)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder
    private func renameField(for tag: TagDef) -> some View {
        HStack(spacing: 6) {
            TextField(tag.name, text: $renamingDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitRename(tag) }
            Button("Save") { commitRename(tag) }
            Button("Cancel") { cancelRename() }
            if let err = renameError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        tags = TagService.allTags
        usage = (try? loadUsage()) ?? [:]
    }

    private func addNewTag() {
        let trimmed = newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = TagService.add(name: trimmed)
        newTagDraft = ""
        reload()
    }

    private func beginRename(_ tag: TagDef) {
        renamingId = tag.id
        renamingDraft = tag.name
        renameError = nil
    }

    private func commitRename(_ tag: TagDef) {
        let trimmed = renamingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { renameError = "Name can't be empty"; return }
        if let collide = TagService.tag(name: trimmed), collide.id != tag.id {
            renameError = "Another tag already uses that name — use Merge instead"
            return
        }
        TagService.rename(id: tag.id, to: trimmed)
        renamingId = nil
        renamingDraft = ""
        renameError = nil
        reload()
    }

    private func cancelRename() {
        renamingId = nil
        renamingDraft = ""
        renameError = nil
    }

    private func colorBinding(for tag: TagDef) -> Binding<Color> {
        Binding(
            get: { tag.colorHex.flatMap(Color.init(hex:)) ?? .gray },
            set: { color in
                TagService.recolor(id: tag.id, colorHex: Self.hexRGB(of: color))
                reload()
            }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deletingTag != nil },
            set: { if !$0 { deletingTag = nil } }
        )
    }

    // MARK: - Usage counts

    /// Per-tag usage count from the derived index. One SQL pass; the
    /// table is small (one row per (record, tag) pair).
    private func loadUsage() throws -> [String: Int] {
        try DatabaseService.shared.dbPool.read { db in
            var out: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT tag_id, COUNT(*) AS n FROM record_tags GROUP BY tag_id") {
                let id: String = row["tag_id"]
                let n: Int = row["n"]
                out[id] = n
            }
            return out
        }
    }

    /// `#RRGGBB` (no alpha) for storage. Mirrors `Color.hexARGB` but
    /// drops the alpha channel — tag colors don't need transparency
    /// and `#AARRGGBB` would look unfamiliar next to the `#RRGGBB`
    /// hex strings used for type accents and theme slots.
    private static func hexRGB(of color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Modal "pick the destination tag to merge into" sheet. Separate from
/// `TagManagementSheet` to keep the alert / sheet stack clean.
private struct MergeIntoSheet: View {
    let source: TagDef
    let others: [TagDef]
    let onMerge: (String) -> Void
    let onCancel: () -> Void

    @State private var selection: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Merge \u{201C}\(source.name)\u{201D} into…")
                .font(.headline)
            Text("Every record carrying \u{201C}\(source.name)\u{201D} will instead carry the destination tag. \u{201C}\(source.name)\u{201D} is then removed from the vocabulary.")
                .font(.caption).foregroundStyle(.secondary)
            if others.isEmpty {
                Text("There are no other tags to merge into. Cancel and create one first.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                List(selection: $selection) {
                    ForEach(others) { tag in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tag.colorHex.flatMap(Color.init(hex:)) ?? .secondary)
                                .frame(width: 8, height: 8)
                            Text(tag.name)
                        }
                        .tag(tag.id)
                    }
                }
                .frame(minHeight: 180)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Merge") {
                    if let id = selection { onMerge(id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
