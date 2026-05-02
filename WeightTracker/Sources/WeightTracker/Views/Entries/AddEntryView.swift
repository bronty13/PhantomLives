import SwiftUI

struct AddEntryView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var date = Date()
    @State private var weightStr = ""
    @State private var notes = ""
    @State private var photoBlob: Data? = nil
    @State private var photoExt: String? = nil
    @State private var photoFilename: String? = nil
    @State private var errorMsg: String? = nil

    private var unit: WeightUnit { appState.settings.weightUnit }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Add Entry")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Cancel") { isPresented = false }
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

                Section("Notes (optional)") {
                    MarkdownEditor(text: $notes)
                        .frame(height: 80)
                }

                Section("Photo (optional)") {
                    PhotoPickerView(photoBlob: $photoBlob, photoExt: $photoExt, photoFilename: $photoFilename)
                }

                if let err = errorMsg {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 4)

            Divider()

            HStack {
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(appState.effectiveAccentColor)
            }
            .padding(20)
        }
        .frame(width: 400)
        .background(.windowBackground)
    }

    private func save() {
        guard let weight = Double(weightStr.replacingOccurrences(of: ",", with: ".")),
              weight > 0 else {
            errorMsg = "Please enter a valid weight."
            return
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = fmt.string(from: date)

        if appState.entries.contains(where: { $0.date == dateStr }) {
            errorMsg = "An entry for this date already exists."
            return
        }

        let weightLbs = unit == .lbs ? weight : weight / 0.453592
        let now = isoNow()
        var entry = WeightEntry(
            rowId: nil,
            date: dateStr,
            weightLbs: weightLbs,
            notesMd: notes,
            photoBlob: photoBlob,
            photoFilename: photoFilename,
            photoExt: photoExt,
            createdAt: now,
            updatedAt: now
        )
        appState.addEntry(&entry)
        isPresented = false
    }

    private func isoNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }
}
