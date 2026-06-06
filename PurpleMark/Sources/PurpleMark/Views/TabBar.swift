import SwiftUI

/// The document tab strip, shown when more than one document is open.
struct TabBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.documents) { doc in
                    TabItem(doc: doc, isActive: doc.id == state.activeID)
                    Divider().frame(height: 18)
                }
                Button { state.newDocument() } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Tab (⌘T)")
                Spacer(minLength: 0)
            }
        }
        .frame(height: 30)
        .background(.bar)
    }
}

private struct TabItem: View {
    @ObservedObject var doc: Document
    let isActive: Bool
    @EnvironmentObject var state: AppState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button { state.activate(doc) } label: {
                Text(doc.title)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .buttonStyle(.plain)

            // Close button (or a dirty dot when idle and unsaved).
            ZStack {
                if hovering || isActive {
                    Button { state.closeDocument(doc) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab (⌘W)")
                } else if doc.isDirty {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                }
            }
            .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(isActive ? Color.accentColor.opacity(0.18) : .clear)
        .onHover { hovering = $0 }
    }
}
