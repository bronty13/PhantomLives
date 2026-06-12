import SwiftUI

/// Find & Replace bar shown above the source editor. Drives `FindController`,
/// which computes matches and posts select/replace commands to the editor.
struct FindReplaceBar: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var find: FindController
    @ObservedObject var doc: Document
    @FocusState private var focusedField: Field?

    private enum Field { case find, replace }

    var body: some View {
        VStack(spacing: 6) {
            findRow
            if find.showReplace { replaceRow }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear {
            find.showReplace = state.findShowReplace
            recompute()
            focusedField = .find
            if find.hasMatches { find.selectCurrent() }
        }
        .onChange(of: state.findShowReplace) { _, v in find.showReplace = v }
        .onChange(of: find.query) { _, _ in recompute(); if find.hasMatches { find.selectCurrent() } }
        .onChange(of: find.useRegex) { _, _ in recompute() }
        .onChange(of: find.caseSensitive) { _, _ in recompute() }
        // Debounced + background so typing in a huge document stays smooth;
        // comparing the version is O(1) where comparing the text was O(n).
        .onChange(of: doc.textVersion) { _, version in
            find.scheduleRecompute(
                debounce: LargeFilePolicy.features(forByteSize: doc.byteSize).findDebounce,
                version: version) { [weak doc] in doc?.text ?? "" }
        }
    }

    private var findRow: some View {
        HStack(spacing: 6) {
            Button { find.showReplace.toggle() } label: {
                Image(systemName: find.showReplace ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Toggle Replace")

            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find", text: $find.query)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .find)
                .frame(minWidth: 160)
                .onSubmit { find.next() }

            toggle("Aa", on: $find.caseSensitive, help: "Case sensitive")
            toggle(".*", on: $find.useRegex, help: "Regular expression")

            Text(matchLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)

            Button { find.previous() } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(!find.hasMatches).help("Previous (⇧⌘G)")
            Button { find.next() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(!find.hasMatches).help("Next (⌘G)")

            Spacer(minLength: 0)
            Button("Done") { state.findVisible = false }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 20)
            Image(systemName: "pencil").foregroundStyle(.secondary)
            TextField("Replace", text: $find.replacement)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .replace)
                .frame(minWidth: 160)
            Button("Replace") { recomputeIfStale(); find.replaceCurrent() }
                .disabled(!find.hasMatches)
            Button("Replace All") { recomputeIfStale(); find.replaceAll() }
                .disabled(!find.hasMatches)
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ label: String, on binding: Binding<Bool>, help: String) -> some View {
        Button { binding.wrappedValue.toggle() } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 18)
                .background(binding.wrappedValue ? Color.accentColor.opacity(0.25) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var matchLabel: String {
        guard !find.query.isEmpty else { return "" }
        guard find.hasMatches else { return "Not found" }
        let total = find.matchesCapped ? "\(find.matchCount)+" : "\(find.matchCount)"
        return "\(find.currentIndex + 1) of \(total)"
    }

    private func recompute() { find.recompute(in: doc.text, version: doc.textVersion) }

    /// A replacement must never run against ranges computed for older text —
    /// the debounce window makes that possible, so resync first.
    private func recomputeIfStale() {
        if find.matchesVersion != doc.textVersion { recompute() }
    }
}
