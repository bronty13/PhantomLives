import SwiftUI

/// Global running-timer banner shown at the top of the main window whenever
/// any timer is active, regardless of which Matter is currently selected.
/// Click the title to jump to the running Matter; click Stop to log the entry.
struct RunningTimerBanner: View {
    @EnvironmentObject var app: AppState
    @State private var noteDraft: String = ""
    @State private var showNotePrompt: Bool = false

    var body: some View {
        if let mid = app.timer.activeMatterId,
           let matter = app.matters.first(where: { $0.id == mid }) {
            let typeColor = app.typesById[matter.typeId].flatMap { Color(hex: $0.colorHex) } ?? .accentColor
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(Color.green.opacity(0.5), lineWidth: 4)
                            .scaleEffect(1.6)
                            .opacity(0.6)
                    )
                    .accessibilityLabel("Timer running")

                VStack(alignment: .leading, spacing: 1) {
                    Text("RUNNING")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        app.selectMatter(id: mid)
                    } label: {
                        HStack(spacing: 8) {
                            Text(matter.id)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(typeColor.opacity(0.25))
                                .foregroundStyle(typeColor)
                                .cornerRadius(4)
                            Text(matter.title.isEmpty ? "Untitled" : matter.title)
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Jump to this Matter")
                }

                Spacer()

                Text(TimeFormat.hms(app.timer.elapsedSeconds))
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.green)
                    .monospacedDigit()

                Button {
                    noteDraft = ""
                    showNotePrompt = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.regular)
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .alert("Add a note (optional)", isPresented: $showNotePrompt) {
                    TextField("What did you work on?", text: $noteDraft)
                    Button("Save") { _ = app.timer.stop(note: noteDraft) }
                    Button("Stop without note", role: .cancel) { _ = app.timer.stop() }
                } message: {
                    Text("Annotate this time entry so the Time tab shows what was done.")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color.green.opacity(0.18), Color.green.opacity(0.08)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .overlay(
                Rectangle().fill(Color.green).frame(height: 2),
                alignment: .top
            )
            .overlay(
                Rectangle().fill(Color.green.opacity(0.3)).frame(height: 1),
                alignment: .bottom
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
