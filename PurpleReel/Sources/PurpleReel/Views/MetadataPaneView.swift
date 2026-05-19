import SwiftUI

/// Kyno-style log fields: Title / Description / Rating / Reel / Scene
/// / Shot / Take / Angle / Camera / Tags. Edits commit on .onSubmit
/// (Return) and on focus loss — no Save button, matching Kyno's UX.
struct MetadataPaneView: View {
    @EnvironmentObject var appState: AppState

    /// When both `playerFps` and `onSeek` are non-nil, the pane
    /// appends a Markers section that lets the user jump to each
    /// marker without flipping tabs. Callers from contexts with no
    /// player (e.g. preview-only) omit them.
    var playerFps: Double? = nil
    var onSeek: ((Double) -> Void)? = nil

    // Local mirrors of the persisted ClipMetadata fields so the
    // TextFields stay responsive while typing. Synced back via
    // .onChange of `appState.selectedAsset` (clip change) and pushed
    // to AppState on .onSubmit / .focused(false).
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var reel: String = ""
    @State private var scene: String = ""
    @State private var shot: String = ""
    @State private var take: String = ""
    @State private var angle: String = ""
    @State private var camera: String = ""
    /// One label per audio track, joined with comma on commit so the
    /// schema stores a single text column. Kyno doesn't preserve
    /// channel labels — a doc/interview-shop differentiator.
    @State private var audioChannelNames: String = ""

    /// Drives the ⌘⌥M "focus metadata input" Kyno shortcut — the
    /// menu posts `.focusMetadata` and we route focus to the Title
    /// field. `FocusState` rather than first-responder hackery
    /// because the Title field is a SwiftUI TextField.
    @FocusState private var titleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ratingRow
                titleAndDescription
                logFieldsGrid
                audioChannelsBlock
                lutsBlock
                tagsBlock
                fcpProjectsBlock
                markersBlock
            }
            .padding(14)
        }
        .onAppear(perform: hydrate)
        .onChange(of: appState.selectedAsset?.path) { _, _ in hydrate() }
        .onChange(of: appState.clipMetadata) { _, _ in hydrate() }
        .onReceive(NotificationCenter.default.publisher(for: .focusMetadataInput)) { _ in
            titleFocused = true
        }
    }

    /// C30 — per-clip Camera + Creative LUT pickers. Pinning a LUT
    /// on a clip means the Convert dialog defaults its picker to
    /// that path for any transcode of this asset. The two roles
    /// compose: camera LUT first (inverse log → scene-linear),
    /// creative LUT second (stylistic look). Hidden when no asset
    /// is selected.
    @ViewBuilder
    private var lutsBlock: some View {
        if appState.selectedAsset != nil {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(.tint)
                    Text("LUTs")
                        .font(.callout.weight(.semibold))
                    Spacer()
                }
                lutRow(role: "Camera",
                       path: appState.clipMetadata.cameraLUTPath,
                       set: { path in
                           appState.updateClipMetadata(\.cameraLUTPath,
                                                        value: path ?? "")
                       })
                lutRow(role: "Creative",
                       path: appState.clipMetadata.creativeLUTPath,
                       set: { path in
                           appState.updateClipMetadata(\.creativeLUTPath,
                                                        value: path ?? "")
                       })
            }
        }
    }

    @ViewBuilder
    private func lutRow(role: String,
                         path: String?,
                         set: @escaping (String?) -> Void) -> some View {
        HStack(spacing: 8) {
            Text("\(role):")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
            if let path, !path.isEmpty {
                Image(systemName: "doc.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text((path as NSString).lastPathComponent)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Change…") { pickLUT(set: set) }
                    .controlSize(.small)
                Button {
                    set(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Clear the saved \(role.lowercased()) LUT for this clip")
            } else {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Pick…") { pickLUT(set: set) }
                    .controlSize(.small)
            }
        }
    }

    /// C30 — open-panel helper for the per-clip LUT pickers. Same
    /// allowedFileTypes (.cube/.3dl/.dat/.lut) as the C22 transcode-
    /// options picker so users can't pick a file LUTService.load
    /// won't understand.
    private func pickLUT(set: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["cube", "3dl", "dat", "lut"]
        panel.message = "Pick a LUT file to pin to this clip."
        if panel.runModal() == .OK, let url = panel.url {
            set(url.path)
        }
    }

    /// C25 — surfaces FCP project memberships catalogued for this
    /// asset. Hidden when there are none (avoids dead UI for users
    /// who don't round-trip through FCPXML). Each badge is the
    /// project name with the event name as a tooltip; rows are
    /// most-recently-imported first.
    @ViewBuilder
    private var fcpProjectsBlock: some View {
        if !appState.fcpProjectUsage.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "film.stack")
                        .foregroundStyle(.tint)
                    Text("FCP Projects")
                        .font(.callout.weight(.semibold))
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.fcpProjectUsage) { usage in
                        HStack(spacing: 4) {
                            Image(systemName: "film")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(usage.projectName)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let event = usage.eventName, !event.isEmpty {
                                Text("· \(event)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.12))
                        )
                        .help(
                            "Imported \(usage.importedAt.formatted(date: .abbreviated, time: .shortened))"
                            + (usage.libraryPath.map { "\n\($0)" } ?? "")
                        )
                    }
                }
            }
        }
    }

    /// Optional Markers section — only rendered when the caller
    /// passed a player fps + seek callback (i.e. when the pane is
    /// hosted next to an actual player). Otherwise the metadata pane
    /// stays compact.
    @ViewBuilder
    private var markersBlock: some View {
        if let fps = playerFps, let seek = onSeek {
            Divider()
            MarkersListView(fps: fps, onJumpTo: seek)
        }
    }

    // MARK: - Sections

    private var ratingRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Rating").foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        appState.setRating(stars: star == currentStars ? 0 : star)
                    } label: {
                        Image(systemName: star <= currentStars ? "star.fill" : "star")
                            .foregroundStyle(star <= currentStars ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    appState.setRating(stars: 0)
                } label: {
                    Image(systemName: "circle.slash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear rating")
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var titleAndDescription: some View {
        labelledField("Title") {
            TextField("", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit { commit(\.title, title) }
        }
        labelledField("Description") {
            TextEditor(text: $description)
                .frame(minHeight: 56, maxHeight: 110)
                .padding(4)
                .background(Color.secondary.opacity(0.08),
                              in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.25))
                )
                .onChange(of: description) { _, new in
                    commit(\.description, new)
                }
        }
    }

    @ViewBuilder
    private var logFieldsGrid: some View {
        Divider()
        labelledField("Reel")   { logField($reel,   key: \.reel) }
        labelledField("Scene")  { logField($scene,  key: \.scene) }
        labelledField("Shot")   { logField($shot,   key: \.shot) }
        labelledField("Take")   { logField($take,   key: \.take) }
        labelledField("Angle")  { logField($angle,  key: \.angle) }
        labelledField("Camera") { logField($camera, key: \.camera) }
    }

    @ViewBuilder
    private var audioChannelsBlock: some View {
        Divider()
        labelledField("Audio Channels") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("e.g. boom, lav-Alice, lav-Bob",
                           text: $audioChannelNames)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitChannelNames() }
                Text("Comma-separated track labels. Survives transcode + FCPXML export; Kyno doesn't preserve these at all.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commitChannelNames() {
        let trimmed = audioChannelNames.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.updateClipMetadata(\.audioChannelNames,
                                      value: trimmed)
    }

    @ViewBuilder
    private var tagsBlock: some View {
        Divider()
        labelledField("Tags") {
            VStack(alignment: .leading, spacing: 6) {
                if appState.tags.isEmpty {
                    Text("No tags.").foregroundStyle(.secondary).font(.caption)
                } else {
                    FlowTagList(tags: appState.tags) { tag in
                        appState.removeTag(name: tag.name)
                    }
                }
                TagEntryField()
            }
        }
    }

    // MARK: - Helpers

    private var currentStars: Int { appState.rating?.stars ?? 0 }

    private func logField(_ binding: Binding<String>,
                          key: WritableKeyPath<ClipMetadata, String?>) -> some View {
        TextField("", text: binding)
            .textFieldStyle(.roundedBorder)
            .onSubmit { commit(key, binding.wrappedValue) }
    }

    @ViewBuilder
    private func labelledField<Content: View>(_ label: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commit(_ key: WritableKeyPath<ClipMetadata, String?>,
                        _ value: String) {
        appState.updateClipMetadata(key, value: value)
    }

    private func hydrate() {
        let m = appState.clipMetadata
        title = m.title ?? ""
        description = m.description ?? ""
        reel = m.reel ?? ""
        scene = m.scene ?? ""
        shot = m.shot ?? ""
        take = m.take ?? ""
        angle = m.angle ?? ""
        camera = m.camera ?? ""
        audioChannelNames = m.audioChannelNames ?? ""
    }
}

/// Compact tag-pill list. Each pill is a button that removes the tag.
private struct FlowTagList: View {
    let tags: [Tag]
    var onRemove: (Tag) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 80, maximum: 160), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.name) { tag in
                Button {
                    onRemove(tag)
                } label: {
                    HStack(spacing: 4) {
                        Text(tag.name).font(.caption)
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

/// Inline "Add tag and press Return" field — matches Kyno's tag UX.
private struct TagEntryField: View {
    @EnvironmentObject var appState: AppState
    @State private var draft: String = ""

    var body: some View {
        TextField("Add tag and press Return", text: $draft)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                appState.addTag(name: trimmed)
                draft = ""
            }
    }
}
