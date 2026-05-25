import SwiftUI
import MasterClipperCore

struct ClipExportSheet: View {
    @EnvironmentObject private var appState: AppState
    let clip: Clip
    let onClose: () -> Void

    enum Mode: String, CaseIterable {
        case plainText, markdown, pdf
        var label: String {
            switch self {
            case .plainText: return "Plain text (iMessage)"
            case .markdown:  return "Markdown"
            case .pdf:       return "PDF"
            }
        }
    }

    enum PlainTextVariant: String, CaseIterable {
        case informationNeeded, verification
        var label: String {
            switch self {
            case .informationNeeded: return "Information Needed"
            case .verification:      return "Verification"
            }
        }
    }

    @State private var mode: Mode = .plainText
    @State private var plainVariant: PlainTextVariant = .informationNeeded
    @State private var copyConfirmed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export clip — \(clip.id)")
                .font(.title3.weight(.semibold))

            Picker("Format", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if mode == .plainText {
                Picker("Mode", selection: $plainVariant) {
                    ForEach(PlainTextVariant.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if mode != .pdf {
                ScrollView {
                    Text(currentText)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 200)
                .background(.background.secondary)
                .border(.separator)
            } else {
                Text("PDF will be saved to disk via the Save panel.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            HStack {
                if mode != .pdf {
                    Button {
                        copyToPasteboard()
                    } label: {
                        Label(copyConfirmed ? "Copied!" : "Copy", systemImage: "doc.on.clipboard")
                    }
                }
                Button {
                    saveToFile()
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }

    private var currentText: String {
        switch mode {
        case .plainText:
            switch plainVariant {
            case .informationNeeded: return ExportService.plainTextInformationNeeded(clip, appState: appState)
            case .verification:      return ExportService.plainTextVerification(clip, appState: appState)
            }
        case .markdown:  return ExportService.exportClipMarkdown(clip, appState: appState)
        case .pdf:       return ""
        }
    }

    private func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentText, forType: .string)
        copyConfirmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyConfirmed = false }
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        try? FileManager.default.createDirectory(
            at: appState.settingsStore.resolvedExportDirectory,
            withIntermediateDirectories: true
        )

        let safeId = clip.id
        switch mode {
        case .plainText:
            panel.nameFieldStringValue = "MasterClipper-\(safeId).txt"
            if panel.runModal() == .OK, let url = panel.url {
                try? currentText.data(using: .utf8)?.write(to: url)
            }
        case .markdown:
            panel.nameFieldStringValue = "MasterClipper-\(safeId).md"
            if panel.runModal() == .OK, let url = panel.url {
                try? currentText.data(using: .utf8)?.write(to: url)
            }
        case .pdf:
            panel.nameFieldStringValue = "MasterClipper-\(safeId).pdf"
            if panel.runModal() == .OK, let url = panel.url {
                let data = ExportService.exportClipPDF(clip, appState: appState)
                try? data.write(to: url)
            }
        }
    }
}
