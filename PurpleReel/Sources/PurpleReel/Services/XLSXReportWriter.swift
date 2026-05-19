import Foundation
import AppKit

/// Producer / AE deliverable: a real Excel `.xlsx` workbook with one
/// row per clip and an embedded JPEG of the poster frame.
///
/// `.xlsx` is a zip of OOXML XML parts. The minimal file set this
/// writer emits:
///
///     [Content_Types].xml
///     _rels/.rels
///     xl/workbook.xml
///     xl/_rels/workbook.xml.rels
///     xl/worksheets/sheet1.xml
///     xl/worksheets/_rels/sheet1.xml.rels
///     xl/drawings/drawing1.xml
///     xl/drawings/_rels/drawing1.xml.rels
///     xl/media/imageN.jpeg          (one per asset that has a preview)
///
/// Cell strings are inlined (`<c t="inlineStr">`) so we don't need a
/// `sharedStrings.xml` part — keeps the writer smaller and the file
/// trivially diffable.
///
/// The archive itself is built by shelling out to `/usr/bin/zip`.
/// PhantomLives already ships zip-based backups via the same tool, so
/// pulling in a Swift zip library just to avoid one Process invocation
/// isn't worth the dependency.
@MainActor
enum XLSXReportWriter {

    /// Emit a `.xlsx` workbook to `destination`. Same return shape as
    /// `ReportExporter.writeHTML` — `(written, skipped)` so the UI
    /// can flash a status for image-only / unprobed clips that had no
    /// extractable preview.
    static func writeXLSX(assets: [Asset],
                           to destination: URL,
                           appState: AppState) async throws
        -> (written: Int, skipped: Int)
    {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("purplereel-xlsx-\(UUID().uuidString)",
                                     isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // Pull thumbnails up front so the sheet XML knows which rows
        // have an image anchor and which fall back to a "no preview"
        // cell label.
        var thumbs: [(assetIndex: Int, jpegPath: URL, sizePx: CGSize)] = []
        var skipped = 0
        for (i, asset) in assets.enumerated() {
            guard let url = await ThumbnailService.thumbnails(for: asset,
                                                                count: 1).first,
                  let data = try? Data(contentsOf: url),
                  let img = NSImage(data: data),
                  let rep = img.representations.first
            else {
                skipped += 1
                continue
            }
            // Bound the thumbnail at 120px wide for the worksheet
            // (same dimension the HTML report uses). Maintain aspect
            // ratio from the raw NSImage representation; default to
            // 16:9 if pixel sizes report zero.
            let pxW = max(1, rep.pixelsWide)
            let pxH = max(1, rep.pixelsHigh)
            let aspect = Double(pxW) / Double(pxH)
            let outW: Double = 120
            let outH = outW / (aspect > 0 ? aspect : (16.0 / 9.0))
            thumbs.append((i, url, CGSize(width: outW, height: outH)))
        }

        // Lay out the directory tree the zip will mirror.
        let mediaDir = work.appendingPathComponent("xl/media",
                                                     isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir,
                                                  withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: work.appendingPathComponent("_rels", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: work.appendingPathComponent("xl/_rels", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: work.appendingPathComponent("xl/worksheets/_rels",
                                              isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: work.appendingPathComponent("xl/drawings/_rels",
                                              isDirectory: true),
            withIntermediateDirectories: true)

        // Drop the JPEGs into `xl/media/imageN.jpeg` (1-indexed).
        for (n, thumb) in thumbs.enumerated() {
            let dest = mediaDir
                .appendingPathComponent("image\(n + 1).jpeg")
            try FileManager.default.copyItem(at: thumb.jpegPath, to: dest)
        }

        // Write the XML parts.
        try contentTypesXML(imageCount: thumbs.count)
            .write(to: work.appendingPathComponent("[Content_Types].xml"),
                   atomically: true, encoding: .utf8)
        try rootRelsXML()
            .write(to: work.appendingPathComponent("_rels/.rels"),
                   atomically: true, encoding: .utf8)
        try workbookXML()
            .write(to: work.appendingPathComponent("xl/workbook.xml"),
                   atomically: true, encoding: .utf8)
        try workbookRelsXML()
            .write(to: work.appendingPathComponent("xl/_rels/workbook.xml.rels"),
                   atomically: true, encoding: .utf8)
        try sheetXML(assets: assets,
                      appState: appState,
                      thumbs: thumbs)
            .write(to: work.appendingPathComponent("xl/worksheets/sheet1.xml"),
                   atomically: true, encoding: .utf8)
        try sheetRelsXML()
            .write(to: work.appendingPathComponent(
                "xl/worksheets/_rels/sheet1.xml.rels"),
                   atomically: true, encoding: .utf8)
        try drawingXML(thumbs: thumbs)
            .write(to: work.appendingPathComponent("xl/drawings/drawing1.xml"),
                   atomically: true, encoding: .utf8)
        try drawingRelsXML(imageCount: thumbs.count)
            .write(to: work.appendingPathComponent(
                "xl/drawings/_rels/drawing1.xml.rels"),
                   atomically: true, encoding: .utf8)

        // Zip the temp directory to the destination. `-X` strips
        // Mac-specific extended attributes (DS_Store, AppleDouble)
        // that confuse strict zip readers; `-r` recurses;
        // `-q` keeps stdout quiet.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = work
        proc.arguments = ["-r", "-q", "-X", destination.path, "."]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(domain: "PurpleReel.XLSX", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "zip exited \(proc.terminationStatus)"])
        }

        return (written: thumbs.count, skipped: skipped)
    }

    // MARK: - XML parts

    private static func contentTypesXML(imageCount: Int) -> String {
        // JPEG MIME is registered via `<Default Extension="jpeg">`
        // below; no per-image `<Override>` is needed.
        _ = imageCount
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="jpeg" ContentType="image/jpeg"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>
        </Types>
        """
    }

    private static func rootRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private static func workbookXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Media report" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
    }

    private static func workbookRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
    }

    private static func sheetXML(assets: [Asset],
                                  appState: AppState,
                                  thumbs: [(assetIndex: Int, jpegPath: URL,
                                              sizePx: CGSize)]) -> String {
        // Row 1 = header. Rows 2…N = data. Column A = thumbnail
        // (empty cell label — the drawing anchors a JPEG over it).
        let header = ["Thumbnail", "Filename", "Codec", "Resolution",
                       "Display Size", "Aspect Ratio", "FPS",
                       "Duration (sec)", "Size (bytes)",
                       "Date Modified", "Date Created", "Date Recorded",
                       "Rating", "Title", "Description",
                       "Reel", "Scene", "Shot", "Take", "Angle", "Camera",
                       "Audio Channels", "Tags"]

        var rows: [String] = []
        rows.append(rowXML(rowIdx: 1, cells: header))
        for (i, asset) in assets.enumerated() {
            let meta = asset.rowId.flatMap { appState.clipMetadataIndex[$0] }
            let tags = appState.tagIndex[asset.path]?.sorted()
                .joined(separator: "; ") ?? ""
            let rating = appState.ratingIndex[asset.path]
                .map(String.init) ?? ""
            let dur = asset.durationSeconds
                .map { String(format: "%.3f", $0) } ?? ""
            let created = asset.createdAt.map(dateString) ?? ""
            let recorded = asset.recordedAt.map(dateString) ?? ""
            let cells: [String] = [
                "",                                  // thumbnail column
                asset.filename,
                asset.codec ?? "",
                resolutionString(asset),
                displaySizeString(asset),
                aspectRatioString(asset),
                fpsString(asset),
                dur,
                "\(asset.sizeBytes)",
                dateString(asset.modifiedAt),
                created,
                recorded,
                rating,
                meta?.title ?? "",
                meta?.description ?? "",
                meta?.reel ?? "",
                meta?.scene ?? "",
                meta?.shot ?? "",
                meta?.take ?? "",
                meta?.angle ?? "",
                meta?.camera ?? "",
                meta?.audioChannelNames ?? "",
                tags
            ]
            rows.append(rowXML(rowIdx: i + 2, cells: cells,
                                 rowHeight: rowHeightForThumb(i, in: thumbs)))
        }

        // Column widths: A (thumbnail) = wide enough for 120px; rest
        // default. Excel's column width is in "characters" — 18 is a
        // working approximation of 120 device-independent pixels.
        let colA = """
        <cols>
          <col min="1" max="1" width="18" customWidth="1"/>
        </cols>
        """

        let drawingRef = thumbs.isEmpty ? "" : """
        <drawing r:id="rId1"/>
        """

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                   xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          \(colA)
          <sheetData>
        \(rows.joined(separator: "\n"))
          </sheetData>
          \(drawingRef)
        </worksheet>
        """
    }

    /// Excel row height is in points (1pt = 1/72"). 96dpi screen ≈
    /// 0.75pt/px, so a 68px-tall thumbnail wants ~51pt of row height
    /// plus a tiny margin so the image doesn't kiss the gridlines.
    private static func rowHeightForThumb(_ rowIdxZero: Int,
                                            in thumbs: [(assetIndex: Int,
                                                          jpegPath: URL,
                                                          sizePx: CGSize)])
        -> Double?
    {
        guard let t = thumbs.first(where: { $0.assetIndex == rowIdxZero })
        else { return nil }
        return Double(t.sizePx.height) * 0.75 + 4
    }

    private static func rowXML(rowIdx: Int,
                                cells: [String],
                                rowHeight: Double? = nil) -> String
    {
        let cellXMLs = cells.enumerated().map { col, value -> String in
            let colLetter = columnLetter(col)
            // Empty cells emit nothing — Excel treats absent cells as
            // empty implicitly and it keeps the file size down.
            if value.isEmpty { return "" }
            return """
            <c r="\(colLetter)\(rowIdx)" t="inlineStr"><is><t xml:space="preserve">\(escapeXML(value))</t></is></c>
            """
        }.filter { !$0.isEmpty }.joined()
        if let h = rowHeight {
            return "<row r=\"\(rowIdx)\" ht=\"\(h)\" customHeight=\"1\">\(cellXMLs)</row>"
        }
        return "<row r=\"\(rowIdx)\">\(cellXMLs)</row>"
    }

    private static func sheetRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>
        </Relationships>
        """
    }

    /// Each `<xdr:oneCellAnchor>` pins an image's top-left corner to
    /// (col=0, row=N) and gives the explicit extent in EMU. 1px ≈
    /// 9525 EMU at 96dpi.
    private static func drawingXML(thumbs: [(assetIndex: Int,
                                               jpegPath: URL,
                                               sizePx: CGSize)]) -> String
    {
        let anchors = thumbs.enumerated().map { idx, t -> String in
            let row = t.assetIndex + 1   // header is row 0 in 0-based
            let widthEMU = Int(t.sizePx.width * 9525)
            let heightEMU = Int(t.sizePx.height * 9525)
            let rId = idx + 1
            let imgId = idx + 2          // anything > 1 is fine
            return """
            <xdr:oneCellAnchor>
              <xdr:from>
                <xdr:col>0</xdr:col><xdr:colOff>19050</xdr:colOff>
                <xdr:row>\(row)</xdr:row><xdr:rowOff>19050</xdr:rowOff>
              </xdr:from>
              <xdr:ext cx="\(widthEMU)" cy="\(heightEMU)"/>
              <xdr:pic>
                <xdr:nvPicPr>
                  <xdr:cNvPr id="\(imgId)" name="thumb\(imgId)"/>
                  <xdr:cNvPicPr/>
                </xdr:nvPicPr>
                <xdr:blipFill>
                  <a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rId\(rId)"/>
                  <a:stretch><a:fillRect/></a:stretch>
                </xdr:blipFill>
                <xdr:spPr>
                  <a:xfrm><a:off x="0" y="0"/><a:ext cx="\(widthEMU)" cy="\(heightEMU)"/></a:xfrm>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                </xdr:spPr>
              </xdr:pic>
              <xdr:clientData/>
            </xdr:oneCellAnchor>
            """
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"
                  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        \(anchors)
        </xdr:wsDr>
        """
    }

    private static func drawingRelsXML(imageCount: Int) -> String {
        let rels = (0 ..< imageCount).map { i -> String in
            let n = i + 1
            return """
            <Relationship Id="rId\(n)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image\(n).jpeg"/>
            """
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(rels)
        </Relationships>
        """
    }

    // MARK: - Helpers shared with ReportExporter

    private static func columnLetter(_ zeroIndexed: Int) -> String {
        // Excel columns: A, B, …, Z, AA, AB, … For a 23-column report
        // we never go past W, but handle the general case anyway.
        var n = zeroIndexed
        var s = ""
        repeat {
            s = String(UnicodeScalar(UInt8(65 + n % 26))) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }

    private static func escapeXML(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&":  out.append("&amp;")
            case "<":  out.append("&lt;")
            case ">":  out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'":  out.append("&apos;")
            default:   out.append(c)
            }
        }
        return out
    }

    private static func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    private static func resolutionString(_ a: Asset) -> String {
        guard let w = a.widthPx, let h = a.heightPx else { return "" }
        return "\(w)×\(h)"
    }

    private static func displaySizeString(_ a: Asset) -> String {
        guard let w = a.widthPx, let h = a.heightPx else { return "" }
        // 0.78mm/px @ ~93 DPI is the Kyno convention.
        let inchesW = Double(w) / 93.0
        let inchesH = Double(h) / 93.0
        return String(format: "%.1f\"×%.1f\"", inchesW, inchesH)
    }

    private static func aspectRatioString(_ a: Asset) -> String {
        guard let w = a.widthPx, let h = a.heightPx, h > 0 else { return "" }
        let ratio = Double(w) / Double(h)
        return String(format: "%.3f:1", ratio)
    }

    private static func fpsString(_ a: Asset) -> String {
        guard let f = a.frameRate else { return "" }
        return String(format: "%.2f", f)
    }
}
