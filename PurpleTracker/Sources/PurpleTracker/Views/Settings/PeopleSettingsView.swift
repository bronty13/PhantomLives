import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings → People. Lets the user import the ADP UserFeed CSV (the
/// `~/Downloads/ADP_IMP_UserFeed_YYYY-MM-DD.csv` daily snapshot) and shows a
/// summary of the current roster.
struct PeopleSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var lastResult: PeopleService.ImportResult?
    @State private var importError: String?
    @State private var search: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Roster").font(.title3).fontWeight(.semibold)
                    Text("Imported from ADP IMP UserFeed CSV. Re-import any time — rows are upserted by Associate ID.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    pickAndImport()
                } label: {
                    Label("Import CSV…", systemImage: "square.and.arrow.down")
                }
                .controlSize(.large)
                Button {
                    autoImportLatestFromDownloads()
                } label: {
                    Label("Import Latest from Downloads", systemImage: "tray.and.arrow.down")
                }
                .help("Find the newest ADP_IMP_UserFeed_*.csv in ~/Downloads and import it.")
            }

            Toggle(isOn: Binding(
                get: { app.settingsStore.settings.peopleAutoImportOnLaunchEnabled },
                set: { v in
                    app.settingsStore.settings.peopleAutoImportOnLaunchEnabled = v
                    app.settingsStore.save()
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto-import latest ADP file on launch")
                    Text("On startup, scans ~/Downloads for the newest ADP_IMP_UserFeed_*.csv and imports it if it hasn't been imported before.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 24) {
                stat("People",       value: "\(app.people.count)")
                stat("Active",       value: "\(app.people.filter { $0.isActive }.count)")
                stat("Last Import",
                     value: app.lastPeopleImportDate
                        .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never")
            }
            .padding(.vertical, 6)

            if let r = lastResult {
                Text("Imported \(r.sourceFilename): \(r.inserted) new, \(r.updated) updated, \(r.skipped) skipped (of \(r.totalRows) rows).")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let e = importError {
                Text(e).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack {
                TextField("Search name, title, email, department…", text: $search)
                    .textFieldStyle(.roundedBorder)
            }

            Table(filteredPeople) {
                TableColumn("Name") { p in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.displayName).font(.body.weight(.medium))
                        if !p.preferredName.isEmpty
                            && p.preferredName.lowercased() != p.firstName.lowercased() {
                            Text("(\(Person.titleCase(p.firstName)) \(Person.titleCase(p.lastName)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("Title")    { p in Text(Person.titleCase(p.jobTitle)) }
                TableColumn("Department") { p in Text(Person.titleCase(p.department)) }
                TableColumn("Status") { p in
                    Text(p.positionStatus)
                        .foregroundStyle(p.isActive ? Color.green : Color.secondary)
                }
                TableColumn("Email") { p in Text(p.workEmail.lowercased()).font(.caption) }
            }
            .frame(minHeight: 260)
        }
        .padding(20)
    }

    private var filteredPeople: [Person] {
        guard !search.isEmpty else { return app.people }
        let q = search.lowercased()
        return app.people.filter {
            $0.displayName.lowercased().contains(q)
                || $0.jobTitle.lowercased().contains(q)
                || $0.department.lowercased().contains(q)
                || $0.workEmail.lowercased().contains(q)
        }
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
    }

    private func pickAndImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, UTType(filenameExtension: "csv") ?? .data]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            doImport(url)
        }
    }

    private func autoImportLatestFromDownloads() {
        guard let url = PeopleService.latestADPFileInDownloads() else {
            importError = "No ADP_IMP_UserFeed_*.csv found in ~/Downloads."
            return
        }
        doImport(url)
    }

    private func doImport(_ url: URL) {
        importError = nil
        do {
            lastResult = try app.importPeopleCSV(at: url)
            // Manual imports also count for auto-import dedupe — otherwise the
            // next launch would re-import the same file.
            app.settingsStore.settings.lastImportedAdpFilename = url.lastPathComponent
            app.settingsStore.save()
        } catch {
            importError = error.localizedDescription
        }
    }
}
