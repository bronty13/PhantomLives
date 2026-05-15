import SwiftUI

/// "All time" toggle + from/to date+time pickers. When `allTime` is on
/// the date pickers are disabled but kept visible so the user can flip
/// the toggle without losing their previously-dialled values.
struct TimeRangeForm: View {
    @Binding var allTime: Bool
    @Binding var from: Date
    @Binding var to: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIME RANGE")
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            Toggle("Archive all time", isOn: $allTime)
            HStack(spacing: 18) {
                DatePicker("From",
                           selection: $from,
                           displayedComponents: [.date, .hourAndMinute])
                    .disabled(allTime)
                    .opacity(allTime ? 0.5 : 1.0)
                DatePicker("To",
                           selection: $to,
                           displayedComponents: [.date, .hourAndMinute])
                    .disabled(allTime)
                    .opacity(allTime ? 0.5 : 1.0)
            }
            Text("Slackdump's API supports UTC timestamps; SlackSucker converts your local times automatically.")
                .font(AppFont.sans(11))
                .foregroundStyle(.tertiary)
        }
    }
}
