import SwiftUI
import ArchiveKit

/// Browse an opened archive's contents in a table, with an Extract action.
/// Encryption prompts for a password before extracting.
struct ArchiveBrowserView: View {
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    @State private var remember = false
    @State private var showingPasswordSheet = false

    var body: some View {
        if model.openedURL == nil {
            emptyState
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                Table(model.entries) {
                    TableColumn("Name") { entry in
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: entry))
                                .foregroundStyle(entry.isDirectory ? Color.secondary : Color.blue)
                            Text(entry.displayPath).lineLimit(1).truncationMode(.middle)
                            if entry.isEncrypted { Image(systemName: "lock.fill").foregroundStyle(.orange) }
                        }
                    }
                    TableColumn("Size") { entry in
                        Text(entry.isDirectory ? "—" : ByteFormat.string(entry.uncompressedSize))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }.width(90)
                    TableColumn("Modified") { entry in
                        Text(entry.modified.map { Self.dateFormatter.string(from: $0) } ?? "—")
                            .foregroundStyle(.secondary).font(.caption)
                    }.width(150)
                }
            }
            .sheet(isPresented: $showingPasswordSheet) { passwordSheet }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.openedURL?.lastPathComponent ?? "")
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                if let info = model.info {
                    Text("\(info.fileCount) files · \(ByteFormat.string(info.totalUncompressedSize))"
                         + (info.isEncrypted ? " · 🔒 encrypted" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                ForEach(model.availableEncodings) { enc in
                    Button {
                        model.selectedEncoding = enc
                    } label: {
                        if enc == model.selectedEncoding { Label(enc.label, systemImage: "checkmark") }
                        else { Text(enc.label) }
                    }
                }
            } label: {
                Label(model.selectedEncoding.label, systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 200)
            .help("Filename text encoding — fix mojibake from Windows/Linux archives")

            Button {
                if model.isEncrypted {
                    if model.vaultPassword != nil { model.extractOpened() }  // auto-fill from Keychain
                    else { showingPasswordSheet = true }
                } else { model.extractOpened() }
            } label: {
                Label("Extract", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent).tint(.purple)
            .disabled(model.busy)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 54)).foregroundStyle(.purple.opacity(0.5))
            Text("Drop an archive here").font(.title3)
            Text("ZIP · 7z · RAR · TAR · gz · bz2 · xz · zst · cab · iso · StuffIt · BinHex · and more")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Archive…") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url { model.open(url) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This archive is encrypted").font(.headline)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder).frame(width: 260)
            Toggle("Remember in Keychain", isOn: $remember)
            HStack {
                Spacer()
                Button("Cancel") { showingPasswordSheet = false }
                Button("Extract") {
                    showingPasswordSheet = false
                    model.extractOpened(password: password, remember: remember)
                    password = ""
                }.keyboardShortcut(.defaultAction).tint(.purple)
            }
        }
        .padding(20)
    }

    private func icon(for entry: ArchiveEntry) -> String {
        if entry.isDirectory { return "folder.fill" }
        if entry.isSymlink { return "arrow.up.forward.app" }
        return "doc"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()
}
