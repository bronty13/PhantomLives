import SwiftUI
import AppKit

/// Full-screen one-by-one triage: large viewer + EXIF panel + a decision bar, driven by the
/// keyboard (Y keep, N skip, F favorite, ←/→ navigate, Space Quick Look). Walks the
/// undecided queue by default; "Show all" includes already-decided items.
struct PreviewModeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var exif: EXIFData?
    @State private var keyMonitor: Any?
    @State private var showKeywordPicker = false
    @State private var showAlbumPicker = false

    @State private var title = ""
    @State private var caption = ""
    // Baselines = what we last loaded for `editingFileId`. Write-through only fires when the
    // text genuinely differs from the baseline, so a programmatic load never writes back to
    // the wrong file during a navigation transition.
    @State private var loadedTitle = ""
    @State private var loadedCaption = ""
    @State private var editingFileId: String?
    @FocusState private var focus: Field?
    private enum Field { case title, caption }

    var body: some View {
        VStack(spacing: 0) {
            topBar    // always visible — so the Review filter is reachable even when the queue is empty
            Divider().opacity(0.3)
            if let file = appState.currentPreviewFile {
                HStack(spacing: 0) {
                    MediaViewerView(file: file)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                    Divider()
                    EXIFPanelView(exif: exif)
                        .frame(width: 300)
                        .background(.ultraThinMaterial)
                }
                Divider()
                decisionBar(file)
            } else {
                emptyQueue
            }
        }
        .task(id: appState.currentPreviewFile?.id) {
            if let file = appState.currentPreviewFile { await onFileChange(file) }
        }
        // Write-through: persist on every edit, independent of focus/navigation timing
        // (the old commit-on-focus-loss missed edits when the field was torn down on nav).
        .onChange(of: title) { _, newValue in
            guard let id = editingFileId, newValue != loadedTitle else { return }
            loadedTitle = newValue
            appState.setTitle(id, newValue)
        }
        .onChange(of: caption) { _, newValue in
            guard let id = editingFileId, newValue != loadedCaption else { return }
            loadedCaption = newValue
            appState.setCaption(id, newValue)
        }
        .onAppear { appState.startPreview(); installMonitor() }
        .onDisappear { removeMonitor() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        let queue = appState.previewQueue
        let pos = queue.isEmpty ? 0 : appState.previewIndex + 1
        return HStack(spacing: 14) {
            Button { appState.prevPreview() } label: { Image(systemName: "chevron.left") }
                .disabled(appState.previewIndex <= 0)
            VStack(spacing: 1) {
                Text("Item \(pos) of \(queue.count)").font(.headline)
                HStack(spacing: 6) {
                    Text(appState.previewDecisionFilter.label.lowercased())
                    if let f = appState.currentPreviewFile, appState.duplicateCount(for: f.id) > 1 {
                        Label("\(appState.duplicateCount(for: f.id)) copies", systemImage: "doc.on.doc.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Button { appState.nextPreview() } label: { Image(systemName: "chevron.right") }
                .disabled(appState.previewIndex >= queue.count - 1)

            Spacer()

            Picker("Review", selection: Binding(
                get: { appState.previewDecisionFilter },
                set: { appState.previewDecisionFilter = $0; appState.startPreview() }
            )) {
                ForEach(DecisionFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .help("Choose which items to step through — including ones you've already decided")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Decision bar

    private func decisionBar(_ file: MediaFile) -> some View {
        HStack(spacing: 12) {
            decisionButton("Keep", key: "Y", systemImage: "checkmark.circle.fill",
                           tint: .green, active: file.keepDecision == true) {
                appState.decidePreview(keep: true)
            }
            decisionButton("Skip", key: "N", systemImage: "xmark.circle.fill",
                           tint: .red, active: file.keepDecision == false) {
                appState.decidePreview(keep: false)
            }
            Button { appState.undoLastDecision() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!appState.canUndoDecision)
            .help(appState.lastDecisionName.map { "Undo keep/skip for \($0) (U)" } ?? "Undo last keep/skip (U)")

            Button { appState.toggleFavoritePreview() } label: {
                Image(systemName: file.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(file.isFavorite ? .pink : .secondary)
            }
            .help("Favorite (F)")

            Button { appState.toggleHiddenPreview() } label: {
                Image(systemName: file.isHidden ? "eye.slash.fill" : "eye.slash")
                    .foregroundStyle(file.isHidden ? theme.accentColor : .secondary)
            }
            .help("Hidden (H)")

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .focused($focus, equals: .title)
                .onSubmit { focus = nil }   // Return exits the field so ←/→ navigate again

            TextField("Caption", text: $caption)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .focused($focus, equals: .caption)
                .onSubmit { focus = nil }

            Button { showKeywordPicker = true } label: { Image(systemName: "tag") }
                .help("Keywords")
                .popover(isPresented: $showKeywordPicker, arrowEdge: .top) {
                    KeywordPickerView().environmentObject(appState)
                }
            Button { showAlbumPicker = true } label: { Image(systemName: "rectangle.stack") }
                .help("Albums")
                .popover(isPresented: $showAlbumPicker, arrowEdge: .top) {
                    AlbumPickerView().environmentObject(appState)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func decisionButton(_ title: String, key: String, systemImage: String, tint: Color,
                                active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
                Text(key).font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(active ? tint.opacity(0.9) : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty queue

    private var emptyQueue: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal").font(.system(size: 56, weight: .light)).foregroundStyle(theme.accentColor)
            Text(appState.selectedRootPath == nil ? "Nothing to preview" : "All caught up")
                .font(.title3.weight(.semibold))
            Text(appState.selectedRootPath == nil
                 ? "Scan a folder, then switch to Preview."
                 : "Nothing matches this filter. Use the Review menu to step through Decided, Kept, Skipped, or All items.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection sync

    private func onFileChange(_ file: MediaFile) async {
        // Set the id first, then the baselines, then the text — so the write-through
        // onChange sees text == baseline and skips (no write back to this file on load).
        editingFileId = file.id
        loadedTitle = file.title ?? ""
        loadedCaption = file.caption ?? ""
        title = loadedTitle
        caption = loadedCaption
        exif = nil
        exif = await EXIFService.load(for: file)
    }

    // MARK: - Keyboard

    private func installMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard appState.appMode == .preview else { return event }
            // Never steal keys while a text field is being edited.
            if NSApp.keyWindow?.firstResponder is NSText { return event }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "y": appState.decidePreview(keep: true); return nil
            case "n": appState.decidePreview(keep: false); return nil
            case "u": appState.undoLastDecision(); return nil
            case "f": appState.toggleFavoritePreview(); return nil
            case "h": appState.toggleHiddenPreview(); return nil
            default: break
            }
            switch event.keyCode {
            case 49: // space → Quick Look
                if let f = appState.currentPreviewFile { QuickLookCoordinator.shared.toggle(f.fileURL) }
                return nil
            case 123: appState.prevPreview(); return nil  // ←
            case 124: appState.nextPreview(); return nil  // →
            default: return event
            }
        }
    }

    private func removeMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
