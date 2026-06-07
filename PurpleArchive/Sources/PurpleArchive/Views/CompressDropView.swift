import SwiftUI
import UniformTypeIdentifiers
import ArchiveKit

/// Drag files/folders here (or pick them) to create an archive in the chosen
/// format. The format/level come from Settings defaults and can be tweaked here.
struct CompressDropView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: SettingsStore
    @State private var staged: [URL] = []
    @State private var password = ""
    @State private var windowsSafe = false
    @State private var recommendation: String?

    var body: some View {
        VStack(spacing: 0) {
            controls
            recommendationBanner
            Divider()
            dropZone
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Format", selection: Binding(
                get: { settings.defaultFormat },
                set: { settings.settings.defaultFormatRaw = $0.rawValue })) {
                ForEach(ArchiveFormat.allCases.filter { $0.canCreate }, id: \.self) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .frame(width: 200)

            if settings.defaultFormat.supportsEncryption {
                SecureField("Password (optional)", text: $password)
                    .textFieldStyle(.roundedBorder).frame(width: 160)
            }

            Toggle("Windows-safe", isOn: $windowsSafe)
                .help("Sanitize filenames so the archive extracts cleanly on Windows")

            Button {
                let rec = FormatRecommender.recommend(
                    inputs: staged,
                    constraints: .init(needsWindowsCompatibility: windowsSafe,
                                       needsEncryption: !password.isEmpty))
                settings.settings.defaultFormatRaw = rec.format.rawValue
                recommendation = rec.rationale
            } label: { Label("Recommend", systemImage: "wand.and.stars") }
            .disabled(staged.isEmpty)
            .help("Pick the best format for these files")

            Spacer()

            Button {
                compress()
            } label: {
                Label("Create Archive", systemImage: "plus.rectangle.on.folder.fill")
            }
            .buttonStyle(.borderedProminent).tint(.purple)
            .disabled(staged.isEmpty || model.busy)
        }
        .padding(12)
    }

    @ViewBuilder private var recommendationBanner: some View {
        if let rec = recommendation {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").foregroundStyle(.purple)
                Text(rec).font(.caption)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.purple.opacity(0.08))
        }
    }

    private var dropZone: some View {
        ZStack {
            if staged.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(.system(size: 48)).foregroundStyle(.purple.opacity(0.5))
                    Text("Drop files & folders to compress").font(.title3)
                    Button("Choose Files…") { pick() }
                }
            } else {
                List {
                    ForEach(staged, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc")
                            Text(url.lastPathComponent)
                            Spacer()
                            Button { staged.removeAll { $0 == url } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(staged.isEmpty ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let group = DispatchGroup(); var urls: [URL] = []
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { urls.append(u) }; group.leave() }
            }
            group.notify(queue: .main) { staged.append(contentsOf: urls) }
            return true
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { staged.append(contentsOf: panel.urls) }
    }

    private func compress() {
        let inputs = staged
        if !password.isEmpty, settings.defaultFormat.supportsEncryption {
            model.compressEncrypted(inputs, password: password, windowsSafe: windowsSafe)
        } else {
            model.compress(inputs, windowsSafe: windowsSafe)
        }
        staged.removeAll(); password = ""; recommendation = nil
    }
}
