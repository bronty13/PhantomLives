import SwiftUI
import PDFKit

/// Thin SwiftUI wrapper around `PDFView` for inline PDF previews. Lives in
/// its own file so the PDFKit import doesn't bleed into views that don't
/// need it.
struct PDFAttachmentView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor.windowBackgroundColor
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(data: data)
    }
}
