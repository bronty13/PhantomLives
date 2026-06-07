import SwiftUI

/// A password field that toggles between masked (`SecureField`) and plain
/// (`TextField`) based on an external `reveal` binding — so one eye toggle can
/// drive several fields (e.g. password + confirm) at once.
struct RevealableSecureField: View {
    let title: String
    @Binding var text: String
    @Binding var reveal: Bool

    init(_ title: String, text: Binding<String>, reveal: Binding<Bool>) {
        self.title = title
        self._text = text
        self._reveal = reveal
    }

    var body: some View {
        Group {
            if reveal {
                TextField(title, text: $text)
            } else {
                SecureField(title, text: $text)
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

/// The eye button that flips a `reveal` binding (show/hide password text).
struct RevealToggle: View {
    @Binding var reveal: Bool

    var body: some View {
        Toggle(isOn: $reveal) {
            Image(systemName: reveal ? "eye.slash" : "eye")
        }
        .toggleStyle(.button)
        .help(reveal ? "Hide password" : "Show password")
    }
}
