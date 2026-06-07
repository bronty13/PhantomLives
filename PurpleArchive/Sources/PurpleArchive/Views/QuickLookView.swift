import SwiftUI
import Quartz

/// Inline Quick Look of a single file, wrapping AppKit's `QLPreviewView`. Used
/// to preview one entry of an open archive without leaving the app — the entry
/// is extracted to a temp file first (see `AppModel.quickLook`). `QLPreviewView`
/// renders the same rich previews Finder's spacebar Quick Look does (text,
/// images, PDFs, audio/video, code, …) with no responder-chain or preview-panel
/// data-source plumbing.
struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? NSURL) as URL? != url {
            nsView.previewItem = url as NSURL
        }
    }
}

/// The Quick Look sheet chrome: a title bar with the entry name plus Reveal /
/// Done actions, and the `QuickLookView` filling the rest.
struct QuickLookSheet: View {
    let item: AppModel.PreviewItem
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .foregroundStyle(.purple)
                Text(item.name)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .tint(.purple)
            }
            .padding(12)
            Divider()
            QuickLookView(url: item.url)
        }
        .frame(width: 720, height: 540)
    }
}
