import Foundation

/// Builds the launchd LaunchAgent property list that runs the scheduled archive. Pure (a
/// String in, a String out) so the generated plist is unit-testable. The orchestration
/// (writing it, `launchctl bootstrap`) lives in the app's SchedulerService.
public enum LaunchAgentPlist {

    public static func build(
        label: String,
        programArguments: [String],
        schedule: ArchiveSchedule,
        stdoutPath: String,
        stderrPath: String
    ) -> String {
        let argsXML = programArguments
            .map { "        <string>\(xmlEscape($0))</string>" }
            .joined(separator: "\n")

        let calXML = schedule.calendarKeys
            .map { "        <key>\($0.key)</key>\n        <integer>\($0.value)</integer>" }
            .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(xmlEscape(label))</string>
            <key>ProgramArguments</key>
            <array>
        \(argsXML)
            </array>
            <key>StartCalendarInterval</key>
            <dict>
        \(calXML)
            </dict>
            <key>RunAtLoad</key>
            <false/>
            <key>ProcessType</key>
            <string>Background</string>
            <key>StandardOutPath</key>
            <string>\(xmlEscape(stdoutPath))</string>
            <key>StandardErrorPath</key>
            <string>\(xmlEscape(stderrPath))</string>
        </dict>
        </plist>
        """
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
