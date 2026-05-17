import SwiftUI

struct TagsRatingView: View {
    @EnvironmentObject var appState: AppState
    @State private var newTag: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rating").font(.headline)
                Spacer()
                StarRatingControl(
                    stars: appState.rating?.stars ?? 0,
                    onChange: { appState.setRating(stars: $0) }
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tags").font(.headline)
                FlowLayoutTagsView(
                    tags: appState.tags.map { $0.name },
                    onRemove: { appState.removeTag(name: $0) }
                )
                HStack {
                    TextField("Add tag and press Return", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            let trimmed = newTag.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            appState.addTag(name: trimmed)
                            newTag = ""
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.headline)
                TextEditor(text: Binding(
                    get: { appState.rating?.description ?? "" },
                    set: { appState.setDescription($0) }
                ))
                .frame(minHeight: 60, maxHeight: 100)
                .font(.body)
            }
        }
        .padding(8)
    }
}

struct StarRatingControl: View {
    let stars: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= stars ? "star.fill" : "star")
                    .foregroundStyle(i <= stars ? Color.yellow : Color.secondary)
                    .onTapGesture {
                        // Tapping a filled star at its own position clears
                        // it; otherwise sets to that rank.
                        onChange(i == stars ? 0 : i)
                    }
            }
        }
    }
}

struct FlowLayoutTagsView: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        if tags.isEmpty {
            Text("No tags.").foregroundStyle(.secondary).font(.caption)
        } else {
            // Simple wrapping HStack. For large tag counts a custom
            // Layout would be better, but for typical media-log usage
            // this is fine.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { name in
                        HStack(spacing: 4) {
                            Text(name).font(.caption)
                            Button { onRemove(name) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .imageScale(.small)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15),
                                     in: Capsule())
                    }
                }
            }
        }
    }
}
