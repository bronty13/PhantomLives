import SwiftUI

struct EntryDetailView: View {
    @EnvironmentObject var appState: AppState
    @Binding var entry: WeightEntry
    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var weightStr = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var photoBlob: Data? = nil
    @State private var photoExt: String? = nil
    @State private var photoFilename: String? = nil
    @State private var errorMsg: String? = nil

    private var unit: WeightUnit { appState.settings.weightUnit }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Entry")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()

            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)

                HStack {
                    Text("Weight (\(unit.label))")
                    Spacer()
                    TextField("e.g. 165.5", text: $weightStr)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Section("Notes") {
                    MarkdownEditor(text: $notes)
                        .frame(height: 100)
                }

                Section("Photo") {
                    PhotoPickerView(photoBlob: $photoBlob, photoExt: $photoExt, photoFilename: $photoFilename)
                }

                if let err = errorMsg {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(appState.effectiveAccentColor)
            }
            .padding(20)
        }
        .frame(width: 400)
        .background(.windowBackground)
        .onAppear { populateFromEntry() }
    }

    private func populateFromEntry() {
        let displayW = entry.displayWeight(unit: unit)
        weightStr = String(format: "%.1f", displayW)
        notes = entry.notesMd
        photoBlob = entry.photoBlob
        photoExt = entry.photoExt
        photoFilename = entry.photoFilename

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if let d = fmt.date(from: entry.date) { date = d }
    }

    private func save() {
        guard let weight = Double(weightStr.replacingOccurrences(of: ",", with: ".")), weight > 0 else {
            errorMsg = "Invalid weight value."
            return
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = fmt.string(from: date)

        let weightLbs = unit == .lbs ? weight : weight / 0.453592
        let now = isoNow()

        entry.date = dateStr
        entry.weightLbs = weightLbs
        entry.notesMd = notes
        entry.photoBlob = photoBlob
        entry.photoExt = photoExt
        entry.photoFilename = photoFilename
        entry.updatedAt = now

        appState.updateEntry(entry)
        onSave()
    }

    private func isoNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }
}
