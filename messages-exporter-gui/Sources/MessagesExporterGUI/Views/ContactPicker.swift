import SwiftUI

/// Text field that consults ContactsService for fuzzy AddressBook matches
/// while the user types and surfaces them in a popover. The selected
/// name is what gets passed to the CLI's substring matcher — the popover
/// is purely a UX nicety and the user is free to type anything.
///
/// Queries are debounced (200 ms) and dispatched as cancellable Tasks
/// against the async `ContactsService.suggestions(for:)`. Avoids the
/// per-keystroke main-thread stall that the previous synchronous query
/// caused on large AddressBooks.
struct ContactPicker: View {
    @Binding var contact: String
    @EnvironmentObject private var contacts: ContactsService

    @State private var suggestions: [String] = []
    @State private var showSuggestions = false
    @State private var refreshTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Contact name", text: $contact)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onChange(of: contact) { _, new in
                    scheduleRefresh(prefix: new)
                }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused { showSuggestions = false }
                }
                .popover(isPresented: $showSuggestions, arrowEdge: .bottom) {
                    suggestionList
                }

            if contacts.permissionDenied {
                Text("Contacts permission denied — type a name; the CLI matches against AddressBook directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.self) { name in
                Button {
                    contact = name
                    showSuggestions = false
                } label: {
                    HStack {
                        Text(name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 220)
        .padding(.vertical, 4)
    }

    private func scheduleRefresh(prefix: String) {
        refreshTask?.cancel()
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else {
            suggestions = []
            showSuggestions = false
            return
        }
        refreshTask = Task {
            // Debounce: drop intermediate keystrokes within 200 ms.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let matches = await contacts.suggestions(for: trimmed)
            guard !Task.isCancelled else { return }
            // Suppress popover when the only suggestion is exactly what
            // they've already typed.
            let filtered = matches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
            suggestions = filtered
            showSuggestions = !filtered.isEmpty && fieldFocused
        }
    }
}
