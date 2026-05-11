import SwiftUI
import PDFKit

/// Paginated viewer over scanned rules pages. Pulls from
/// `AssetResolver.manualPageURLs()` — drop `page_01.png` …`page_NN.png`
/// (or one `manual.pdf`) into `~/Documents/ElectronicDetective Assets/manual/`
/// and the booklet picks them up the next time it opens.
struct RulesBookletView: View {
    @EnvironmentObject var assets: AssetResolver
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex: Int = 0

    private var urls: [URL] { assets.manualPageURLs() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if urls.isEmpty {
                emptyState
            } else {
                pageContent
                Divider()
                pageControls
            }
        }
        .frame(minWidth: 720, minHeight: 600)
    }

    private var header: some View {
        HStack {
            Text("Rules Booklet").font(.title3).bold()
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text("No manual pages found")
                .font(.headline)
            Text("Drop your scanned rules pages into:")
                .foregroundStyle(.secondary)
            Text(assets.manualDir.path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.15)))
            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([assets.manualDir])
                }
                Button("Refresh") { assets.refresh() }
            }
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pageContent: some View {
        let url = urls[min(pageIndex, urls.count - 1)]
        Group {
            if url.pathExtension.lowercased() == "pdf" {
                PDFPageView(url: url)
            } else if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                Text("Couldn't load \(url.lastPathComponent)")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageControls: some View {
        HStack {
            Button(action: { pageIndex = max(0, pageIndex - 1) }) {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(pageIndex == 0)

            Spacer()
            Text("Page \(pageIndex + 1) of \(urls.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()

            Button(action: { pageIndex = min(urls.count - 1, pageIndex + 1) }) {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(pageIndex >= urls.count - 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

/// Embeds a single-page PDF in the booklet view. PDFKit handles its own
/// scrolling/zoom; we only host one page at a time so the booklet feels like
/// flipping a physical manual.
private struct PDFPageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePage
        v.displaysPageBreaks = false
        v.document = PDFDocument(url: url)
        return v
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
