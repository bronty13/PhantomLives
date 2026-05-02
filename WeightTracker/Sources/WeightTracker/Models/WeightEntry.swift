import Foundation
import GRDB

struct WeightEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var rowId: Int64?
    var date: String          // "YYYY-MM-DD" — unique, used as SwiftUI identity
    var weightLbs: Double
    var notesMd: String
    var photoBlob: Data?
    var photoFilename: String?
    var photoExt: String?
    var createdAt: String
    var updatedAt: String

    var id: String { date }

    static let databaseTableName = "weight_entries"

    enum CodingKeys: String, CodingKey {
        case rowId = "id"
        case date, weightLbs, notesMd, photoBlob, photoFilename, photoExt, createdAt, updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        rowId = inserted.rowID
    }

    var weightKg: Double { weightLbs * 0.453592 }

    func displayWeight(unit: WeightUnit) -> Double {
        unit == .lbs ? weightLbs : weightKg
    }

    var parsedDate: Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: date)
    }

    func exportPhotoFilename() -> String? {
        guard let ext = photoExt else { return nil }
        let weightStr = String(format: "%.2f", weightLbs).replacingOccurrences(of: ".", with: "_")
        let guid = UUID().uuidString
        return "\(date)-\(weightStr)-\(guid).\(ext)"
    }
}

enum WeightUnit: String, Codable, CaseIterable {
    case lbs, kg

    var label: String { rawValue.uppercased() }
}
