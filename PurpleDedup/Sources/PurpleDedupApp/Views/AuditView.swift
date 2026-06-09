import SwiftUI
import AppKit
import PurpleDedupCore

/// "Audit a folder against your Photos library" workflow. The user picks a
/// folder and their `.photoslibrary`, runs the audit, and sees which files are
/// already in Photos vs missing — then bulk-imports the missing ones.
///
/// Manual `HStack` + fixed-width sidebar (per the repo's "no NavigationSplitView
/// for new layouts" rule). Reuses `AuditEngine` / `PhotoKitImportService` from
/// the core, and `ThumbnailView` / `ProgressThrottle` / `ContentView.formatProgress`
/// from the app.
struct AuditView: View {
    @ObservedObject var settingsStore: SettingsStore

    @State private var auditFolder: URL?
    @State private var libraryURL: URL?
    @State private var matchMode: AuditEngine.MatchMode = .perceptual
    @State private var includeHiddenPhotos = true

    @State private var result: AuditEngine.AuditResult?
    @State private var isAuditing = false
    @State private var auditTask: Task<Void, Never>?
    @State private var progressLine = ""
    @State private var statusMessage = "Pick a folder and your Photos library, then click Audit."

    @State private var filter: AuditFilter = .all
    @State private var selectedMissing: Set<URL> = []

    @State private var showImportPreflight = false
    @State private var isImporting = false
    @State private var importProgress: (done: Int, total: Int) = (0, 0)
    @State private var importResult: PhotoKitImportService.ImportResult?

    @State private var photosAuthStatus: PhotoKitDeletionService.Authorization = .notDetermined
    @State private var hydrated = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 320)
            Divider()
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showImportPreflight) {
            ImportPreflightView(
                toImport: Array(selectedMissing).sorted { $0.path < $1.path },
                albumName: PhotoKitImportService.defaultAlbumName,
                onCancel: { showImportPreflight = false },
                onConfirm: {
                    let urls = Array(selectedMissing)
                    showImportPreflight = false
                    Task { await runImport(urls) }
                }
            )
        }
        .onAppear {
            photosAuthStatus = PhotoKitDeletionService.shared.currentStatus()
            hydrateIfNeeded()
        }
        .onChange(of: auditFolder?.path) { _, v in settingsStore.settings.lastAuditFolderPath = v }
        .onChange(of: libraryURL?.path) { _, v in settingsStore.settings.lastAuditLibraryPath = v }
        .onChange(of: matchMode) { _, v in settingsStore.settings.auditMatchMode = v.rawValue }
        .onChange(of: includeHiddenPhotos) { _, v in settingsStore.settings.auditIncludeHiddenPhotos = v }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Audit against Photos").font(.headline)

            pickerRow(
                title: "Folder to audit",
                value: auditFolder?.lastPathComponent,
                placeholder: "Choose a folder…",
                systemImage: "folder",
                action: pickFolder
            )

            pickerRow(
                title: "Compare against",
                value: libraryURL?.lastPathComponent,
                placeholder: "Choose Photos library…",
                systemImage: "photo.stack",
                action: pickLibrary
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Match mode").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("", selection: $matchMode) {
                    Text("Perceptual").tag(AuditEngine.MatchMode.perceptual)
                    Text("Exact").tag(AuditEngine.MatchMode.exact)
                }
                .pickerStyle(.segmented).labelsHidden()
                .disabled(isAuditing)
                Text(matchMode == .perceptual
                     ? "Also matches re-encoded / resized copies. Slower on big libraries."
                     : "Byte-identical originals only. Fast and exact.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Include hidden Photos items", isOn: $includeHiddenPhotos)
                    .toggleStyle(.checkbox)
                    .disabled(isAuditing)
                Text("Compares against the Hidden album too; matches that are hidden get a pink tag.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            auditButton

            if photosAuthStatus == .denied || photosAuthStatus == .restricted {
                photosAccessNote
            }

            statusStrip

            Spacer()
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func pickerRow(title: String, value: String?, placeholder: String,
                           systemImage: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Button(action: action) {
                HStack {
                    Image(systemName: systemImage)
                    Text(value ?? placeholder)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(value == nil ? .secondary : .primary)
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(isAuditing)
        }
    }

    @ViewBuilder
    private var auditButton: some View {
        if isAuditing {
            Button(role: .destructive) {
                auditTask?.cancel()
                statusMessage = "Cancelling…"
            } label: {
                Label("Cancel", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red)
        } else {
            Button {
                auditTask = Task { await runAudit() }
            } label: {
                Label("Audit", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(auditFolder == nil || libraryURL == nil)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var photosAccessNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Photos access is needed to import.")
                .font(.caption.bold())
            HStack(spacing: 8) {
                Button("Grant") {
                    Task { photosAuthStatus = await PhotoKitImportService.shared.requestAuthorization() }
                }
                .controlSize(.small).buttonStyle(.borderedProminent).tint(.purple)
                Button("Reset") {
                    Task {
                        PhotosAuthHelper.resetTCC()
                        photosAuthStatus = await PhotoKitImportService.shared.requestAuthorization()
                    }
                }
                .controlSize(.small)
                Button("Settings") { PhotosAuthHelper.openPrivacySettings() }
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.35), lineWidth: 0.5))
    }

    private var statusStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusMessage).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !progressLine.isEmpty {
                Text(progressLine).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if isImporting {
                ProgressView(value: Double(importProgress.done), total: Double(max(importProgress.total, 1)))
                Text("Importing \(importProgress.done)/\(importProgress.total)…")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let result {
            VStack(spacing: 0) {
                summaryBar(result)
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
                actionRow(result)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                Divider()
                resultsList(result)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 40)).foregroundStyle(.secondary.opacity(0.4))
            Text(isAuditing ? "Auditing…" : "Pick a folder and your Photos library, then click Audit.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryBar(_ result: AuditEngine.AuditResult) -> some View {
        Picker("", selection: $filter) {
            Text("All (\(result.files.count))").tag(AuditFilter.all)
            Text("In Photos (\(result.inPhotos.count))").tag(AuditFilter.inPhotos)
            Text("Missing (\(result.missing.count))").tag(AuditFilter.missing)
        }
        .pickerStyle(.segmented).labelsHidden()
    }

    @ViewBuilder
    private func actionRow(_ result: AuditEngine.AuditResult) -> some View {
        HStack(spacing: 10) {
            Button("Select all missing") {
                selectedMissing = Set(result.missingURLs)
            }
            .disabled(result.missing.isEmpty || isImporting)
            Button("Deselect") { selectedMissing = [] }
                .disabled(selectedMissing.isEmpty || isImporting)

            if let ir = importResult {
                Text(ir.summary).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }

            Spacer()

            Button {
                showImportPreflight = true
            } label: {
                Label("Import \(selectedMissing.count) → Photos", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent).tint(.purple)
            .disabled(selectedMissing.isEmpty || isImporting)
        }
    }

    private func resultsList(_ result: AuditEngine.AuditResult) -> some View {
        let files = result.files(for: filter)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(files, id: \.url) { f in
                    AuditRow(
                        file: f,
                        isSelected: selectedMissing.contains(f.url),
                        onToggleSelected: { toggleSelected(f.url) }
                    )
                    .padding(.horizontal, 12)
                    Divider()
                }
            }
        }
    }

    private func toggleSelected(_ url: URL) {
        if selectedMissing.contains(url) { selectedMissing.remove(url) }
        else { selectedMissing.insert(url) }
    }

    // MARK: - Run

    private func runAudit() async {
        guard let folder = auditFolder, let library = libraryURL else { return }
        isAuditing = true
        defer { isAuditing = false }
        result = nil
        selectedMissing = []
        importResult = nil
        progressLine = ""
        statusMessage = "Auditing…"

        let throttle = ProgressThrottle()
        do {
            let known = await PhotoKitDeletionService.shared.libraryOriginalFilenames()
            let hiddenStems = PhotoKitDeletionService.readHiddenUUIDsFromPhotosSQLite(libraryURL: library).uuids
            let db = try? Database.openDefault()
            let engine = AuditEngine(database: db)
            let r = try await engine.audit(
                folder: folder,
                photosLibrary: library,
                mode: matchMode,
                knownPhotoBasenames: known.isEmpty ? nil : known,
                includeHidden: includeHiddenPhotos,
                hiddenAssetStems: hiddenStems
            ) { p in
                if !throttle.shouldFire(interval: 0.2) { return }
                Task { @MainActor in self.progressLine = ContentView.formatProgress(p) }
            }
            self.result = r
            self.filter = .all
            self.statusMessage = r.summary
            self.progressLine = ""
        } catch is CancellationError {
            statusMessage = "Audit cancelled"; progressLine = ""
        } catch {
            statusMessage = "Audit failed: \(error.localizedDescription)"
            Log.app.error("Audit failed: \(error.localizedDescription, privacy: .public)")
        }
        auditTask = nil
    }

    private func runImport(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        importProgress = (0, urls.count)
        statusMessage = "Importing \(urls.count) file(s) into Photos…"

        let r = await PhotoKitImportService.shared.importFiles(
            urls, addToAlbumNamed: PhotoKitImportService.defaultAlbumName
        ) { done, total in
            Task { @MainActor in self.importProgress = (done, total) }
        }
        self.photosAuthStatus = PhotoKitImportService.shared.currentStatus()

        // Re-audit so the list reflects the newly-imported files, THEN surface
        // the import summary — runAudit() resets importResult/statusMessage, so
        // restoring them afterward keeps the "Imported N" banner visible.
        await runAudit()
        self.importResult = r
        self.statusMessage = r.summary
    }

    // MARK: - Pickers & persistence

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder to audit against your Photos library."
        if panel.runModal() == .OK, let url = panel.url { auditFolder = url }
    }

    private func pickLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose your Apple Photos library (.photoslibrary)."
        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            panel.directoryURL = pictures
        }
        if panel.runModal() == .OK,
           let url = panel.url, url.pathExtension.lowercased() == "photoslibrary" {
            libraryURL = url
        }
    }

    private func hydrateIfNeeded() {
        guard !hydrated else { return }
        hydrated = true
        let s = settingsStore.settings
        let fm = FileManager.default
        if let p = s.lastAuditFolderPath, fm.fileExists(atPath: p) {
            auditFolder = URL(fileURLWithPath: p)
        }
        if let p = s.lastAuditLibraryPath, fm.fileExists(atPath: p) {
            libraryURL = URL(fileURLWithPath: p)
        }
        if let m = AuditEngine.MatchMode(rawValue: s.auditMatchMode) { matchMode = m }
        includeHiddenPhotos = s.auditIncludeHiddenPhotos
    }
}
