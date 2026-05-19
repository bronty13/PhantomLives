import Foundation

/// Heterogeneous JSON value codec. Lets us round-trip the
/// `fields_json` shape (strings, numbers, bools, arrays, nested
/// dicts, null) through `JSONEncoder`/`JSONDecoder` without writing a
/// per-key type-erasure dance. Originally inlined in
/// `PlaintextSnapshotService.swift`; extracted here in Phase 1 of
/// Purple Import / Purple Export because the new mapping +
/// import-runner code needs the same shape.
///
/// On encode: walks Swift values + `NSNumber`/`NSNull` wrappers from
/// `JSONSerialization` and emits the right JSON primitive.
///
/// On decode: tries each primitive shape in turn, falling through
/// to nested array / dict / null.
///
/// The Bool-vs-Int trap is intentional: `JSONSerialization` hands
/// back `NSNumber` for every numeric, and the bridge `as? Bool` /
/// `as? Int` matches on a Bool-wrapped `NSNumber` because Bool's
/// Objective-C encoding shares the integer encoding with `1`/`0`. The
/// CFTypeID check is the only reliable way to distinguish them. Do
/// not "simplify" that branch — the regression is silent.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try Self.encodeAny(value, into: &container)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try Self.decodeAny(from: container)
    }

    private static func encodeAny(_ value: Any, into container: inout SingleValueEncodingContainer) throws {
        if value is NSNull {
            try container.encodeNil()
        } else if let v = value as? NSNumber {
            if CFGetTypeID(v) == CFBooleanGetTypeID() {
                try container.encode(v.boolValue)
            } else {
                let d = v.doubleValue
                if d.rounded() == d, abs(d) < 1e15 {
                    try container.encode(Int64(d))
                } else {
                    try container.encode(d)
                }
            }
        } else if let v = value as? Bool {
            try container.encode(v)
        } else if let v = value as? Int {
            try container.encode(v)
        } else if let v = value as? Int64 {
            try container.encode(v)
        } else if let v = value as? Double {
            try container.encode(v)
        } else if let v = value as? String {
            try container.encode(v)
        } else if let v = value as? [Any] {
            try container.encode(v.map { AnyCodable($0) })
        } else if let v = value as? [String: Any] {
            try container.encode(v.mapValues { AnyCodable($0) })
        } else {
            try container.encode(String(describing: value))
        }
    }

    private static func decodeAny(from container: SingleValueDecodingContainer) throws -> Any {
        if container.decodeNil() { return NSNull() }
        if let v = try? container.decode(Bool.self) { return v }
        if let v = try? container.decode(Int.self) { return v }
        if let v = try? container.decode(Double.self) { return v }
        if let v = try? container.decode(String.self) { return v }
        if let v = try? container.decode([AnyCodable].self) { return v.map(\.value) }
        if let v = try? container.decode([String: AnyCodable].self) {
            return v.mapValues(\.value)
        }
        return NSNull()
    }
}
