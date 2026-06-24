import Testing
import Foundation
@testable import PurpleMirror

@Suite struct RebootSafeServiceTests {

    @Test func parseExternalDisksPicksPhysicalExternals() {
        let out = """
        /dev/disk3 (internal, physical):
           #:                       TYPE NAME            SIZE       IDENTIFIER
        /dev/disk6 (external, physical):
           #:                       TYPE NAME            SIZE       IDENTIFIER
           1:        Apple_APFS Container disk7          2.0 TB     disk6s2
        /dev/disk8 (external, physical):
        """
        #expect(RebootSafeService.parseExternalDisks(out) == ["disk6", "disk8"])
    }

    @Test func parseExternalDisksEmptyWhenNoneAttached() {
        let out = "/dev/disk3 (internal, physical):\n   stuff\n"
        #expect(RebootSafeService.parseExternalDisks(out).isEmpty)
    }

    @Test func parseMountedExternalVolumesReadsVolumeNames() {
        let mount = """
        /dev/disk3s5 on /System/Volumes/Data (apfs, local, journaled, nobrowse)
        /dev/disk7s1 on /Volumes/PRO-G40 (apfs, local, nodev, nosuid, journaled, noowners)
        /dev/disk9s1 on /Volumes/LACIE (apfs, local, nodev)
        """
        #expect(RebootSafeService.parseMountedExternalVolumes(mount) == ["PRO-G40", "LACIE"])
    }

    @Test func parseMountedExternalVolumesIgnoresSystemAndRoot() {
        let mount = """
        /dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
        /dev/disk3s6 on /System/Volumes/VM (apfs, local, noexec)
        devfs on /dev (devfs, local, nobrowse)
        """
        #expect(RebootSafeService.parseMountedExternalVolumes(mount).isEmpty)
    }

    @Test func parseMountedExternalVolumesHandlesSpacesInName() {
        let mount = "/dev/disk10s1 on /Volumes/Client Drive 2026 (hfs, local, nodev, nosuid, journaled)"
        #expect(RebootSafeService.parseMountedExternalVolumes(mount) == ["Client Drive 2026"])
    }
}
