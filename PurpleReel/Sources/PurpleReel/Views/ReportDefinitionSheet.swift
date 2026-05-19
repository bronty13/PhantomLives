import SwiftUI

/// "Report Definition" dialog (Kyno-parity, Image #89). Intermediate
/// step between the user clicking Create Report / Export Report and
/// the actual NSSavePanel. Lets the producer slim a long report by
/// dropping section groups.
///
/// Two of the five section toggles are locked-on (File size, File
/// type) so every row carries minimum identification columns even
/// when the user drops everything else.
///
/// Kyno's dialog only chooses sections — but PurpleReel has three
/// report formats (CSV / HTML / XLSX), so this dialog also exposes
/// a format Picker at the top.
struct ReportDefinitionSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var sections: ReportSections
    @State var format: ReportFormat

    enum ReportFormat: String, CaseIterable, Identifiable {
        case csv, html, xlsx
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .csv:  return "CSV (text only)"
            case .html: return "HTML (with thumbnails)"
            case .xlsx: return "Excel XLSX (with thumbnails)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    formatPicker
                    Divider()
                    sectionToggles
                    Text("File size and File type are always included so every row stays identifiable even with the rest of the sections off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 460)
    }

    private var header: some View {
        HStack {
            Text("Report Definition").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var formatPicker: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Format:").foregroundStyle(.secondary)
                Picker("", selection: $format) {
                    ForEach(ReportFormat.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
    }

    private var sectionToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sections").font(.title3.weight(.semibold))
            // Locked-on (Kyno's grayed boxes from Image #89). Always
            // included; the dialog still shows them so the user
            // understands the minimum.
            sectionRow(label: "File size", section: .fileSize, locked: true)
            sectionRow(label: "File type", section: .fileType, locked: true)
            sectionRow(label: "Duration",            section: .duration)
            sectionRow(label: "Format Details",      section: .formatDetails)
            sectionRow(label: "Descriptive Metadata", section: .descriptiveMetadata)
        }
    }

    @ViewBuilder
    private func sectionRow(label: String,
                             section: ReportSections,
                             locked: Bool = false) -> some View {
        let binding = Binding<Bool>(
            get: { sections.contains(section) },
            set: { isOn in
                if isOn { sections.insert(section) }
                else    { sections.remove(section) }
            }
        )
        Toggle(label, isOn: binding)
            .disabled(locked)
            .opacity(locked ? 0.6 : 1.0)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Create Report") {
                appState.runReportExportFromDialog(
                    format: format, sections: sections
                )
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
