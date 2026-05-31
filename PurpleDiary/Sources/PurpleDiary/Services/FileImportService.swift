import Foundation
import UniformTypeIdentifiers

/// Imports photos and videos chosen from the filesystem (via NSOpenPanel) into
/// the encrypted journal. Images are downscaled + re-encoded as JPEG like the
/// Photos path; videos are stored byte-for-byte as an encrypted BLOB with a
/// poster-frame thumbnail. Everything lands inside `diary.sqlite`, so it
/// inherits SQLCipher encryption at rest and rides along in the backup zip —
/// nothing is written to a plaintext sidecar and nothing is uploaded.
@MainActor
enum FileImportService {

    /// Content types the open panel offers — still images and movies.
    static let allowedContentTypes: [UTType] = [.image, .movie]

    enum MediaKind { case image, video, unsupported }

    /// Classify a file URL by its declared content type.
    static func classify(_ url: URL) -> MediaKind {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return .unsupported }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .image }
        return .unsupported
    }

    /// Build an `Attachment` (ready to insert) from a filesystem URL, or nil if
    /// the file isn't a supported image/video or can't be decoded. `entryId` is
    /// the owning entry. Reads bytes off the main actor where possible.
    static func makeAttachment(from url: URL, entryId: String) async -> Attachment? {
        switch classify(url) {
        case .image:  return makeImageAttachment(from: url, entryId: entryId)
        case .video:  return await makeVideoAttachment(from: url, entryId: entryId)
        case .unsupported: return nil
        }
    }

    // MARK: - Image

    private static func makeImageAttachment(from url: URL, entryId: String) -> Attachment? {
        guard let raw = try? Data(contentsOf: url),
              let encoded = ImageProcessing.downscaledJPEG(from: raw) else { return nil }
        let thumb = ImageProcessing.thumbnailJPEG(from: encoded.data)
        return Attachment(
            id: UUID().uuidString,
            entryId: entryId,
            kind: "photo",
            filename: url.lastPathComponent,
            mimeType: "image/jpeg",
            sizeBytes: Int64(encoded.data.count),
            width: encoded.width,
            height: encoded.height,
            data: encoded.data,
            thumbnailData: thumb,
            sourceAssetId: nil,
            createdAt: DatabaseService.isoNow()
        )
    }

    // MARK: - Video

    private static func makeVideoAttachment(from url: URL, entryId: String) async -> Attachment? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let poster = await VideoProcessing.poster(from: url)
        let mime = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.preferredMIMEType)
            ?? "video/quicktime"
        return Attachment(
            id: UUID().uuidString,
            entryId: entryId,
            kind: "video",
            filename: url.lastPathComponent,
            mimeType: mime,
            sizeBytes: Int64(raw.count),
            width: poster?.width ?? 0,
            height: poster?.height ?? 0,
            data: raw,
            thumbnailData: poster?.jpeg,
            sourceAssetId: nil,
            createdAt: DatabaseService.isoNow()
        )
    }
}
