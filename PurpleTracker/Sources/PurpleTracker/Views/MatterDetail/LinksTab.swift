import SwiftUI

/// Cross-references between Matters: "depends on" (directional) and
/// "related" (informational). Click a chip to jump to that Matter.
struct LinksTab: View {
    let matter: Matter
    @EnvironmentObject var app: AppState
    @State private var pickerKind: MatterLink.Kind = .related
    @State private var pickerTarget: String = ""

    private var links: [MatterLink] {
        app.linksByMatter[matter.id] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section(.dependsOn)
            section(.related)
            Divider()
            HStack {
                Picker("Kind", selection: $pickerKind) {
                    ForEach(MatterLink.Kind.allCases) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Picker("Matter", selection: $pickerTarget) {
                    Text("Choose a Matter…").tag("")
                    ForEach(app.matters.filter { $0.id != matter.id }) { m in
                        Text("\(m.id)  \(m.title)").tag(m.id)
                    }
                }
                .pickerStyle(.menu)

                Button("Link") {
                    guard !pickerTarget.isEmpty else { return }
                    try? app.addLink(from: matter.id, to: pickerTarget, kind: pickerKind)
                    pickerTarget = ""
                }
                .disabled(pickerTarget.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func section(_ kind: MatterLink.Kind) -> some View {
        let mine = links.filter { $0.kind == kind.rawValue }
        Text(kind.displayName)
            .font(.headline)
        if mine.isEmpty {
            Text("None")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            ForEach(mine, id: \.relatedMatterId) { l in
                HStack {
                    Button {
                        app.selectMatter(id: l.relatedMatterId)
                    } label: {
                        let target = app.matters.first(where: { $0.id == l.relatedMatterId })
                        Text("\(l.relatedMatterId) — \(target?.title ?? "(deleted)")")
                            .lineLimit(1)
                    }
                    .buttonStyle(.link)
                    Spacer()
                    Button(role: .destructive) {
                        try? app.deleteLink(l)
                    } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}
