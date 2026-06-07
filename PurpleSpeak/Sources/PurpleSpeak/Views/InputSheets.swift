import SwiftUI

/// "New from Pasted Text" entry.
struct PasteTextSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New from Pasted Text").font(.headline)
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $body_)
                .font(.system(size: 14))
                .frame(minWidth: 460, minHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add & Read") {
                    appState.importPastedText(title: title, text: body_)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}

/// "Read Web Article" entry.
struct WebArticleSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Read a Web Article").font(.headline)
            Text("Paste a link — PurpleSpeak pulls the article text out of the page and reads it aloud.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://example.com/article", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 460)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Fetch & Read") {
                    appState.importWebArticle(urlString)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}
