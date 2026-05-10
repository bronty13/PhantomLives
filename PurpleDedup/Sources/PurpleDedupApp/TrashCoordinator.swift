import Foundation
import PurpleDedupCore

/// Async orchestration of the trash flow, lifted out of `ContentView`.
/// Splits an incoming file set into regular files (move via Finder Trash
/// or a configured stage folder) and Photos library files (queue in the
/// "Marked for Deletion in PurpleDedup" album for the user to finalise
/// inside Photos.app).
///
/// Returns a typed `Outcome` carrying everything the GUI projects onto
/// `@State`: which files actually moved, the PhotoKit summary, any
/// failures, and pre-formatted status text. Cluster cleanup + decision
/// pruning live in ContentView because they touch SwiftUI state — this
/// coordinator stays SwiftUI-free.
struct TrashCoordinator {

    let stageFolderPath: String

    struct Outcome {
        let trashed: [TrashedFile]
        let photoKitSummary: String
        let failures: [String]
        let statusMessage: String
        /// Set of regular-file paths that successfully moved. Used by the
        /// caller to drop them from the in-memory cluster lists.
        let trashedPaths: Set<String>
        /// True when at least one Photos library file was queued in the
        /// PhotoKit album. Drives the "Open Photos.app to finalise"
        /// reminder appended to the status message.
        let didQueuePhotosFiles: Bool
    }

    func run(_ toDelete: [DiscoveredFile]) async -> Outcome {
        // Split into regular files (Trash via FileManager) and Photos
        // library files (queue in PhotoKit album). Photos files inside
        // `.photoslibrary/` can't go to Trash directly without leaving
        // Photos.app's database broken — they round-trip through the
        // "Marked for Deletion in PurpleDedup" album.
        let regularFiles = toDelete.filter { !$0.url.path.contains(".photoslibrary/") }
        let photosFiles  = toDelete.filter {  $0.url.path.contains(".photoslibrary/") }

        let database = (try? Database.openDefault())
        let manager = TrashManager(database: database)
        var trashed: [TrashedFile] = []
        var failures: [String] = []

        // FR-5.5: route to a user-chosen stage folder when configured,
        // otherwise the Finder Trash. TrashManager records both
        // destinations in the operation log so Cmd+Z can restore from
        // either kind.
        let destination: TrashManager.Destination =
            stageFolderPath.isEmpty
            ? .trash
            : .folder(URL(fileURLWithPath: stageFolderPath))

        for f in regularFiles {
            do {
                if let resultURL = try manager.move(f, to: destination) {
                    trashed.append(TrashedFile(
                        originalPath: f.url.path,
                        trashURL: resultURL,
                        sizeBytes: f.sizeBytes
                    ))
                }
            } catch {
                failures.append("\(f.url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Photos library round-trip. The service builds (or reuses) the
        // album, looks up each path's PHAsset by basename, and bulk-adds
        // them via PHAssetCollectionChangeRequest. The user opens
        // Photos.app afterwards to finalise.
        var photoKitSummary = ""
        if !photosFiles.isEmpty {
            let result = await PhotoKitDeletionService.shared.markForDeletion(
                paths: photosFiles.map(\.url)
            )
            photoKitSummary = result.summary
        }

        let trashedPaths = Set(trashed.map(\.originalPath))
        let didQueuePhotos = !photosFiles.isEmpty
        let statusMessage = Self.formatMessage(
            trashed: trashed,
            stageFolderPath: stageFolderPath,
            photoKitSummary: photoKitSummary,
            failures: failures,
            didQueuePhotos: didQueuePhotos
        )

        return Outcome(
            trashed: trashed,
            photoKitSummary: photoKitSummary,
            failures: failures,
            statusMessage: statusMessage,
            trashedPaths: trashedPaths,
            didQueuePhotosFiles: didQueuePhotos
        )
    }

    private static func formatMessage(
        trashed: [TrashedFile],
        stageFolderPath: String,
        photoKitSummary: String,
        failures: [String],
        didQueuePhotos: Bool
    ) -> String {
        var msg: [String] = []
        if !trashed.isEmpty {
            let dest = stageFolderPath.isEmpty
                ? "Trash"
                : "stage folder (\(URL(fileURLWithPath: stageFolderPath).lastPathComponent))"
            msg.append("Moved \(trashed.count) file(s) to \(dest)")
        }
        if !photoKitSummary.isEmpty {
            msg.append(photoKitSummary)
        }
        if !failures.isEmpty {
            msg.append("\(failures.count) failed")
        }
        let body = msg.joined(separator: " · ")
        if trashed.isEmpty && didQueuePhotos {
            return body + ". Open Photos.app to finalise."
        }
        return body + (trashed.isEmpty ? "." : ". Cmd+Z to undo the Trash batch.")
    }
}
