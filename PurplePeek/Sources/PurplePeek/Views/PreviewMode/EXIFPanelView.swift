import SwiftUI

/// Scrollable metadata panel shown beside the viewer in Preview mode. Renders whatever
/// `EXIFData` fields are present, grouped into File / Camera / Exposure / Location sections.
struct EXIFPanelView: View {
    let exif: EXIFData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let exif {
                    section("File", rows: fileRows(exif))
                    let camera = cameraRows(exif)
                    if !camera.isEmpty { section("Camera", rows: camera) }
                    let exposure = exposureRows(exif)
                    if !exposure.isEmpty { section("Exposure", rows: exposure) }
                    if exif.hasLocation { section("Location", rows: locationRows(exif)) }
                } else {
                    ProgressView().padding(.top, 40)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sections

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top) {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).multilineTextAlignment(.trailing)
                }
                .font(.callout)
            }
            Divider().opacity(0.2)
        }
    }

    private func fileRows(_ e: EXIFData) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let n = e.fileName { rows.append(("Name", n)) }
        if let t = e.fileType { rows.append(("Type", t)) }
        if let dims = e.dimensionsString { rows.append(("Dimensions", dims)) }
        if let size = e.fileSizeBytes {
            rows.append(("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
        }
        if let dur = e.durationSeconds { rows.append(("Duration", formatDuration(dur))) }
        if let cp = e.colorProfile { rows.append(("Color", cp)) }
        return rows
    }

    private func cameraRows(_ e: EXIFData) -> [(String, String)] {
        var rows: [(String, String)] = []
        let model = [e.cameraMake, e.cameraModel].compactMap { $0 }.joined(separator: " ")
        if !model.isEmpty { rows.append(("Camera", model)) }
        if let lens = e.lensModel { rows.append(("Lens", lens)) }
        if let date = e.captureDate { rows.append(("Captured", date)) }
        return rows
    }

    private func exposureRows(_ e: EXIFData) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let f = e.focalLength { rows.append(("Focal length", f)) }
        if let a = e.aperture { rows.append(("Aperture", a)) }
        if let s = e.shutterSpeed { rows.append(("Shutter", s)) }
        if let i = e.iso { rows.append(("ISO", i)) }
        return rows
    }

    private func locationRows(_ e: EXIFData) -> [(String, String)] {
        guard let lat = e.latitude, let lon = e.longitude else { return [] }
        return [("Coordinates", String(format: "%.5f, %.5f", lat, lon))]
    }

    private func formatDuration(_ secs: Double) -> String {
        let total = Int(secs.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
