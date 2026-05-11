import SwiftUI

/// 2×10 scrollable grid of all 20 suspects. Tapping a card opens a popover
/// with two interrogation actions (`WHERE?` and `FINGERPRINT?`). The popover
/// routes through `AppState`, which is what fires the engine and the LED.
struct SuspectRolodexView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedId: Int?

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ROLODEX")
                    .font(.caption).bold()
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if appState.session == nil {
                    Text("press ON to start")
                        .font(.caption2).italic()
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(SuspectRoster.all) { suspect in
                        Button {
                            if appState.session != nil { selectedId = suspect.id }
                        } label: {
                            SuspectCardView(
                                suspect: suspect,
                                knownLocation: knownLocation(for: suspect.id),
                                highlighted: selectedId == suspect.id
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: Binding(
                            get: { selectedId == suspect.id },
                            set: { if !$0 { selectedId = nil } }
                        )) {
                            interrogationActions(for: suspect)
                                .padding(14)
                                .frame(minWidth: 220)
                        }
                    }
                }
            }
        }
    }

    private func knownLocation(for id: Int) -> Location? {
        guard let s = appState.session,
              let p = s.players.first(where: { $0.seat == s.currentSeat })
        else { return nil }
        return p.notepad.locationsBySuspect[id]
    }

    @ViewBuilder
    private func interrogationActions(for suspect: Suspect) -> some View {
        let session = appState.session
        let pqLeft = (session?.difficulty.privateQuestionsPerTurn ?? 0)
                   - (session?.privateQuestionsAskedThisTurn      ?? 0)
        VStack(alignment: .leading, spacing: 10) {
            Text("#\(suspect.id) — \(suspect.name)")
                .font(.headline)
            Divider()
            Button {
                appState.askWhereWereYou(suspectId: suspect.id)
                selectedId = nil
            } label: {
                Label("Where were you?", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)

            Button {
                appState.askFingerprint(suspectId: suspect.id)
                selectedId = nil
            } label: {
                Label("Fingerprint parity? (PQ \(pqLeft) left)", systemImage: "fingerprint")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(pqLeft <= 0)
        }
    }
}
