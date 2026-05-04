import SwiftUI

struct NewClipView: View {
    @EnvironmentObject private var appState: AppState

    let onCreated: (Clip) -> Void
    let onCancel: () -> Void

    @State private var personaCode: String = ""
    @State private var title: String = ""
    @State private var contentDate: Date = Date()
    @State private var contentDateActive: Bool = false
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

                // Optional content date — toggle controls whether the picker
                // is used at all. When off, the new clip's id and contentDate
                // both fall back to today.
                HStack(spacing: 10) {
                    Toggle(isOn: $contentDateActive) {
                        Text("Content date")
                    }
                    .toggleStyle(.checkbox)
                    if contentDateActive {
                        DatePicker("",
                            selection: $contentDate,
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                    } else {
                        Text("Use today")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .formStyle(.grouped)

            Text("The clip ID is generated as YYYY-MM-DD-##### keyed off the content date. Leave content date off to use today.")
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
            let date: Date? = contentDateActive ? contentDate : nil
            let clip = try appState.createClip(
                personaCode: personaCode,
                title: title,
                contentDate: date
            )
            onCreated(clip)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
