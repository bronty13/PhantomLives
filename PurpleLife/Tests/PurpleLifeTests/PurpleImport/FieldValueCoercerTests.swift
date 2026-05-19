import XCTest
@testable import PurpleLife

/// Coercer is the load-bearing layer between source bytes and the
/// `fields_json` shape. These tests pin both inference (column →
/// FieldKind) and per-value coercion across every `FieldKind` that
/// Phase 1 supports.
final class FieldValueCoercerTests: XCTestCase {

    // MARK: - Inference

    func testInferKindAllBooleanSamples() {
        let kind = FieldValueCoercer.inferKind(samples: ["true", "false", "yes", "no", "1", "0"])
        XCTAssertEqual(kind, .boolean)
    }

    func testInferKindAllNumericSamples() {
        let kind = FieldValueCoercer.inferKind(samples: ["1.5", "2", "3.14", "42"])
        XCTAssertEqual(kind, .number)
    }

    func testInferKindAllISODateSamples() {
        let kind = FieldValueCoercer.inferKind(samples: ["2024-01-15", "2026-05-19", "2026-12-31"])
        XCTAssertEqual(kind, .date)
    }

    func testInferKindAllURLSamples() {
        let kind = FieldValueCoercer.inferKind(samples: [
            "https://example.com",
            "https://anthropic.com",
            "http://localhost:8080"
        ])
        XCTAssertEqual(kind, .url)
    }

    func testInferKindAllEmailSamples() {
        let kind = FieldValueCoercer.inferKind(samples: ["a@b.com", "c@d.org", "e@f.io"])
        XCTAssertEqual(kind, .email)
    }

    func testInferKindFallsBackToTextWhenAmbiguous() {
        let kind = FieldValueCoercer.inferKind(samples: ["hello", "world", "ada lovelace"])
        XCTAssertEqual(kind, .text)
    }

    func testInferKindRequiresEightyPercentForNonText() {
        // 4 numbers + 2 text out of 6 = 66.7% — falls below the
        // 80% threshold, so the column should be classified text.
        let kind = FieldValueCoercer.inferKind(samples: ["1", "2", "3", "4", "ouch", "nope"])
        XCTAssertEqual(kind, .text)
    }

    func testInferKindHandlesEmptySample() {
        XCTAssertEqual(FieldValueCoercer.inferKind(samples: []), .text)
        XCTAssertEqual(FieldValueCoercer.inferKind(samples: [nil, nil]), .text)
    }

    // MARK: - Coercion

    func testCoerceTextPassesThrough() {
        let r = FieldValueCoercer.coerce("hello", to: .text)
        if case .value(let v) = r { XCTAssertEqual(v as? String, "hello") }
        else { XCTFail("Expected .value, got \(r)") }
    }

    func testCoerceNumberHandlesIntAndDouble() {
        if case .value(let v) = FieldValueCoercer.coerce("42", to: .number) {
            XCTAssertEqual(v as? Double, 42.0)
        } else { XCTFail() }
        if case .value(let v) = FieldValueCoercer.coerce("3.14", to: .number) {
            XCTAssertEqual(v as? Double, 3.14)
        } else { XCTFail() }
    }

    func testCoerceNumberStripsCommaThousandsSeparator() {
        if case .value(let v) = FieldValueCoercer.coerce("1,234.5", to: .number) {
            XCTAssertEqual(v as? Double, 1234.5)
        } else { XCTFail() }
    }

    func testCoerceNumberFailsOnNonNumeric() {
        let r = FieldValueCoercer.coerce("not a number", to: .number)
        if case .failure = r { /* ok */ } else { XCTFail("Expected .failure, got \(r)") }
    }

    func testCoerceBooleanFromLiterals() {
        for lit in ["true", "yes", "1", "TRUE"] {
            if case .value(let v) = FieldValueCoercer.coerce(lit, to: .boolean) {
                XCTAssertEqual(v as? Bool, true, "‘\(lit)’ should be true")
            } else { XCTFail("‘\(lit)’ failed") }
        }
        for lit in ["false", "no", "0", "F"] {
            if case .value(let v) = FieldValueCoercer.coerce(lit, to: .boolean) {
                XCTAssertEqual(v as? Bool, false, "‘\(lit)’ should be false")
            } else { XCTFail("‘\(lit)’ failed") }
        }
    }

    func testCoerceDateFromExcelSerial() {
        // 43478 days from 1899-12-30 = 2019-01-13 (verified against
        // openpyxl.utils.datetime.from_excel). Pivot tables and some
        // workbook shapes drop date number-formatting from the
        // underlying cells, so XLSXReader can't always tag the cell
        // as a date — coercion has to recover.
        if case .value(let v) = FieldValueCoercer.coerce("43478", to: .date) {
            XCTAssertEqual(v as? String, "2019-01-13")
        } else { XCTFail() }
        // Below the 1..100000 gate stays unparsed.
        if case .failure = FieldValueCoercer.coerce("0", to: .date) { /* ok */ }
        else { XCTFail("0 should not be treated as Excel serial") }
        if case .failure = FieldValueCoercer.coerce("999999", to: .date) { /* ok */ }
        else { XCTFail("999999 should not be treated as Excel serial") }
    }

    func testCoerceDateFromMultipleFormats() {
        for s in ["2024-01-15", "2024/01/15", "1/15/2024", "01/15/2024"] {
            if case .value(let v) = FieldValueCoercer.coerce(s, to: .date) {
                XCTAssertEqual(v as? String, "2024-01-15", "‘\(s)’ should normalize to 2024-01-15")
            } else { XCTFail("‘\(s)’ failed") }
        }
    }

    func testCoerceDateTimeFromISO() {
        let s = "2024-01-15T10:30:00Z"
        if case .value(let v) = FieldValueCoercer.coerce(s, to: .dateTime) {
            XCTAssertNotNil(v as? String)
        } else { XCTFail() }
    }

    func testCoerceRatingClipsTo0Through5() {
        if case .value(let v) = FieldValueCoercer.coerce("7", to: .rating) {
            XCTAssertEqual(v as? Int, 5)
        } else { XCTFail() }
        if case .value(let v) = FieldValueCoercer.coerce("-2", to: .rating) {
            XCTAssertEqual(v as? Int, 0)
        } else { XCTFail() }
    }

    func testCoerceSelectMatchesByOptionName() {
        let options = [
            FieldOption(id: "opt-a", name: "Alpha", colorHex: nil),
            FieldOption(id: "opt-b", name: "Bravo", colorHex: nil)
        ]
        if case .value(let v) = FieldValueCoercer.coerce("alpha", to: .select, fieldOptions: options) {
            XCTAssertEqual(v as? String, "opt-a")  // case-insensitive name match
        } else { XCTFail() }
    }

    func testCoerceMultiSelectSplitsByCommaSemicolonPipe() {
        let options = [
            FieldOption(id: "x", name: "X", colorHex: nil),
            FieldOption(id: "y", name: "Y", colorHex: nil),
            FieldOption(id: "z", name: "Z", colorHex: nil)
        ]
        if case .value(let v) = FieldValueCoercer.coerce("x, y; z", to: .multiSelect, fieldOptions: options) {
            XCTAssertEqual(v as? [String], ["x", "y", "z"])
        } else { XCTFail() }
    }

    func testCoerceEmptyStringReturnsEmpty() {
        if case .empty = FieldValueCoercer.coerce("", to: .text) { /* ok */ }
        else { XCTFail() }
        if case .empty = FieldValueCoercer.coerce("   ", to: .text) { /* ok */ }
        else { XCTFail() }
    }

    func testCoerceNilReturnsEmpty() {
        if case .empty = FieldValueCoercer.coerce(nil, to: .text) { /* ok */ }
        else { XCTFail() }
    }

    func testCoerceRichTextAttachmentLinkRejected() {
        // The plan's design decision #5 says these need separate
        // handling — the runner doesn't try to coerce them from
        // raw primitives.
        for kind in [FieldKind.richText, .attachment, .link, .noteLog] {
            if case .failure = FieldValueCoercer.coerce("anything", to: kind) { /* ok */ }
            else { XCTFail("\(kind) should fail to coerce from raw string") }
        }
    }

    // MARK: - Bool-as-NSNumber trap

    func testInferDoesNotMistakeBoolForNumber() {
        // The same trap that bit `PlaintextSnapshotService` before
        // the CFGetTypeID guard landed. `NSNumber(value: true)`
        // bridges to `.boolean`, not `.number`.
        let n: NSNumber = true
        let kind = FieldValueCoercer.inferKind(samples: [n, n, n])
        XCTAssertEqual(kind, .boolean)
    }
}
