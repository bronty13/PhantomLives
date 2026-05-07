import Foundation

/// Spawns the next Matter in a cadenced series when the predecessor closes.
/// Called from `AppState.updateMatterStatus(...)` whenever a Matter with a
/// non-nil `cadenceId` transitions to the lifecycle's terminal value.
@MainActor
enum CadenceService {

    /// Build (without inserting) the successor Matter for `previous`. The
    /// caller is responsible for assigning a fresh Matter ID and inserting it
    /// — keeping this as a pure factory makes it trivially unit-testable.
    static func nextMatter(after previous: Matter, cadence: Cadence) -> Matter {
        let baseDate = previous.dueAt ?? Date()
        let nextDue = cadence.nextDate(after: baseDate)
        let now = Date()
        return Matter(
            id: "",                          // filled in by allocator
            title: previous.title,
            typeId: previous.typeId,
            status: MatterStatus.new.rawValue,
            descriptionMd: previous.descriptionMd,
            dueAt: nextDue,
            createdAt: now,
            accessedAt: now,
            modifiedAt: now,
            external1Number: previous.external1Number,
            external1Url: previous.external1Url,
            external2Number: previous.external2Number,
            external2Url: previous.external2Url,
            external3Number: previous.external3Number,
            external3Url: previous.external3Url,
            timeTrackingCode: previous.timeTrackingCode,
            resolutionMd: "",                // fresh — don't carry resolution forward
            lessonsMd: "",                   // fresh
            notesMd: "",                     // fresh
            fileStorePrimary: previous.fileStorePrimary,
            fileStoreSecondary: previous.fileStoreSecondary,
            cadenceId: previous.cadenceId,
            parentMatterId: previous.id
        )
    }
}
