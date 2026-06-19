import SwiftUI

/// The classic Ircle "Inputline" window: formatting buttons, a status readout
/// of who you're talking to, and the text field. Return sends.
struct InputBarView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore
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
                // Classic style surfaces the rest of the original Inputline
                // toolbar: strikethrough, plain/reset, and the mIRC colour menu.
                if settingsStore.settings.interfaceStyle == .classic {
                    formatButton("S", code: "\u{1E}")   // strikethrough
                    formatButton("P", code: "\u{0F}")   // plain / reset all formatting
                    colorMenu
                }
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

    /// The mIRC colour picker — inserts `^C NN` (colour) or a bare `^C` (reset
    /// colour). Indices 0–15 are the standard mIRC palette.
    private var colorMenu: some View {
        Menu {
            ForEach(Array(Self.mircColors.enumerated()), id: \.offset) { i, c in
                Button { text.append("\u{03}\(String(format: "%02d", i))") } label: {
                    Label("\(i)  \(c.name)", systemImage: "circle.fill")
                        .foregroundStyle(c.color)
                }
            }
            Divider()
            Button("End colour") { text.append("\u{03}") }
        } label: {
            Text("C")
                .font(palette.chromeFontBold())
                .foregroundColor(palette.chromeText)
                .frame(width: 18, height: 16)
                .platinumBevel(palette, raised: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Insert an mIRC colour code")
    }

    /// Standard mIRC palette (0–15) for the colour menu labels.
    private static let mircColors: [(name: String, color: Color)] = [
        ("White",    Color(red: 1,    green: 1,    blue: 1)),
        ("Black",    Color(red: 0,    green: 0,    blue: 0)),
        ("Blue",     Color(red: 0,    green: 0,    blue: 0.5)),
        ("Green",    Color(red: 0,    green: 0.5,  blue: 0)),
        ("Red",      Color(red: 1,    green: 0,    blue: 0)),
        ("Brown",    Color(red: 0.5,  green: 0.25, blue: 0)),
        ("Purple",   Color(red: 0.5,  green: 0,    blue: 0.5)),
        ("Orange",   Color(red: 1,    green: 0.5,  blue: 0)),
        ("Yellow",   Color(red: 1,    green: 1,    blue: 0)),
        ("Lt Green", Color(red: 0,    green: 1,    blue: 0)),
        ("Teal",     Color(red: 0,    green: 0.5,  blue: 0.5)),
        ("Cyan",     Color(red: 0,    green: 1,    blue: 1)),
        ("Lt Blue",  Color(red: 0,    green: 0,    blue: 1)),
        ("Pink",     Color(red: 1,    green: 0,    blue: 1)),
        ("Grey",     Color(red: 0.5,  green: 0.5,  blue: 0.5)),
        ("Lt Grey",  Color(red: 0.75, green: 0.75, blue: 0.75)),
    ]

    private func send() {
        let toSend = text
        text = ""
        model.submitInput(toSend, in: buffer)
        focused = true
    }
}
