import SwiftUI

struct LengthField: View {
    @Binding var lengthSeconds: Int?
    @State private var text: String = ""
    @State private var invalid: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("mm:ss or hh:mm:ss", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onAppear { text = DurationFormatter.format(lengthSeconds) == "—" ? "" : DurationFormatter.format(lengthSeconds) }
                .onChange(of: text) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        lengthSeconds = nil
                        invalid = false
                    } else if let secs = DurationFormatter.parse(trimmed) {
                        lengthSeconds = secs
                        invalid = false
                    } else {
                        invalid = true
                    }
                }
            if invalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Use mm:ss or hh:mm:ss")
            }
        }
    }
}
