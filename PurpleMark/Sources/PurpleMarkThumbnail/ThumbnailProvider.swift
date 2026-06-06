import QuickLookThumbnailing
import PurpleMarkRenderCore

/// Finder/Quick Look thumbnail for `.md` files — draws a small page-preview of
/// the document (purple accent + the first lines) so markdown files get a
/// recognizable, content-aware icon instead of a generic one.
class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                  _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        // Read a bounded prefix — thumbnails only need the first lines.
        let markdown: String
        if let data = try? Data(contentsOf: request.fileURL),
           let s = String(data: data.prefix(8 * 1024), encoding: .utf8) {
            markdown = s
        } else {
            markdown = ""
        }

        // Fit a portrait "paper" rectangle inside the requested maximum size.
        let maxSize = request.maximumSize
        let ratio: CGFloat = 8.5 / 11.0
        var w = maxSize.height * ratio
        var h = maxSize.height
        if w > maxSize.width { w = maxSize.width; h = w / ratio }
        let size = CGSize(width: max(1, w), height: max(1, h))

        let reply = QLThumbnailReply(contextSize: size) { () -> Bool in
            MarkdownThumbnail.draw(markdown: markdown, size: size)
            return true
        }
        handler(reply, nil)
    }
}
