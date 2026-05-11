import SwiftUI

/// Full editable Case Fact Sheet for the current player. Mirrors the four
/// sections of the printed pad. In `.auto` transcription mode some fields
/// are filled by the engine (locations, fingerprint parity); the rest are
/// the player's deductions to record by hand.
struct CaseFactSheetView: View {
    @EnvironmentObject var appState: AppState

    private var session: GameSession? { appState.session }
    private var currentSeat: Int? { session?.currentSeat }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let _ = session, currentSeat != nil {
                    murderFactsSection
                    whoWasWhereSection
                    whoSaidWhatSection
                    whoDidItSection
                } else {
                    Text("Press ON on the console to begin a case.")
                        .italic()
                        .foregroundStyle(.black.opacity(0.5))
                }
            }
            .padding(16)
        }
        .background(notepadBackground)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DETECTIVE'S CASE FACT SHEET")
                .font(.system(size: 13, weight: .heavy, design: .serif))
                .foregroundStyle(.black)
            if let p = currentPlayer {
                Text(p.name + (p.eliminated ? " (eliminated)" : ""))
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(.black.opacity(0.7))
            }
        }
    }

    private var murderFactsSection: some View {
        sectionFrame("THE MURDER FACTS") {
            sexRow
            caliberRow
            parityRow
            locationRow
        }
    }

    private var whoWasWhereSection: some View {
        sectionFrame("WHO WAS WHERE?") {
            VStack(spacing: 4) {
                ForEach(SuspectRoster.all) { s in
                    suspectLocationRow(s)
                }
            }
        }
    }

    private var whoSaidWhatSection: some View {
        sectionFrame("WHO SAID WHAT?") {
            VStack(spacing: 6) {
                ForEach(SuspectRoster.all) { s in
                    suspectNoteRow(s)
                }
            }
        }
    }

    private var whoDidItSection: some View {
        sectionFrame("WHO DID IT?") {
            HStack {
                Text("My accusation:")
                    .foregroundStyle(.black.opacity(0.75))
                Picker("", selection: notepadBinding(\.prospectiveAccusationId)) {
                    Text("—").tag(Int?.none)
                    ForEach(SuspectRoster.all) { s in
                        Text("#\(s.id) — \(s.name)").tag(Optional(s.id))
                    }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Murder-facts rows

    private var sexRow: some View {
        HStack {
            Text("Sex").frame(width: 90, alignment: .leading)
            Picker("", selection: notepadBinding(\.murdererSex)) {
                Text("—").tag(Sex?.none)
                ForEach(Sex.allCases, id: \.self) { s in
                    Text(s.rawValue.capitalized).tag(Optional(s))
                }
            }
            .labelsHidden()
        }
    }

    private var caliberRow: some View {
        HStack {
            Text("Caliber").frame(width: 90, alignment: .leading)
            Picker("", selection: notepadBinding(\.weaponCaliber)) {
                Text("—").tag(WeaponCaliber?.none)
                ForEach(WeaponCaliber.allCases, id: \.self) { c in
                    Text(c.displayName).tag(Optional(c))
                }
            }
            .labelsHidden()
        }
    }

    private var parityRow: some View {
        HStack {
            Text("Print parity").frame(width: 90, alignment: .leading)
            Picker("", selection: notepadBinding(\.fingerprintParity)) {
                Text("—").tag(IDParity?.none)
                ForEach([IDParity.odd, IDParity.even], id: \.self) { p in
                    Text(p.rawValue.uppercased()).tag(Optional(p))
                }
            }
            .labelsHidden()
        }
    }

    private var locationRow: some View {
        HStack {
            Text("Murder loc.").frame(width: 90, alignment: .leading)
            Picker("", selection: notepadBinding(\.murderLocation)) {
                Text("—").tag(Location?.none)
                ForEach(Location.allCases, id: \.self) { loc in
                    Text(loc.displayName).tag(Optional(loc))
                }
            }
            .labelsHidden()
        }
    }

    // MARK: - Suspect rows

    private func suspectLocationRow(_ s: Suspect) -> some View {
        HStack(spacing: 8) {
            Text("#\(s.id) \(s.name)")
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            Picker("", selection: locationBinding(for: s.id)) {
                Text("—").tag(Location?.none)
                ForEach(Location.allCases, id: \.self) { loc in
                    Text(loc.code).tag(Optional(loc))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func suspectNoteRow(_ s: Suspect) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("#\(s.id)")
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 32, alignment: .leading)
            TextField("notes…", text: noteBinding(for: s.id), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .lineLimit(1...3)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.2)))
        }
    }

    // MARK: - Layout helpers

    private func sectionFrame<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .serif))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.bottom, 2)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(.black.opacity(0.4)), alignment: .bottom)
            content()
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.black.opacity(0.85))
        }
        .padding(.bottom, 4)
    }

    private var notepadBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.97, green: 0.94, blue: 0.86))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            // faint ruled lines
            GeometryReader { geo in
                VStack(spacing: 22) {
                    ForEach(0..<Int(geo.size.height / 22), id: \.self) { _ in
                        Rectangle().fill(Color.blue.opacity(0.08)).frame(height: 0.5)
                    }
                }
            }
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Player + binding plumbing

    private var currentPlayer: GameSession.Player? {
        guard let s = session, let seat = currentSeat else { return nil }
        return s.players.first { $0.seat == seat }
    }

    /// Binding to one field of the current player's notepad. Writes back
    /// through the session so SwiftUI sees the change.
    private func notepadBinding<V>(_ keyPath: WritableKeyPath<PlayerNotepad, V>) -> Binding<V> {
        Binding(
            get: { currentPlayer?.notepad[keyPath: keyPath] ?? defaultValue(for: keyPath) },
            set: { newValue in
                guard var s = appState.session,
                      let idx = s.players.firstIndex(where: { $0.seat == s.currentSeat })
                else { return }
                s.players[idx].notepad[keyPath: keyPath] = newValue
                appState.session = s
            }
        )
    }

    /// Defaults for optional-typed keypaths — Swift can't infer `Optional<X>.none`
    /// through a generic `V`, so we round-trip through `Any` and cast.
    private func defaultValue<V>(for keyPath: WritableKeyPath<PlayerNotepad, V>) -> V {
        return PlayerNotepad.empty[keyPath: keyPath]
    }

    private func locationBinding(for id: Int) -> Binding<Location?> {
        Binding(
            get: { currentPlayer?.notepad.locationsBySuspect[id] },
            set: { newValue in
                guard var s = appState.session,
                      let idx = s.players.firstIndex(where: { $0.seat == s.currentSeat })
                else { return }
                if let v = newValue { s.players[idx].notepad.locationsBySuspect[id] = v }
                else                 { s.players[idx].notepad.locationsBySuspect.removeValue(forKey: id) }
                appState.session = s
            }
        )
    }

    private func noteBinding(for id: Int) -> Binding<String> {
        Binding(
            get: { currentPlayer?.notepad.notes[id] ?? "" },
            set: { newValue in
                guard var s = appState.session,
                      let idx = s.players.firstIndex(where: { $0.seat == s.currentSeat })
                else { return }
                if newValue.isEmpty { s.players[idx].notepad.notes.removeValue(forKey: id) }
                else                 { s.players[idx].notepad.notes[id] = newValue }
                appState.session = s
            }
        )
    }
}
