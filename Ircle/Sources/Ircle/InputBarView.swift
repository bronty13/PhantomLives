import SwiftUI

/// The classic Ircle "Inputline" window: formatting buttons, a status readout
/// of who you're talking to, and the text field. Return sends.
struct InputBarView: View {
    @EnvironmentObject var model: IrcleModel
    @ObservedObject var buffer: IrcleBuffer
    let palette: PlatinumPalette
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Status row
            HStack(spacing: 6) {
                formatButton("B", code: "\u{02}")
                formatButton("I", code: "\u{1D}")
                formatButton("U", code: "\u{1F}")
                Text("talking to \(buffer.name)")
                    .font(palette.chromeFont())
                    .foregroundColor(palette.timestamp)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6).padding(.top, 3)

            // Input field
            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text("Type a message or /command…")
                    .foregroundColor(palette.timestamp))
                    .textFieldStyle(.plain)
                    .font(palette.messageFont(12))
                    .foregroundColor(palette.normalText)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .platinumBevel(palette, raised: false, fill: palette.textBG)

                Button("Send", action: send)
                    .font(palette.chromeFontBold())
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .platinumBevel(palette, raised: true)
            }
            .padding(6)
        }
        .background(palette.paneBG)
        .onAppear { focused = true }
        .onChange(of: buffer.id) { _, _ in focused = true }
    }

    private func formatButton(_ label: String, code: String) -> some View {
        Button(action: { text.append(code) }) {
            Text(label)
                .font(palette.chromeFontBold())
                .foregroundColor(palette.chromeText)
                .frame(width: 18, height: 16)
                .platinumBevel(palette, raised: true)
        }
        .buttonStyle(.plain)
    }

    private func send() {
        let toSend = text
        text = ""
        model.submitInput(toSend, in: buffer)
        focused = true
    }
}
