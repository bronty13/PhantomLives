import SwiftUI

/// The transport object between the batch-edit sheet UI and
/// `AppState.applyBatchMetadata(_:)`. Lives outside the view so it can
/// be tested without instantiating SwiftUI.
struct BatchMetadataChange {
    // Per-field opt-in toggles — only ticked fields are written. Lets
    // the user batch-set Scene and Camera while leaving Description
    // untouched, for example.
    var applyRating     = false
    var applyTags       = false
    var applyTitle      = false
    var applyDescription = false
    var applyReel       = false
    var applyScene      = false
    var applyShot       = false
    var applyTake       = false
    var applyAngle      = false
    var applyCamera     = false

    var rating: Int = 0          // 0…5
    var tagsToAdd: [String] = []  // additive — never clears existing
    var title: String        = ""
    var description: String  = ""
    var reel: String         = ""
    var scene: String        = ""
    var shot: String         = ""
    var take: String         = ""
    var angle: String        = ""
    var camera: String       = ""
}

/// "Edit Multiple…" sheet (⌘⇧M) — applies log fields, rating, and
/// additive tags across the current multi-selection (or the primary
/// single selection if nothing is multi-selected).
///
/// Each row has an **Apply** checkbox in front of the field — only
/// ticked rows are written. Unticked rows leave that field untouched
/// on every target clip, so the user can batch Scene+Camera without
/// blowing away the per-clip Description.
struct BatchMetadataSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var change = BatchMetadataChange()
    @State private var tagDraft: String = ""
    @State private var appliedSummary: String?

    private var targetCount: Int {
        appState.selectedAssetPaths.isEmpty
            ? (appState.selectedAsset == nil ? 0 : 1)
            : appState.selectedAssetPaths.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ratingRow
                    tagsRow
                    Divider()
                    Text("Log fields").font(.headline)
                    logFieldsGrid
                    Divider()
                    helpText
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 600)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Edit Metadata for \(targetCount) clip\(targetCount == 1 ? "" : "s")")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var ratingRow: some View {
        HStack(spacing: 10) {
            applyToggle(\.applyRating, label: "Rating")
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        change.applyRating = true
                        change.rating = star == change.rating ? 0 : star
                    } label: {
                        Image(systemName: star <= change.rating ? "star.fill" : "star")
                            .foregroundStyle(star <= change.rating ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    change.applyRating = true
                    change.rating = 0
                } label: {
                    Image(systemName: "circle.slash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear rating")
            }
            .disabled(!change.applyRating)
            .opacity(change.applyRating ? 1 : 0.5)
            Spacer()
        }
    }

    @ViewBuilder
    private var tagsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            applyToggle(\.applyTags, label: "Add Tags")
            VStack(alignment: .leading, spacing: 6) {
                if !change.tagsToAdd.isEmpty {
                    FlowChips(tags: change.tagsToAdd) { tag in
                        change.tagsToAdd.removeAll { $0 == tag }
                        if change.tagsToAdd.isEmpty { change.applyTags = false }
                    }
                }
                HStack(spacing: 6) {
                    TextField("Type a tag and press Return", text: $tagDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitTagDraft() }
                    Button("Add") { commitTagDraft() }
                        .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Tags are added to every selected clip — existing tags stay.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .disabled(!change.applyTags && change.tagsToAdd.isEmpty)
            .opacity((change.applyTags || !change.tagsToAdd.isEmpty) ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private var logFieldsGrid: some View {
        labelledLogField("Title",       binding: $change.title,       apply: \.applyTitle)
        labelledLogField("Description", binding: $change.description, apply: \.applyDescription, multiline: true)
        labelledLogField("Reel",        binding: $change.reel,        apply: \.applyReel)
        labelledLogField("Scene",       binding: $change.scene,       apply: \.applyScene)
        labelledLogField("Shot",        binding: $change.shot,        apply: \.applyShot)
        labelledLogField("Take",        binding: $change.take,        apply: \.applyTake)
        labelledLogField("Angle",       binding: $change.angle,       apply: \.applyAngle)
        labelledLogField("Camera",      binding: $change.camera,      apply: \.applyCamera)
    }

    private var helpText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Only fields with the Apply checkbox ticked are written. "
                 + "Leaving a ticked field empty clears the value on every "
                 + "selected clip.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let summary = appliedSummary {
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Apply") { apply() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!anyFieldTicked || targetCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Helpers

    private var anyFieldTicked: Bool {
        change.applyRating || change.applyTags || change.applyTitle
            || change.applyDescription || change.applyReel
            || change.applyScene || change.applyShot || change.applyTake
            || change.applyAngle || change.applyCamera
    }

    private func applyToggle(_ key: WritableKeyPath<BatchMetadataChange, Bool>,
                              label: String) -> some View {
        Toggle(isOn: Binding(
            get: { change[keyPath: key] },
            set: { change[keyPath: key] = $0 }
        )) {
            Text(label)
                .frame(width: 100, alignment: .trailing)
        }
        .toggleStyle(.checkbox)
    }

    @ViewBuilder
    private func labelledLogField(_ label: String,
                                  binding: Binding<String>,
                                  apply: WritableKeyPath<BatchMetadataChange, Bool>,
                                  multiline: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            applyToggle(apply, label: label)
            if multiline {
                TextEditor(text: binding)
                    .frame(minHeight: 50, maxHeight: 90)
                    .padding(4)
                    .background(Color.secondary.opacity(0.08),
                                  in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.25))
                    )
            } else {
                TextField("", text: binding)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .disabled(!change[keyPath: apply])
        .opacity(change[keyPath: apply] ? 1 : 0.5)
    }

    private func commitTagDraft() {
        let trimmed = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !change.tagsToAdd.contains(trimmed) else {
            tagDraft = ""
            return
        }
        change.tagsToAdd.append(trimmed)
        change.applyTags = true
        tagDraft = ""
    }

    private func apply() {
        // Bring the typed-but-not-Returned tag draft into the set if
        // the user clicked Apply while it was still in the field.
        commitTagDraft()
        let n = appState.applyBatchMetadata(change)
        appliedSummary = "Applied to \(n) clip\(n == 1 ? "" : "s")."
        // Auto-dismiss after a beat — feels snappier than making the
        // user reach for Cancel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            dismiss()
        }
    }
}

/// Reusable removable-pill row (matches the Metadata pane's tag
/// display). Kept private to this file so the public surface stays
/// minimal.
private struct FlowChips: View {
    let tags: [String]
    var onRemove: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 80, maximum: 160), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onRemove(tag)
                } label: {
                    HStack(spacing: 4) {
                        Text(tag).font(.caption)
                        Image(systemName: "xmark").font(.system(size: 9))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
