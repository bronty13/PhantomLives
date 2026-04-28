import SwiftUI
import UniformTypeIdentifiers
import SnRCore

// MARK: - Root

struct ContentView: View {
    @ObservedObject var viewModel: SearchReplaceViewModel
    @State private var showFilters: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            CriteriaPane(viewModel: viewModel, showFilters: $showFilters)
                .padding(10)
                .background(.background.secondary)
            Divider()
            VSplitView {
                ResultsOutline(viewModel: viewModel)
                    .frame(minHeight: 220, idealHeight: 360)
                ContextPane(viewModel: viewModel)
                    .frame(minHeight: 140, idealHeight: 200)
            }
            Divider()
            StatusBar(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSaveFavoriteSheet) { SaveFavoriteSheet(viewModel: viewModel) }
        .sheet(isPresented: $viewModel.showStringPairsSheet) { StringPairsSheet(viewModel: viewModel) }
        .sheet(isPresented: $viewModel.showAskEachSheet) { AskEachSheet(viewModel: viewModel) }
    }
}

// MARK: - Criteria

private struct CriteriaPane: View {
    @ObservedObject var viewModel: SearchReplaceViewModel
    @Binding var showFilters: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Find:").frame(width: 64, alignment: .trailing)
                    TextField("text or pattern", text: $viewModel.pattern)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await viewModel.runSearch() } }
                    HStack(spacing: 4) {
                        Toggle(".*", isOn: $viewModel.isRegex).help("Regular expression")
                        Toggle("Aa", isOn: $viewModel.caseInsensitive).help("Case-insensitive")
                        Toggle("⟦w⟧", isOn: $viewModel.wholeWord).help("Whole word")
                        Toggle("¶", isOn: $viewModel.multiline).help("Multi-line")
                    }
                    .toggleStyle(.button).controlSize(.small)
                }
                GridRow {
                    Text("Replace:").frame(width: 64, alignment: .trailing)
                    TextField("replacement (optional)", text: $viewModel.replacement)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(2)
                        .onSubmit { Task { await viewModel.runSearch() } }
                }
                GridRow {
                    Text("Folders:").frame(width: 64, alignment: .trailing)
                    FolderListView(roots: $viewModel.roots,
                                   add: { viewModel.pickRoot() },
                                   remove: { viewModel.removeRoot($0) })
                        .gridCellColumns(2)
                }
                GridRow {
                    Text("Include:").frame(width: 64, alignment: .trailing)
                    TextField("*.swift; *.m  (file masks, ; separated)", text: $viewModel.includeGlobs)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await viewModel.runSearch() } }
                    Toggle(".gitignore", isOn: $viewModel.honorGitignore)
                        .toggleStyle(.checkbox).controlSize(.small)
                }
                GridRow {
                    Text("Exclude:").frame(width: 64, alignment: .trailing)
                    TextField("Pods/**; .build/**", text: $viewModel.excludeGlobs)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(2)
                        .onSubmit { Task { await viewModel.runSearch() } }
                }
            }

            DisclosureGroup(isExpanded: $showFilters) {
                FiltersPane(viewModel: viewModel)
            } label: {
                Label("Filters & sources", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if viewModel.isWorking {
                    Button {
                        viewModel.stopSearch()
                    } label: { Label("Stop", systemImage: "stop.circle") }
                    .keyboardShortcut(".", modifiers: [.command])
                } else {
                    Button {
                        Task { await viewModel.runSearch() }
                    } label: { Label("Find", systemImage: "magnifyingglass") }
                    .keyboardShortcut(.return, modifiers: [.command])
                }

                Button {
                    Task { await viewModel.commit() }
                } label: { Label("Replace All", systemImage: "arrow.triangle.2.circlepath") }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(viewModel.fileMatches.isEmpty)

                Button {
                    viewModel.startAskEach()
                } label: { Label("Replace with Prompt…", systemImage: "questionmark.bubble") }
                .disabled(viewModel.fileMatches.isEmpty)

                Button {
                    if viewModel.stringPairs.isEmpty { viewModel.stringPairs = [StringPair()] }
                    viewModel.showStringPairsSheet = true
                } label: { Label("String Pairs…", systemImage: "list.bullet.rectangle") }

                Spacer()

                ExportMenu(viewModel: viewModel)
                FavoritesMenu(viewModel: viewModel)
            }
        }
    }
}

private struct FiltersPane: View {
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Toggle("Date range:", isOn: $viewModel.useDateFilter).controlSize(.small)
                DatePicker("after",  selection: $viewModel.modifiedAfter,  displayedComponents: .date)
                    .disabled(!viewModel.useDateFilter).controlSize(.small)
                DatePicker("before", selection: $viewModel.modifiedBefore, displayedComponents: .date)
                    .disabled(!viewModel.useDateFilter).controlSize(.small)
            }
            GridRow {
                Toggle("Max file size:", isOn: $viewModel.useSizeFilter).controlSize(.small)
                Stepper(value: $viewModel.maxFileBytesMB, in: 1...4096, step: 1) {
                    Text("\(viewModel.maxFileBytesMB) MB").monospacedDigit()
                }.disabled(!viewModel.useSizeFilter).controlSize(.small)
                Color.clear.frame(height: 0)
            }
            GridRow {
                Text("Sources:").frame(alignment: .leading).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Toggle("ZIP", isOn: $viewModel.searchInsideArchives).controlSize(.small)
                    Toggle("Office", isOn: $viewModel.searchInsideOOXML).controlSize(.small)
                    Toggle("PDF",  isOn: $viewModel.searchInsidePDFs).controlSize(.small)
                }
                .toggleStyle(.checkbox)
                .gridCellColumns(2)
            }
        }
        .padding(.leading, 16)
        .padding(.top, 4)
    }
}

private struct FolderListView: View {
    @Binding var roots: [URL]
    var add: () -> Void
    var remove: (URL) -> Void

    var body: some View {
        HStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if roots.isEmpty {
                        Text("(no folders — click + to add)").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(roots, id: \.self) { url in
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text(url.lastPathComponent)
                            Button(action: { remove(url) }) {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 6))
                        .help(url.path)
                    }
                }
            }
            Button(action: add) { Image(systemName: "plus") }.buttonStyle(.borderless)
        }
    }
}

private struct FavoritesMenu: View {
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        Menu {
            Button("Save current as Favorite…") {
                viewModel.newFavoriteName = viewModel.pattern
                viewModel.showSaveFavoriteSheet = true
            }
            Divider()
            if viewModel.favorites.isEmpty {
                Text("No saved favorites").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.favorites) { fav in
                    Button(fav.name) { viewModel.loadFavorite(fav) }
                }
                Divider()
                Menu("Delete") {
                    ForEach(viewModel.favorites) { fav in
                        Button(fav.name) { viewModel.deleteFavorite(fav) }
                    }
                }
            }
        } label: { Label("Favorites", systemImage: "star") }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 140)
    }
}

private struct ExportMenu: View {
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        Menu {
            ForEach(SearchReplaceViewModel.ExportFormat.allCases) { fmt in
                Button("Export as \(fmt.rawValue)…") { viewModel.exportResults(format: fmt) }
            }
        } label: { Label("Export", systemImage: "square.and.arrow.up") }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 110)
        .disabled(viewModel.fileMatches.isEmpty)
    }
}

// MARK: - Sheets

private struct SaveFavoriteSheet: View {
    @ObservedObject var viewModel: SearchReplaceViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Favorite").font(.headline)
            TextField("Favorite name", text: $viewModel.newFavoriteName)
                .textFieldStyle(.roundedBorder).frame(minWidth: 320)
            HStack {
                Spacer()
                Button("Cancel") { viewModel.showSaveFavoriteSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let name = viewModel.newFavoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    viewModel.saveAsFavorite(name: name)
                    viewModel.showSaveFavoriteSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.newFavoriteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20)
    }
}

private struct StringPairsSheet: View {
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Multiple Search/Replace Pairs").font(.headline)
            Text("Each pair runs sequentially against the same folders/masks. One backup session covers them all.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach($viewModel.stringPairs) { $pair in
                        HStack(spacing: 6) {
                            TextField("find", text: $pair.find).textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField("replace", text: $pair.replace).textFieldStyle(.roundedBorder)
                            Button {
                                viewModel.stringPairs.removeAll { $0.id == pair.id }
                                if viewModel.stringPairs.isEmpty { viewModel.stringPairs = [StringPair()] }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }.frame(minHeight: 180)
            HStack {
                Button { viewModel.stringPairs.append(StringPair()) } label: {
                    Label("Add Pair", systemImage: "plus.circle")
                }
                Spacer()
                Button("Cancel") { viewModel.showStringPairsSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Run All Pairs") {
                    viewModel.showStringPairsSheet = false
                    Task { await viewModel.runStringPairs() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.stringPairs.contains(where: { !$0.find.isEmpty }))
            }
        }
        .padding(20).frame(minWidth: 560, minHeight: 340)
    }
}

private struct AskEachSheet: View {
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.askIndex < viewModel.pendingAskHits.count {
                let entry = viewModel.pendingAskHits[viewModel.askIndex]
                Text("Replace this match? (\(viewModel.askIndex + 1) of \(viewModel.pendingAskHits.count))")
                    .font(.headline)
                Text(entry.file.url.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                HStack(alignment: .top) {
                    Text("L\(entry.hit.line)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    Text(MatchHighlight.attributed(
                        line: entry.hit.preview,
                        matchedText: entry.hit.matchedText,
                        caseInsensitive: viewModel.caseInsensitive,
                        replacement: viewModel.replacement.isEmpty ? nil : viewModel.replacement
                    ))
                }
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button("Cancel") {
                        Task { await viewModel.answerAsk(accept: false, cancel: true) }
                    }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Skip File") {
                        Task { await viewModel.answerAsk(accept: false, skipRestOfFile: true) }
                    }
                    Button("Skip") {
                        Task { await viewModel.answerAsk(accept: false) }
                    }.keyboardShortcut("n")
                    Button("Replace All") {
                        Task { await viewModel.answerAsk(accept: true, applyToAll: true) }
                    }.keyboardShortcut("a")
                    Button("Replace") {
                        Task { await viewModel.answerAsk(accept: true) }
                    }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20).frame(minWidth: 560)
    }
}

// MARK: - Results outline

private struct ResultsOutline: View {
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        if viewModel.fileMatches.isEmpty {
            VStack { Spacer(); Text("No results").foregroundStyle(.secondary); Spacer() }
                .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(viewModel.fileMatches) { file in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { viewModel.expandedFiles.contains(file.id) },
                            set: { v in
                                if v { viewModel.expandedFiles.insert(file.id) }
                                else { viewModel.expandedFiles.remove(file.id) }
                            }
                        )
                    ) {
                        ForEach(file.hits) { hit in
                            HitRow(file: file, hit: hit, viewModel: viewModel)
                        }
                    } label: {
                        FileRowLabel(file: file, viewModel: viewModel)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

private struct FileRowLabel: View {
    let file: FileMatches
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
            Text(file.url.path).lineLimit(1).truncationMode(.middle).help(file.url.path)
            Spacer()
            Text("\(file.hits.count)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(.background.tertiary, in: Capsule())
        }
        .onDrag { NSItemProvider(object: file.url as NSURL) }
        .contextMenu {
            Button("Open") { viewModel.openWithDefaultApp(file.url) }
            Button("Open in Editor") { viewModel.openInExternalEditor(file.url) }
            Button("Reveal in Finder") { viewModel.revealInFinder(file.url) }
            Button("Copy Path") { viewModel.copyToPasteboard(file.url.path) }
            Divider()
            Button("Uncheck All Hits in File") {
                for h in file.hits where h.accepted { viewModel.toggleHit(fileID: file.id, hitID: h.id) }
            }
            Button("Check All Hits in File") {
                for h in file.hits where !h.accepted { viewModel.toggleHit(fileID: file.id, hitID: h.id) }
            }
        }
    }
}

private struct HitRow: View {
    let file: FileMatches
    let hit: Hit
    @ObservedObject var viewModel: SearchReplaceViewModel

    private var isSelected: Bool {
        viewModel.selectedFile == file.id && viewModel.selectedHitID == hit.id
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Toggle("", isOn: Binding(
                get: { hit.accepted },
                set: { _ in viewModel.toggleHit(fileID: file.id, hitID: hit.id) }
            )).toggleStyle(.checkbox).labelsHidden()

            Text(String(format: "%5d", hit.line))
                .foregroundStyle(.secondary)
                .font(.system(.caption, design: .monospaced))

            Text(MatchHighlight.attributed(
                line: hit.preview,
                matchedText: hit.matchedText,
                caseInsensitive: viewModel.caseInsensitive,
                replacement: viewModel.replacement.isEmpty ? nil : viewModel.replacement
            ))
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1).padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectHit(fileID: file.id, hitID: hit.id) }
        .onDrag { NSItemProvider(object: file.url as NSURL) }
        .contextMenu {
            Button("Open File") { viewModel.openWithDefaultApp(file.url) }
            Button("Open in Editor") { viewModel.openInExternalEditor(file.url) }
            Button("Reveal in Finder") { viewModel.revealInFinder(file.url) }
            Divider()
            Button("Copy Match") { viewModel.copyToPasteboard(hit.matchedText) }
            Button("Copy Line") { viewModel.copyToPasteboard(hit.preview) }
            Button("Copy Path:Line") { viewModel.copyToPasteboard("\(file.url.path):\(hit.line)") }
        }
    }
}

// MARK: - Context preview

private struct ContextPane: View {
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        if let file = viewModel.selectedFileMatches, let hit = viewModel.selectedHit {
            let (lines, hitIndex) = viewModel.loadContext(for: file, hit: hit)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(file.url.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Open in Editor") { viewModel.openInExternalEditor(file.url) }
                            .controlSize(.small).buttonStyle(.borderless)
                        Text("Line \(hit.line), col \(hit.columnStart)")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.bottom, 4)

                    let firstLineNumber = max(1, hit.line - hitIndex)
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, raw in
                        let absLine = firstLineNumber + idx
                        let isHitLine = idx == hitIndex
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(absLine)")
                                .frame(width: 44, alignment: .trailing)
                                .foregroundStyle(.secondary)
                                .font(.system(.caption, design: .monospaced))
                            if isHitLine {
                                Text(MatchHighlight.attributed(
                                    line: raw, matchedText: hit.matchedText,
                                    caseInsensitive: viewModel.caseInsensitive,
                                    replacement: viewModel.replacement.isEmpty ? nil : viewModel.replacement
                                )).textSelection(.enabled)
                            } else {
                                Text(raw)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                        .background(isHitLine ? Color.yellow.opacity(0.10) : Color.clear)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack { Spacer(); Text("Select a hit to see context").foregroundStyle(.secondary); Spacer() }
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    @ObservedObject var viewModel: SearchReplaceViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.isWorking { ProgressView().scaleEffect(0.55).frame(width: 14, height: 14) }
            Text(viewModel.statusText).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            if !viewModel.fileMatches.isEmpty {
                let total = viewModel.fileMatches.reduce(0) { $0 + $1.hits.count }
                let accepted = viewModel.fileMatches.reduce(0) {
                    $0 + $1.hits.filter(\.accepted).count
                }
                Text("\(accepted)/\(total) selected · \(viewModel.fileMatches.count) files")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }
}
