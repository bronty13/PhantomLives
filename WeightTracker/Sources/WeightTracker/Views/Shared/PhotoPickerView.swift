import SwiftUI
import AppKit

struct PhotoPickerView: View {
    @Binding var photoBlob: Data?
    @Binding var photoExt: String?
    @Binding var photoFilename: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = photoBlob, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 150)
                    .cornerRadius(8)
                    .overlay(
                        Button(action: clearPhoto) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.5).clipShape(Circle()))
                        }
                        .buttonStyle(.plain)
                        .padding(4),
                        alignment: .topTrailing
                    )
            } else {
                Button(action: pickPhoto) {
                    Label("Add Photo", systemImage: "camera")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                photoBlob = data
                photoExt = url.pathExtension.lowercased()
                photoFilename = url.lastPathComponent
            }
        }
    }

    private func clearPhoto() {
        photoBlob = nil
        photoExt = nil
        photoFilename = nil
    }
}
