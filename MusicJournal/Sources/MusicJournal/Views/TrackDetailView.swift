// TrackDetailView.swift
// Right-hand panel shown when a track is selected in the track table.
// Displays album art, track metadata, a 1–5 star rating picker, and a
// notes text editor. Changes are saved to the local DB on tap of "Save Notes";
// onSave callback notifies the parent to reload the track list so the note
// indicator (green note icon) updates immediately.

import SwiftUI

/// Detail panel for a selected track — album art, metadata, star rating, and
/// rich-text journaling fields (notes, lyrics, lyric summary, song year).
struct TrackDetailView: View {
    let track: Track
    /// Called after a save so the parent can refresh its track list.
    let onSave: (Track) -> Void

    @State private var notes: String = ""
    @State private var personalNotes: String = ""
    @State private var rating: Int = 0
    @State private var songYearText: String = ""
    @State private var lyrics: String = ""
    @State private var lyricSummary: String = ""
    /// True when any field differs from the saved values.
    @State private var isDirty = false

    // LLM clipboard round-trip state.
    @State private var llmError: String?
    @State private var llmStatus: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                albumArt
                trackInfo
                metadataBadges

                Divider()

                ratingSection
                songYearSection

                Divider()

                llmSection

                Divider()

                lyricSummarySection
                lyricsSection
                songNotesSection
                personalNotesSection

                if isDirty {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                        .frame(maxWidth: .infinity)
                }

                Link("Open in Spotify", destination: URL(string: track.spotifyURL)!)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
        .onAppear { resetFields() }
        // Reset fields when the user selects a different track — always,
        // even if there are unsaved edits (matches existing UX).
        .onChange(of: track.spotifyId) { resetFields() }
        // Reset when the *same* track's user-owned fields change externally
        // (e.g. a sync backfilled songYear, or another panel saved). Skip
        // when the user has unsaved edits so we don't clobber them.
        .onChange(of: trackUserFieldsKey) { _, _ in
            if !isDirty { resetFields() }
        }
        .alert("LLM Response", isPresented: .constant(llmError != nil)) {
            Button("OK") { llmError = nil }
        } message: {
            Text(llmError ?? "")
        }
    }

    // MARK: - Sections

    private var albumArt: some View {
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
    }

    private var trackInfo: some View {
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
    }

    private var metadataBadges: some View {
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
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My Rating").font(.headline)
            StarRatingView(rating: $rating, onChange: { isDirty = true })
        }
    }

    private var songYearSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song Year").font(.headline)
            TextField("e.g. 1985", text: $songYearText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
                .onChange(of: songYearText) { isDirty = true }
        }
    }

    private var lyricSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lyric Summary").font(.headline)
            MarkdownEditor(text: $lyricSummary, minHeight: 100)
                .onChange(of: lyricSummary) { isDirty = true }
        }
    }

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lyrics").font(.headline)
            MarkdownEditor(text: $lyrics, minHeight: 200)
                .onChange(of: lyrics) { isDirty = true }
        }
    }

    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LLM Round-Trip").font(.headline)
            HStack(spacing: 8) {
                Button {
                    copyPromptToClipboard()
                } label: {
                    Label("Copy Prompt", systemImage: "doc.on.clipboard")
                }
                .help("Copy a prompt for this track to the clipboard. Paste into Claude / ChatGPT / Gemini, then come back and click Apply Response.")

                Button {
                    applyResponseFromClipboard()
                } label: {
                    Label("Apply Response", systemImage: "arrow.down.doc")
                }
                .help("Read the LLM's JSON response from the clipboard and apply it to the fields below. Edit the prompt template in Settings → LLM Prompt.")
            }
            .controlSize(.small)
            if let status = llmStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func copyPromptToClipboard() {
        let prompt = LLMPromptService.render(for: track)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        llmStatus = "Prompt copied. Paste into your LLM, then click Apply Response."
    }

    private func applyResponseFromClipboard() {
        let pb = NSPasteboard.general
        guard let raw = pb.string(forType: .string), !raw.isEmpty else {
            llmError = LLMPromptService.ParseError.empty.localizedDescription
            return
        }
        do {
            let resp = try LLMPromptService.parseResponse(raw)
            var applied: [String] = []
            if let y = resp.songYear {
                songYearText = String(y)
                applied.append("Year")
            }
            if let s = resp.lyricSummary, !s.isEmpty {
                lyricSummary = s
                applied.append("Lyric Summary")
            }
            if let l = resp.lyrics, !l.isEmpty {
                lyrics = l
                applied.append("Lyrics")
            }
            if let n = resp.notes, !n.isEmpty {
                notes = n
                applied.append("Notes")
            }
            if applied.isEmpty {
                llmStatus = "Response parsed but contained no values to apply."
            } else {
                isDirty = true
                llmStatus = "Applied: \(applied.joined(separator: ", ")). Click Save to persist."
            }
        } catch {
            llmError = error.localizedDescription
        }
    }

    private var songNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Song Notes").font(.headline)
                Text("(facts, context — LLM may write here)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            MarkdownEditor(text: $notes, minHeight: 120)
                .onChange(of: notes) { isDirty = true }
        }
    }

    private var personalNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Personal Notes").font(.headline)
                Text("(your private commentary — never touched by the LLM)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            MarkdownEditor(text: $personalNotes, minHeight: 140)
                .onChange(of: personalNotes) { isDirty = true }
        }
    }

    /// Combined hash of the user-owned fields on the bound track. Drives
    /// `.onChange` so the panel picks up server-side updates (e.g. a sync
    /// that backfilled `songYear`) without forcing a re-selection.
    private var trackUserFieldsKey: Int {
        var h = Hasher()
        h.combine(track.songYear)
        h.combine(track.userRating)
        h.combine(track.userNotes)
        h.combine(track.personalNotes)
        h.combine(track.lyrics)
        h.combine(track.lyricSummary)
        return h.finalize()
    }

    // MARK: - State helpers

    private func resetFields() {
        notes = track.userNotes
        personalNotes = track.personalNotes
        rating = track.userRating ?? 0
        songYearText = track.songYear.map(String.init) ?? ""
        lyrics = track.lyrics
        lyricSummary = track.lyricSummary
        isDirty = false
        llmStatus = nil
        llmError = nil
    }

    private func save() {
        let r = rating == 0 ? nil : rating
        let year = Int(songYearText.trimmingCharacters(in: .whitespaces))
        try? DatabaseService.shared.updateTrackUserFields(
            spotifyId: track.spotifyId,
            notes: notes,
            personalNotes: personalNotes,
            rating: r,
            songYear: year,
            lyrics: lyrics,
            lyricSummary: lyricSummary
        )
        var updated = track
        updated.userNotes = notes
        updated.personalNotes = personalNotes
        updated.userRating = r
        updated.songYear = year
        updated.lyrics = lyrics
        updated.lyricSummary = lyricSummary
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
