import SwiftUI
import ArchiveKit

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var queue: JobQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
                Text("Purple Archive").font(.headline)
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 12)

            ForEach(SidebarItem.allCases) { item in
                Button {
                    model.sidebarSelection = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.systemImage)
                            .frame(width: 18)
                            .foregroundStyle(model.sidebarSelection == item ? .purple : .secondary)
                        Text(item.rawValue)
                        Spacer()
                        if item == .queue, queue.activeCount > 0 {
                            Text("\(queue.activeCount)")
                                .font(.caption2).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.purple, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(model.sidebarSelection == item
                                ? Color.purple.opacity(0.16) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            if let url = model.openedURL, model.sidebarSelection == .browse {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OPEN").font(.caption2).foregroundStyle(.tertiary)
                    Text(url.lastPathComponent)
                        .font(.caption).lineLimit(2).truncationMode(.middle)
                }
                .padding(.horizontal, 14).padding(.top, 14)
            }

            Spacer()

            // Engine version footer.
            Text("libarchive \(ArchiveKitVersions.libarchive) · zstd \(ArchiveKitVersions.zstd)")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }
}
