import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(.purple)
                Text("Purple Archive").font(.headline)
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 10)

            ForEach(SidebarItem.allCases) { item in
                Button {
                    model.sidebarSelection = item
                } label: {
                    Label(item.rawValue, systemImage: item.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(model.sidebarSelection == item
                                    ? Color.purple.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            if let url = model.openedURL, model.sidebarSelection == .browse {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open").font(.caption2).foregroundStyle(.tertiary)
                    Text(url.lastPathComponent)
                        .font(.caption).lineLimit(2).truncationMode(.middle)
                }
                .padding(12)
            }
        }
    }
}
