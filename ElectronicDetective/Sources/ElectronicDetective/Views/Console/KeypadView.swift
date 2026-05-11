import SwiftUI

/// 4-column keypad. Layout sketch (M1 minimum):
///
///   [1] [2] [3] [SUSPECT]
///   [4] [5] [6] [PRIVATE Q]
///   [7] [8] [9] [READOUT]
///   [CLR][0][ENT][END]
///   [ON]              [I ACCUSE]
///
/// Visual proportions land in M3.
struct KeypadView: View {
    let onKey: (ConsoleKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            row([digit(1), digit(2), digit(3), fn("SUSPECT",   .suspect, .blue)])
            row([digit(4), digit(5), digit(6), fn("PRIVATE Q", .privateQuestion, .blue)])
            row([digit(7), digit(8), digit(9), fn("READOUT",   .readout, .gray)])
            row([fn("CLR", .clear, .red), digit(0), fn("ENTER", .enter, .blue), fn("END", .endTurn, .gray)])
            HStack(spacing: 10) {
                fn("ON",       .onOff,    .gray)
                Spacer()
                fn("I ACCUSE", .iAccuse,  .red)
            }
            .padding(.top, 4)
        }
    }

    private func digit(_ n: Int) -> KeyButton {
        KeyButton(label: "\(n)", tint: .black) { onKey(.digit(n)) }
    }

    private func fn(_ label: String, _ key: ConsoleKey, _ tint: KeyButton.Tint) -> KeyButton {
        KeyButton(label: label, tint: tint) { onKey(key) }
    }

    private func row(_ keys: [KeyButton]) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<keys.count, id: \.self) { keys[$0] }
        }
    }
}
