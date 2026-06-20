import Foundation
import SwiftUI
import Testing
@testable import Ircle

@MainActor
@Suite("Modern fonts")
struct FontStyleTests {

    @Test func rootFallsBackToClassicWhenEmpty() {
        let rf = FontStyle.inherit.resolvedRoot(classicFamily: "Monaco", classicSize: 12)
        #expect(rf.family == "Monaco")
        #expect(rf.size == 12)
        #expect(rf.weight == .regular)
        #expect(rf.italic == false)
        #expect(rf.tracking == 0)
    }

    @Test func rootHonoursOverrides() {
        let st = FontStyle(family: "Menlo", size: 15, weight: .bold, italic: true, tracking: 1.5)
        let rf = st.resolvedRoot(classicFamily: "Monaco", classicSize: 12)
        #expect(rf.family == "Menlo")
        #expect(rf.size == 15)
        #expect(rf.weight == .bold)
        #expect(rf.italic)
        #expect(rf.tracking == 1.5)
    }

    @Test func childInheritsParentThenOverrides() {
        let parent = FontStyle(family: "Menlo", size: 14, weight: .medium)
            .resolvedRoot(classicFamily: "Monaco", classicSize: 12)
        // A timestamp that only sets size inherits family + weight from the body.
        let child = FontStyle(size: 10).resolved(parent: parent)
        #expect(child.family == "Menlo")     // inherited
        #expect(child.size == 10)            // overridden
        #expect(child.weight == .medium)     // inherited
    }

    @Test func weightMapping() {
        #expect(FontStyle.Weight.inherit.swiftUI == nil)
        #expect(FontStyle.Weight.bold.swiftUI == .bold)
        #expect(FontStyle.Weight.semibold.swiftUI == .semibold)
        #expect(FontStyle.Weight.allCases.count == 6)
    }

    @Test func slotsAndRoots() {
        #expect(FontSlot.allCases.count == 5)
        #expect(FontSlot.messageBody.isRoot)
        #expect(FontSlot.chrome.isRoot)
        #expect(FontSlot.nick.isRoot == false)
        #expect(FontSlot.timestamp.isRoot == false)
    }

    @Test func monospacedFamiliesAreASubset() {
        let all = Set(InstalledFonts.allFamilyNames)
        // Every monospaced family is also in the full list, and Menlo (ships with
        // macOS) registers as monospaced.
        #expect(InstalledFonts.monospacedFamilyNames.allSatisfy { all.contains($0) })
        #expect(InstalledFonts.monospacedFamilyNames.contains("Menlo"))
        #expect(InstalledFonts.allFamilyNames.count >= InstalledFonts.monospacedFamilyNames.count)
    }

    @Test func fontStyleRoundTripsThroughJSON() throws {
        let st = FontStyle(family: "SF Mono", size: 13, weight: .semibold,
                           italic: true, ligatures: false, tracking: 0.5)
        let data = try JSONEncoder().encode(st)
        let back = try JSONDecoder().decode(FontStyle.self, from: data)
        #expect(back == st)
    }
}
