import Foundation

/// Detects pasted SNOW or ADO URLs and pulls out the human-readable
/// reference number so the user can autofill the correct External1/2
/// "Number" field. Pure regex, returns nil if the URL doesn't match.
enum URLAutofillService {

    enum Match: Equatable {
        /// ServiceNow incident / request etc — `INC0012345`, `REQ0001234`,
        /// `RITM0001234`, `CHG0001234`, `TASK0001234`.
        case snow(number: String)
        /// Azure DevOps work item — `12345`.
        case ado(number: String)
    }

    /// Try to identify a SNOW or ADO URL and extract its reference number.
    static func detect(_ raw: String) -> Match? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // ServiceNow: …?id=…&number=INC0012345 (or ?sysparm_query=number=INC…)
        if let m = firstMatch(in: s,
            pattern: #"(?:[?&](?:sys_id|sysparm_query|number|id)[^&]*?)?(INC|REQ|RITM|CHG|TASK)0*(\d+)"#) {
            let prefix = (s as NSString).substring(with: m.range(at: 1))
            let digits = (s as NSString).substring(with: m.range(at: 2))
            // Pad SNOW numbers back to 7 digits to match SNOW's display format.
            let padded = String(repeating: "0", count: max(0, 7 - digits.count)) + digits
            return .snow(number: "\(prefix)\(padded)")
        }
        // Azure DevOps: /_workitems/edit/12345  OR  /_workitems/recentlyupdated/12345
        if let m = firstMatch(in: s,
            pattern: #"_workitems/[a-z]+/(\d+)"#) {
            let digits = (s as NSString).substring(with: m.range(at: 1))
            return .ado(number: digits)
        }
        return nil
    }

    private static func firstMatch(in s: String, pattern: String) -> NSTextCheckingResult? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.firstMatch(in: s, options: [], range: range)
    }
}
