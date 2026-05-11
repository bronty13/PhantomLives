import Foundation

/// The 20-card cast.
///
/// The shipped names are generic placeholders preserving the original game's
/// id → sex mapping (1–10 male, 11–20 female) and id parity. To restore the
/// canonical cast from your copy of the rules, edit the `all` table below —
/// the engine treats `name` and `occupation` as opaque display strings.
enum SuspectRoster {

    static let all: [Suspect] = [
        Suspect(id:  1, name: "Suspect 01", occupation: "Occupation 1",  sex: .male),
        Suspect(id:  2, name: "Suspect 02", occupation: "Occupation 2",  sex: .male),
        Suspect(id:  3, name: "Suspect 03", occupation: "Occupation 3",  sex: .male),
        Suspect(id:  4, name: "Suspect 04", occupation: "Occupation 4",  sex: .male),
        Suspect(id:  5, name: "Suspect 05", occupation: "Occupation 5",  sex: .male),
        Suspect(id:  6, name: "Suspect 06", occupation: "Occupation 6",  sex: .male),
        Suspect(id:  7, name: "Suspect 07", occupation: "Occupation 7",  sex: .male),
        Suspect(id:  8, name: "Suspect 08", occupation: "Occupation 8",  sex: .male),
        Suspect(id:  9, name: "Suspect 09", occupation: "Occupation 9",  sex: .male),
        Suspect(id: 10, name: "Suspect 10", occupation: "Occupation 10", sex: .male),
        Suspect(id: 11, name: "Suspect 11", occupation: "Occupation 11", sex: .female),
        Suspect(id: 12, name: "Suspect 12", occupation: "Occupation 12", sex: .female),
        Suspect(id: 13, name: "Suspect 13", occupation: "Occupation 13", sex: .female),
        Suspect(id: 14, name: "Suspect 14", occupation: "Occupation 14", sex: .female),
        Suspect(id: 15, name: "Suspect 15", occupation: "Occupation 15", sex: .female),
        Suspect(id: 16, name: "Suspect 16", occupation: "Occupation 16", sex: .female),
        Suspect(id: 17, name: "Suspect 17", occupation: "Occupation 17", sex: .female),
        Suspect(id: 18, name: "Suspect 18", occupation: "Occupation 18", sex: .female),
        Suspect(id: 19, name: "Suspect 19", occupation: "Occupation 19", sex: .female),
        Suspect(id: 20, name: "Suspect 20", occupation: "Occupation 20", sex: .female),
    ]

    static let byId: [Int: Suspect] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func suspect(id: Int) -> Suspect { byId[id]! }

    static let maleIds: [Int] = all.filter { $0.sex == .male }.map(\.id)
    static let femaleIds: [Int] = all.filter { $0.sex == .female }.map(\.id)

    static func ids(of sex: Sex) -> [Int] {
        sex == .male ? maleIds : femaleIds
    }
}
