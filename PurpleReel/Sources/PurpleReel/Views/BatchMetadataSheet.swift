import SwiftUI

/// The transport object between the batch-edit sheet UI and
/// `AppState.applyBatchMetadata(_:)`. Lives outside the view so it can
/// be tested without instantiating SwiftUI.
struct BatchMetadataChange {
    // Per-field opt-in toggles — only ticked fields are written. Lets
    // the user batch-set Scene and Camera while leaving Description
    // untouched, for example. C8 swapped the UI's checkboxes for
    // "Keep / Set" Pickers (Kyno-parity, Image #87) but the model
    // shape is unchanged so `AppState.applyBatchMetadata(_:)` stays
    // identical downstream.
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

    var rating: Int = 0          // 0…5, or -1 for Rejected (C7 sentinel)
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

/// "Edit Multiple Items…" sheet (⌘⇧M) — applies log fields, rating,
/// and additive tags across the current multi-selection (or the
/// primary single selection if nothing is multi-selected).
///
/// Per-field **Keep / Set** Picker on the left (Kyno-parity,
/// Image #87). Only `.set` rows are written; `.keep` rows leave that
/// field untouched on every target clip. Lets the user batch
/// Scene+Camera without blowing away the per-clip Description.
struct BatchMetadataSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var change = BatchMetadataChange()
    @State private var tagDraft: String = ""
    @State private var appliedSummary: String?

    /// Per-field mode driving the Keep/Set Picker. Bound to the
    /// existing `applyX: Bool` flags via a translating Binding so the
    /// transport struct stays untouched.
    enum FieldMode: String, CaseIterable, Hashable {
        case keep, set
        var displayName: String {
            switch self {
            case .keep: return "Keep"
            case .set:  return "Set"
            }
        }
    }

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
                Grid(alignment: .leading,
                      horizontalSpacing: 12, verticalSpacing: 10) {
                    titleRow
                    descriptionRow
                    GridRow {
                        Color.clear.frame(height: 6)
                            .gridCellColumns(3)
                    }
                    ratingRow
                    logFieldRow("Reel",   binding: $change.reel,
                                  apply: \.applyReel)
                    logFieldRow("Scene",  binding: $change.scene,
                                  apply: \.applyScene)
                    logFieldRow("Shot",   binding: $change.shot,
                                  apply: \.applyShot)
                    logFieldRow("Take",   binding: $change.take,
                                  apply: \.applyTake)
                    logFieldRow("Angle",  binding: $change.angle,
                                  apply: \.applyAngle)
                    logFieldRow("Camera", binding: $change.camera,
                                  apply: \.applyCamera)
                    tagsRow
                }
                .padding(20)
                if let summary = appliedSummary {
                    Text(summary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 640)
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Text("Edit Multiple Items").font(.headline)
            Spacer()
            Text("\(targetCount) clip\(targetCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("OK") { apply() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!anyFieldSet || targetCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Row builders

    private var titleRow: some View {
        GridRow {
            keepPicker(apply: \.applyTitle)
            Text("Title:").foregroundStyle(.secondary)
            TextField("", text: $change.title)
                .textFieldStyle(.roundedBorder)
                .disabled(!change.applyTitle)
        }
    }

    private var descriptionRow: some View {
        GridRow(alignment: .top) {
            keepPicker(apply: \.applyDescription)
            Text("Description:").foregroundStyle(.secondary)
            TextEditor(text: $change.description)
                .frame(minHeight: 60, maxHeight: 90)
                .padding(4)
                .background(Color.secondary.opacity(0.08),
                              in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.25))
                )
                .disabled(!change.applyDescription)
                .opacity(change.applyDescription ? 1 : 0.55)
        }
    }

    /// Rating row — 5 stars + a Rejected (Ø) button per Image #87.
    /// Rejected stores `stars = -1` (C7 sentinel); the Star buttons
    /// store 1…5 and the Ø button stores -1.
    private var ratingRow: some View {
        GridRow {
            keepPicker(apply: \.applyRating)
            Text("Rating:").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        change.applyRating = true
                        change.rating = star == change.rating ? 0 : star
                    } label: {
                        Image(systemName: star <= change.rating
                              && change.rating > 0
                                ? "star.fill" : "star")
                            .foregroundStyle(star <= change.rating
                                              && change.rating > 0
                                                ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                // Rejected (Ø) — sentinel `stars = -1`. Visual treatment
                // matches Kyno's Image #87 "circle-slash" icon next to
                // the stars.
                Button {
                    change.applyRating = true
                    change.rating = change.rating == -1 ? 0 : -1
                } label: {
                    Image(systemName: "nosign")
                        .foregroundStyle(change.rating == -1
                                          ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("Rejected")
                Spacer()
            }
            .disabled(!change.applyRating)
            .opacity(change.applyRating ? 1 : 0.55)
        }
    }

    /// Generic single-line log-field row.
    @ViewBuilder
    private func logFieldRow(_ label: String,
                              binding: Binding<String>,
                              apply: WritableKeyPath<BatchMetadataChange, Bool>)
        -> some View {
        GridRow {
            keepPicker(apply: apply)
            Text("\(label):").foregroundStyle(.secondary)
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(!change[keyPath: apply])
                .opacity(change[keyPath: apply] ? 1 : 0.55)
        }
    }

    /// Tags row — Kyno's pattern has the picker + a list below with a
    /// Remove button. We mirror it: type-or-pick tag, accumulate
    /// chips, click any chip to remove.
    private var tagsRow: some View {
        GridRow(alignment: .top) {
            keepPicker(apply: \.applyTags)
            Text("Tags:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Select or Create Tag", text: $tagDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitTagDraft() }
                    Button("Add") { commitTagDraft() }
                        .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !change.tagsToAdd.isEmpty {
                    FlowChips(tags: change.tagsToAdd) { tag in
                        change.tagsToAdd.removeAll { $0 == tag }
                        if change.tagsToAdd.isEmpty {
                            change.applyTags = false
                        }
                    }
                }
                Text("Tags are added to every selected clip — existing tags stay. Click any chip to remove it from the list.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .disabled(!change.applyTags && change.tagsToAdd.isEmpty)
            .opacity((change.applyTags || !change.tagsToAdd.isEmpty)
                      ? 1 : 0.55)
        }
    }

    // MARK: - Keep/Set picker helper

    /// Bridges the existing `applyX: Bool` model to the Kyno-shaped
    /// `Keep | Set` Picker. Selecting Set ticks the apply flag; Keep
    /// clears it. The Picker is the standard `.menu` style with a
    /// fixed-width frame so every row aligns vertically (Image #87).
    private func keepPicker(
        apply key: WritableKeyPath<BatchMetadataChange, Bool>
    ) -> some View {
        let binding = Binding<FieldMode>(
            get: { change[keyPath: key] ? .set : .keep },
            set: { change[keyPath: key] = ($0 == .set) }
        )
        return Picker("", selection: binding) {
            ForEach(FieldMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 90, alignment: .leading)
    }

    // MARK: - Apply

    private var anyFieldSet: Bool {
        change.applyRating || change.applyTags || change.applyTitle
            || change.applyDescription || change.applyReel
            || change.applyScene || change.applyShot || change.applyTake
            || change.applyAngle || change.applyCamera
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
        // the user clicked OK while it was still in the field.
        commitTagDraft()
        let n = appState.applyBatchMetadata(change)
        appliedSummary = "Applied to \(n) clip\(n == 1 ? "" : "s")."
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
