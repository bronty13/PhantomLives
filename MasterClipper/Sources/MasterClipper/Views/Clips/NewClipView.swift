import SwiftUI

struct NewClipView: View {
    @EnvironmentObject private var appState: AppState

    let onCreated: (Clip) -> Void
    let onCancel: () -> Void

    @State private var personaCode: String = ""
    @State private var title: String = ""
    @State private var contentDateText: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Clip")
                .font(.title2.weight(.semibold))

            Form {
                Picker("Persona", selection: $personaCode) {
                    ForEach(appState.personas) { p in
                        Text("\(p.code) — \(p.displayName)").tag(p.code)
                    }
                }

                TextField("Title (optional)", text: $title)
                    .textFieldStyle(.roundedBorder)

                TextField("Content date (YYYY-MM-DD, blank = today)", text: $contentDateText)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)

            Text("The clip ID is generated as YYYYMMDD#### keyed off the content date. Leave content date blank to use today.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear {
            if personaCode.isEmpty {
                personaCode = appState.settings.defaultPersonaCode
            }
        }
    }

    private func create() {
        do {
            var date: Date? = nil
            let trimmed = contentDateText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.locale = Locale(identifier: "en_US_POSIX")
                guard let parsed = fmt.date(from: trimmed) else {
                    error = "Content date must be YYYY-MM-DD."
                    return
                }
                date = parsed
            }
            let clip = try appState.createClip(personaCode: personaCode, title: title, contentDate: date)
            onCreated(clip)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
