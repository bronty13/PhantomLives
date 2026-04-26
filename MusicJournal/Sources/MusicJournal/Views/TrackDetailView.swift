// TrackDetailView.swift
// Right-hand panel shown when a track is selected in the track table.
// Displays album art, track metadata, a 1–5 star rating picker, and a
// notes text editor. Changes are saved to the local DB on tap of "Save Notes";
// onSave callback notifies the parent to reload the track list so the note
// indicator (green note icon) updates immediately.

import SwiftUI

/// Detail panel for a selected track — album art, metadata, star rating, and notes.
struct TrackDetailView: View {
    let track: Track
    /// Called after a save so the parent can refresh its track list.
    let onSave: (Track) -> Void

    @State private var notes: String = ""
    @State private var rating: Int = 0
    /// True when notes or rating differ from the saved values.
    @State private var isDirty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Album art
                AsyncImage(url: URL(string: track.albumImageURL ?? "")) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 6)

                // Track info
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(track.artistNames)
                        .foregroundStyle(.secondary)
                    Text(track.albumName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Metadata badges
                HStack(spacing: 16) {
                    Label(track.durationFormatted, systemImage: "clock")
                    if track.isExplicit {
                        Text("E")
                            .font(.caption.bold())
                            .padding(.horizontal, 4)
                            .background(Color.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if let pop = track.popularity {
                        Label("\(pop)%", systemImage: "chart.bar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                // Star rating
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Rating")
                        .font(.headline)
                    StarRatingView(rating: $rating, onChange: { isDirty = true })
                }

                // Notes editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Notes")
                        .font(.headline)
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        .onChange(of: notes) { isDirty = true }
                }

                if isDirty {
                    Button("Save Notes") { save() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }

                Link("Open in Spotify", destination: URL(string: track.spotifyURL)!)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
        .onAppear {
            notes = track.userNotes
            rating = track.userRating ?? 0
        }
        // Reset fields when the user selects a different track.
        .onChange(of: track.spotifyId) {
            notes = track.userNotes
            rating = track.userRating ?? 0
            isDirty = false
        }
    }

    private func save() {
        let r = rating == 0 ? nil : rating
        try? DatabaseService.shared.updateTrackNotes(
            spotifyId: track.spotifyId,
            notes: notes,
            rating: r
        )
        var updated = track
        updated.userNotes = notes
        updated.userRating = r
        onSave(updated)
        isDirty = false
    }
}

// MARK: - StarRatingView

/// Tap-to-set star rating widget. Tapping the current star clears the rating.
struct StarRatingView: View {
    @Binding var rating: Int
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .yellow : .secondary)
                    .font(.title3)
                    .onTapGesture {
                        // Tapping the active star resets to 0 (unrated).
                        rating = rating == star ? 0 : star
                        onChange()
                    }
            }
        }
    }
}
