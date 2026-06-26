import SwiftUI

/// Adaptive thumbnail grid of the currently visible media files.
struct MediaGridView: View {
    let files: [MediaFile]
    @EnvironmentObject private var appState: AppState

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(files) { file in
                    MediaThumbnailCell(
                        file: file,
                        isSelected: appState.selectedFileId == file.id,
                        duplicateCount: appState.duplicateCount(for: file.id),
                        keywordNames: appState.keywordNames(for: file.id),
                        onTap: { appState.selectFile(file.id) }
                    )
                }
            }
            .padding(20)
        }
    }
}
