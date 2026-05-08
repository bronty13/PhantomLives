import Foundation
import GRDB
import CryptoKit

/// On-demand integrity sweep — re-hashes every attachment BLOB and reports
/// any whose stored SHA1 no longer matches, plus dangling person FKs.
enum IntegrityCheckService {

    struct Report {
        var attachmentsChecked: Int = 0
        var attachmentsCorrupt: [(id: String, filename: String)] = []
        var danglingRequestor: [String] = []     // matter ids
        var danglingInterestedParties: [String] = []  // matter ids
        var orphanedSubtasks: Int = 0

        var summary: String {
            var lines: [String] = []
            lines.append("Attachments checked: \(attachmentsChecked)")
            lines.append("Attachments with hash mismatch: \(attachmentsCorrupt.count)")
            for c in attachmentsCorrupt {
                lines.append("  • \(c.id)  \(c.filename)")
            }
            lines.append("Matters with dangling Requestor: \(danglingRequestor.count)")
            lines.append("Matters with dangling Interested Party: \(danglingInterestedParties.count)")
            lines.append("Orphaned subtasks: \(orphanedSubtasks)")
            return lines.joined(separator: "\n")
        }
    }

    @MainActor
    static func run(peopleIds: Set<String>) throws -> Report {
        var r = Report()
        let pool = DatabaseService.shared.dbPool
        try pool.read { db in
            // Attachments
            let atts = try Attachment.fetchAll(db)
            r.attachmentsChecked = atts.count
            for a in atts {
                let actual = sha1Hex(a.data)
                if actual.lowercased() != a.sha1.lowercased() {
                    r.attachmentsCorrupt.append((a.id, a.filename))
                }
            }

            // Matters with dangling person FKs
            let matters = try Matter.fetchAll(db)
            for m in matters {
                if !m.requestorAssociateId.isEmpty,
                   !peopleIds.contains(m.requestorAssociateId) {
                    r.danglingRequestor.append(m.id)
                }
                let ips = [m.interestedParty1AssociateId, m.interestedParty2AssociateId,
                           m.interestedParty3AssociateId, m.interestedParty4AssociateId,
                           m.interestedParty5AssociateId]
                if ips.contains(where: { !$0.isEmpty && !peopleIds.contains($0) }) {
                    r.danglingInterestedParties.append(m.id)
                }
            }

            // Subtasks pointing at no-longer-existent matters (cascades should
            // prevent this but we still check defensively).
            let validIds = Set(matters.map(\.id))
            let subs = try Subtask.fetchAll(db)
            r.orphanedSubtasks = subs.filter { !validIds.contains($0.matterId) }.count
        }
        return r
    }

    private static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
