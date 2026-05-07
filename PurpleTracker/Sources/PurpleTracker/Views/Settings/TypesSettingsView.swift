import SwiftUI

struct TypesSettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Matter Types").font(.headline)
                Spacer()
                Button {
                    let new = MatterType(
                        id: UUID().uuidString,
                        name: "New Type",
                        colorHex: "#888888",
                        sortOrder: (app.types.map(\.sortOrder).max() ?? 0) + 1,
                        isCadenced: false
                    )
                    try? app.saveType(new)
                } label: { Label("Add", systemImage: "plus") }
            }
            ScrollView {
                ForEach(app.types) { t in
                    TypeRow(type: t)
                    Divider()
                }
            }
        }
    }
}

private struct TypeRow: View {
    let type: MatterType
    @EnvironmentObject var app: AppState
    @State private var name: String = ""
    @State private var color: Color = .gray
    @State private var cadenced: Bool = false
    @State private var loaded = false

    var body: some View {
        HStack {
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: color) { _, new in
                    var t = type
                    t.colorHex = new.toHex()
                    try? app.saveType(t)
                }
            TextField("", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    var t = type; t.name = name; try? app.saveType(t)
                }
            Toggle("Cadenced", isOn: $cadenced)
                .onChange(of: cadenced) { _, new in
                    var t = type; t.isCadenced = new; try? app.saveType(t)
                }
            Button(role: .destructive) {
                try? app.deleteType(id: type.id)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Delete (only allowed if no Matters use this type)")
        }
        .padding(.vertical, 4)
        .onAppear {
            guard !loaded else { return }
            name = type.name
            color = Color(hex: type.colorHex) ?? .gray
            cadenced = type.isCadenced
            loaded = true
        }
    }
}
