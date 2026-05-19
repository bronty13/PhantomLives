import SwiftUI

/// "Export FCPX XML" dialog (Kyno-parity, Image #88). Collects the
/// options that drive `FCPXMLWriter.makeXML(...)` before the file
/// hits disk. Defaults match Kyno's: Copy to library, no relative
/// paths, Open after export, Keywords from tags, Favorites from
/// rating ≥ 1 star.
struct FCPXMLExportSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var options: FCPXMLExportOptions
    /// Scope chosen from the menu (selected vs all catalogued). The
    /// dialog doesn't expose a Picker for it — that came from the
    /// caller — but we need it to know how many clips will export.
    let scope: AppState.FCPXMLExportScope

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                Grid(alignment: .leading,
                      horizontalSpacing: 12, verticalSpacing: 12) {
                    libraryRow
                    eventNameRow
                    destinationRow
                    filesRow
                    Divider().gridCellColumns(2)
                    metadataMappingHeader
                    keywordsRow
                    favoritesRow
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 600)
    }

    private var header: some View {
        HStack {
            Text("Export FCPX XML").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Library / event

    private var libraryRow: some View {
        GridRow {
            Text("FCPX Library:").foregroundStyle(.secondary)
            // Kyno's pattern: pick a target library inside FCP from a
            // dropdown. PurpleReel doesn't (yet) introspect FCP's open
            // libraries, so the row presents a single read-only option
            // explaining the user picks it when FCP receives the file.
            Text("Select in Final Cut")
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12),
                              in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var eventNameRow: some View {
        GridRow {
            Text("Event Name:").foregroundStyle(.secondary)
            TextField("", text: $options.eventName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    /// C38 — explicit destination picker + recents dropdown.
    /// Defaults to "(default: ~/Downloads/PurpleReel/exports/)";
    /// once the user picks a folder, the recents list grows.
    private var destinationRow: some View {
        GridRow {
            Text("Save to:").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(options.outputDir?.path
                      ?? "(default: ~/Downloads/PurpleReel/exports/)")
                    .font(.callout)
                    .foregroundStyle(options.outputDir == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Choose…") { pickOutputDir() }
                let recents = RecentDestinations.list(.fcpxml)
                if !recents.isEmpty {
                    Menu {
                        Button("Use Default") {
                            options.outputDir = nil
                        }
                        Divider()
                        ForEach(recents, id: \.path) { url in
                            Button(url.path) {
                                options.outputDir = url
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                    .help("Recent FCPXML destinations")
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
    }

    private func pickOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = options.outputDir
        if panel.runModal() == .OK, let url = panel.url {
            options.outputDir = url
        }
    }

    private var filesRow: some View {
        GridRow(alignment: .top) {
            Text("Files:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: $options.fileReference) {
                    ForEach(FCPXMLExportOptions.FileReference.allCases,
                             id: \.self) { ref in
                        Text(ref.displayName).tag(ref)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Toggle("Use relative paths", isOn: $options.useRelativePaths)
                Toggle("Open exported file", isOn: $options.openExportedFile)
            }
        }
    }

    // MARK: - Metadata mapping

    private var metadataMappingHeader: some View {
        GridRow {
            Text("Metadata mapping")
                .font(.title3.weight(.semibold))
                .gridCellColumns(2)
        }
    }

    private var keywordsRow: some View {
        GridRow(alignment: .top) {
            Text("Keywords:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("From tags",     isOn: $options.keywordsFromTags)
                Toggle("From subclips", isOn: $options.keywordsFromSubclips)
                Toggle("From folders",  isOn: $options.keywordsFromFolders)
                if options.keywordsFromFolders {
                    Picker("", selection: $options.folderKeywordScope) {
                        ForEach(FCPXMLExportOptions.FolderKeywordScope.allCases,
                                 id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)
                    .padding(.leading, 20)
                }
            }
        }
    }

    private var favoritesRow: some View {
        GridRow(alignment: .top) {
            Text("Favorites:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("From subclips",          isOn: $options.favoritesFromSubclips)
                Toggle("From in and out points", isOn: $options.favoritesFromInOutPoints)
                Toggle("From rating",            isOn: $options.favoritesFromRating)
                if options.favoritesFromRating {
                    Picker("", selection: $options.favoritesMinStars) {
                        ForEach(1...5, id: \.self) { stars in
                            Text("At least: \(String(repeating: "★", count: stars))")
                                .tag(stars)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220, alignment: .leading)
                    .padding(.leading, 20)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Export") {
                _ = appState.exportFCPXML(scope: scope, options: options)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(options.eventName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
