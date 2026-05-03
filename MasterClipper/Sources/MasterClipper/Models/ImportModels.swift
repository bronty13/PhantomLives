import Foundation

enum ClipFieldKey: String, CaseIterable, Hashable {
    case ignore
    case externalClipId
    case trackingTag
    case personaCode
    case title
    case descriptionRaw
    case descriptionRefined
    case categories
    case keywords
    case clipFilename
    case thumbnailFilename
    case previewFilename
    case performers
    case lengthSeconds
    case priceCents
    case salesCount
    case incomeCents
    case contentDate
    case goLiveDate
    case status
    case notes

    var label: String {
        switch self {
        case .ignore:             return "— ignore —"
        case .externalClipId:     return "External Clip ID (legacy #)"
        case .trackingTag:        return "Tracking Tag"
        case .personaCode:        return "Persona"
        case .title:              return "Title"
        case .descriptionRaw:     return "Description (raw)"
        case .descriptionRefined: return "Description (refined)"
        case .categories:         return "Categories"
        case .keywords:           return "Keywords"
        case .clipFilename:       return "Clip Filename"
        case .thumbnailFilename:  return "Thumbnail Filename"
        case .previewFilename:    return "Preview Filename"
        case .performers:         return "Performers"
        case .lengthSeconds:      return "Length"
        case .priceCents:         return "Price"
        case .salesCount:         return "Sales"
        case .incomeCents:        return "Income"
        case .contentDate:        return "Content Date"
        case .goLiveDate:         return "Go Live Date"
        case .status:             return "Status"
        case .notes:              return "Notes"
        }
    }
}

struct ParsedClipRow: Identifiable {
    let id = UUID()
    var values: [ClipFieldKey: String]
    var rawCategories: [String] = []
    var rawKeywords: [String] = []
    var isDuplicate: Bool = false
    var isSelected: Bool = true
    var sourceRowIndex: Int
}

struct ImportSession {
    var sourceColumns: [String]
    var rows: [[String]]
    var mapping: [Int: ClipFieldKey]            // source column index → field
    var previewRows: [ParsedClipRow]
    var sheetName: String?
    var fileName: String?
}
