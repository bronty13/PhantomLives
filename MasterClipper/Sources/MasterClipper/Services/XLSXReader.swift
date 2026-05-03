import Foundation

/// Hand-rolled XLSX reader. xlsx is a zip of XML; we use `/usr/bin/unzip -p`
/// to stream individual entries and Foundation's `XMLParser` to walk them.
/// Only the bits we need (sheet listing + cell strings) are parsed.
enum XLSXReader {

    struct Sheet {
        let name: String
        let rows: [[String]]
    }

    enum ReaderError: Error, LocalizedError {
        case unzipFailed(String)
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .unzipFailed(let s): return "Could not unzip xlsx: \(s)"
            case .parseFailed(let s): return "Could not parse xlsx XML: \(s)"
            }
        }
    }

    static func read(url: URL) throws -> [Sheet] {
        let sharedStrings = try readSharedStrings(url: url)
        let sheetEntries = try readSheetIndex(url: url)
        var sheets: [Sheet] = []
        for entry in sheetEntries {
            let rows = try readSheetRows(url: url, sheetPath: entry.relativePath, sharedStrings: sharedStrings)
            sheets.append(Sheet(name: entry.name, rows: rows))
        }
        return sheets
    }

    // MARK: - Shared strings

    static func readSharedStrings(url: URL) throws -> [String] {
        guard let data = try? unzipPart(url: url, member: "xl/sharedStrings.xml") else {
            return []
        }
        let parser = SharedStringsParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else {
            throw ReaderError.parseFailed("sharedStrings.xml: \(xml.parserError?.localizedDescription ?? "unknown")")
        }
        return parser.strings
    }

    // MARK: - Sheet index

    private struct SheetEntry {
        let name: String
        let sheetId: String
        let relId: String
        var relativePath: String   // e.g. "xl/worksheets/sheet1.xml"
    }

    static func readSheetIndex(url: URL) throws -> [(name: String, relativePath: String)] {
        let workbookData = try unzipPart(url: url, member: "xl/workbook.xml")
        let wbParser = WorkbookParser()
        let xml = XMLParser(data: workbookData)
        xml.delegate = wbParser
        guard xml.parse() else {
            throw ReaderError.parseFailed("workbook.xml: \(xml.parserError?.localizedDescription ?? "unknown")")
        }

        // Read xl/_rels/workbook.xml.rels to map relId → target path
        let relsData = try unzipPart(url: url, member: "xl/_rels/workbook.xml.rels")
        let relsParser = RelsParser()
        let xml2 = XMLParser(data: relsData)
        xml2.delegate = relsParser
        guard xml2.parse() else {
            throw ReaderError.parseFailed("workbook.xml.rels: \(xml2.parserError?.localizedDescription ?? "unknown")")
        }

        var entries: [(name: String, relativePath: String)] = []
        for sheet in wbParser.sheets {
            guard let target = relsParser.targets[sheet.relId] else { continue }
            // Targets are usually like "worksheets/sheet1.xml" → prefix with "xl/"
            let path = target.hasPrefix("xl/") ? target : "xl/\(target)"
            entries.append((sheet.name, path))
        }
        return entries
    }

    // MARK: - Sheet rows

    static func readSheetRows(url: URL, sheetPath: String, sharedStrings: [String]) throws -> [[String]] {
        let data = try unzipPart(url: url, member: sheetPath)
        let parser = SheetParser(sharedStrings: sharedStrings)
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else {
            throw ReaderError.parseFailed("\(sheetPath): \(xml.parserError?.localizedDescription ?? "unknown")")
        }
        return parser.rows
    }

    // MARK: - Process / unzip

    static func unzipPart(url: URL, member: String) throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-p", url.path, member]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw ReaderError.unzipFailed("Process launch: \(error.localizedDescription)")
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 || data.isEmpty {
            let msg = String(data: errData, encoding: .utf8) ?? "exit \(proc.terminationStatus)"
            if data.isEmpty {
                throw ReaderError.unzipFailed("\(member): \(msg)")
            }
            // Some xlsx files emit benign warnings on stderr while still producing data;
            // only fail if we actually have no data.
        }
        return data
    }
}

// MARK: - SAX delegates

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var inside_si = false
    private var current = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "si" {
            inside_si = true
            current = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inside_si { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "si" {
            strings.append(current)
            inside_si = false
        }
    }
}

private struct WorkbookSheetEntry {
    let name: String
    let sheetId: String
    let relId: String
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    var sheets: [WorkbookSheetEntry] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "sheet" {
            let name = attributeDict["name"] ?? ""
            let sheetId = attributeDict["sheetId"] ?? ""
            // r:id is namespaced; the parser exposes it as "r:id"
            let relId = attributeDict["r:id"] ?? attributeDict["id"] ?? ""
            sheets.append(WorkbookSheetEntry(name: name, sheetId: sheetId, relId: relId))
        }
    }
}

private final class RelsParser: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]   // relId → target path

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "Relationship" {
            let id = attributeDict["Id"] ?? ""
            let target = attributeDict["Target"] ?? ""
            if !id.isEmpty && !target.isEmpty {
                targets[id] = target
            }
        }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    let sharedStrings: [String]
    var rows: [[String]] = []

    private var currentRow: [String] = []
    private var currentCellRef: String = ""        // e.g. "B7"
    private var currentCellType: String = ""       // "" | "s" (sharedString) | "str" | "b" | "n"
    private var currentCellValue: String = ""
    private var inValue = false
    private var inInlineStr = false
    private var collectChars = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "row":
            currentRow = []
        case "c":
            currentCellRef = attributeDict["r"] ?? ""
            currentCellType = attributeDict["t"] ?? ""
            currentCellValue = ""
        case "v":
            inValue = true
            collectChars = true
        case "is":
            inInlineStr = true
        case "t":
            if inInlineStr { collectChars = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectChars { currentCellValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v":
            inValue = false
            collectChars = false
        case "t":
            if inInlineStr { collectChars = false }
        case "is":
            inInlineStr = false
        case "c":
            // Resolve sharedString reference if needed
            let resolved: String
            if currentCellType == "s", let idx = Int(currentCellValue), idx >= 0 && idx < sharedStrings.count {
                resolved = sharedStrings[idx]
            } else {
                resolved = currentCellValue
            }

            // Pad to the column index encoded in the cell ref (e.g. "B7" → col 1).
            let col = columnIndex(fromRef: currentCellRef)
            while currentRow.count < col {
                currentRow.append("")
            }
            currentRow.append(resolved)

            currentCellRef = ""
            currentCellType = ""
            currentCellValue = ""
        case "row":
            rows.append(currentRow)
            currentRow = []
        default:
            break
        }
    }

    private func columnIndex(fromRef ref: String) -> Int {
        // Letters part of "AB12" → 28-1 → 27 (0-indexed)
        var letters = ""
        for ch in ref {
            if ch.isLetter { letters.append(ch) } else { break }
        }
        if letters.isEmpty { return 0 }
        var col = 0
        for ch in letters.uppercased() {
            guard let v = ch.asciiValue, v >= 65 && v <= 90 else { return 0 }
            col = col * 26 + Int(v - 64)
        }
        return col - 1   // 0-indexed
    }
}
