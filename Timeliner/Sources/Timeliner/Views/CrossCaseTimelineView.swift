import SwiftUI

/// Phase-2 cross-case combined timeline. The user picks any subset of cases
/// from a left-side toggle list, and their events are merged into a single
/// horizontal pan/zoom Canvas — color-coded by case so parallel
/// investigations can be compared at a glance.
struct CrossCaseTimelineView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedCaseIds: Set<String> = []
    @State private var panOffset: CGFloat = 0
    @State private var dragStartPan: CGFloat = 0
    @State private var zoom: CGFloat = 1
    @State private var pinchStartZoom: CGFloat = 1
    @State private var hoveredEventId: String?
    @State private var editingEvent: Event?
    @State private var didAutoFit = false

    /// Deterministic 8-color palette assigned in display order. The same
    /// case always lands on the same color across launches because cases are
    /// sorted (pinned-first, updated-desc) by the AppState reload pipeline.
    static let casePalette: [Color] = [
        Color(red: 0.35, green: 0.65, blue: 1.00),   // blue
        Color(red: 0.95, green: 0.45, blue: 0.50),   // coral
        Color(red: 0.50, green: 0.80, blue: 0.45),   // green
        Color(red: 1.00, green: 0.65, blue: 0.20),   // amber
        Color(red: 0.75, green: 0.45, blue: 0.95),   // violet
        Color(red: 1.00, green: 0.55, blue: 0.85),   // pink
        Color(red: 0.45, green: 0.85, blue: 0.85),   // teal
        Color(red: 0.85, green: 0.75, blue: 0.30),   // gold
    ]

    private var orderedCases: [Case] { appState.cases }

    private func color(for caseId: String) -> Color {
        guard let idx = orderedCases.firstIndex(where: { $0.id == caseId }) else {
            return .gray
        }
        return Self.casePalette[idx % Self.casePalette.count]
    }

    private var visibleEvents: [Event] {
        appState.events.filter { selectedCaseIds.contains($0.caseId) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidePanel
                .frame(width: 240)
            Divider()
            canvasArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Cross-case Timeline")
        .onAppear {
            // Default to selecting the first 3 cases on first appearance —
            // gives the user something to look at instead of a blank canvas.
            if selectedCaseIds.isEmpty {
                selectedCaseIds = Set(orderedCases.prefix(3).map(\.id))
            }
        }
        .sheet(item: $editingEvent) { ev in
            EventEditorSheet(event: ev, isNew: false)
                .environmentObject(appState)
        }
    }

    // MARK: - Side panel (case toggles + legend)

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cases")
                    .font(.headline)
                Spacer()
                if !orderedCases.isEmpty {
                    Button(allSelected ? "None" : "All") {
                        selectedCaseIds = allSelected ? [] : Set(orderedCases.map(\.id))
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)
            Divider()

            if orderedCases.isEmpty {
                Spacer()
                Text("No cases yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(orderedCases) { c in
                            CaseToggleRow(
                                aCase: c,
                                color: color(for: c.id),
                                isOn: Binding(
                                    get: { selectedCaseIds.contains(c.id) },
                                    set: { on in
                                        if on { selectedCaseIds.insert(c.id) }
                                        else { selectedCaseIds.remove(c.id) }
                                    }
                                ),
                                eventCount: appState.events.filter { $0.caseId == c.id }.count
                            )
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                }
            }

            Divider()
            HStack {
                Text("\(visibleEvents.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    zoom = 1; panOffset = 0
                } label: {
                    Label("Reset view", systemImage: "scope")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Reset zoom & pan")
            }
            .padding(10)
        }
        .background(Color(.windowBackgroundColor).opacity(0.4))
    }

    private var allSelected: Bool {
        !orderedCases.isEmpty && selectedCaseIds.count == orderedCases.count
    }

    // MARK: - Canvas area

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if visibleEvents.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.split.3x1")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text(selectedCaseIds.isEmpty
                             ? "Select one or more cases on the left."
                             : "No events in the selected cases.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let layout = TimelineLayout(
                        events: visibleEvents,
                        size: geo.size,
                        zoom: zoom,
                        panOffset: panOffset
                    )
                    canvas(layout: layout)
                    chrome(in: geo.size)
                }
            }
            .onAppear {
                if !didAutoFit {
                    panOffset = 0; zoom = 1
                    didAutoFit = true
                }
            }
        }
    }

    private func canvas(layout: TimelineLayout) -> some View {
        Canvas(rendersAsynchronously: false) { ctx, _ in
            drawAxis(ctx: ctx, layout: layout)
            drawEvents(ctx: ctx, layout: layout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(panGesture)
        .gesture(zoomGesture)
        .onTapGesture { tapLocation in
            if let hit = layout.event(at: tapLocation, hitRadius: 12) {
                editingEvent = hit
            }
        }
    }

    private func drawAxis(ctx: GraphicsContext, layout: TimelineLayout) {
        let theme = appState.currentTheme
        var trackPath = Path()
        trackPath.move(to: CGPoint(x: 0, y: layout.axisY))
        trackPath.addLine(to: CGPoint(x: layout.size.width, y: layout.axisY))
        ctx.stroke(trackPath, with: .color(theme.timelineTrackColor), lineWidth: 1.5)

        let span = layout.visibleSpanSeconds
        let granularity: TimelineLayout.Granularity = {
            if span > 365 * 86400 * 8 { return .year }
            if span > 365 * 86400 * 1.5 { return .quarter }
            if span > 30 * 86400 * 4 { return .month }
            return .week
        }()

        for tick in layout.ticks(granularity: granularity) {
            let major = tick.isMajor
            var p = Path()
            let h: CGFloat = major ? 14 : 7
            p.move(to: CGPoint(x: tick.x, y: layout.axisY - h))
            p.addLine(to: CGPoint(x: tick.x, y: layout.axisY + h))
            ctx.stroke(p, with: .color(theme.timelineTrackColor.opacity(major ? 0.7 : 0.35)),
                        lineWidth: 1)
            if major {
                ctx.draw(
                    Text(tick.label).font(.caption.monospacedDigit()).foregroundStyle(.secondary),
                    at: CGPoint(x: tick.x, y: layout.axisY + 22),
                    anchor: .center
                )
            }
        }
    }

    private func drawEvents(ctx: GraphicsContext, layout: TimelineLayout) {
        let placements = layout.placements()
        for p in placements {
            let ev = p.event
            let tint = color(for: ev.caseId)
            let isHovered = ev.id == hoveredEventId
            let radius: CGFloat = isHovered ? 9 : 7
            let dotRect = CGRect(x: p.x - radius, y: p.y - radius,
                                  width: radius * 2, height: radius * 2)
            if isHovered {
                ctx.fill(Path(ellipseIn: dotRect.insetBy(dx: -8, dy: -8)),
                          with: .color(tint.opacity(0.25)))
            }
            ctx.fill(Path(ellipseIn: dotRect), with: .color(tint))
            ctx.stroke(Path(ellipseIn: dotRect),
                        with: .color(.white.opacity(0.85)), lineWidth: 1.5)

            if abs(p.y - layout.axisY) > 1 {
                var stem = Path()
                stem.move(to: CGPoint(x: p.x, y: layout.axisY))
                stem.addLine(to: CGPoint(x: p.x, y: p.y))
                ctx.stroke(stem, with: .color(tint.opacity(0.4)), lineWidth: 0.8)
            }

            if !ev.title.isEmpty && (isHovered || layout.shouldLabel) {
                ctx.draw(
                    Text(ev.title).font(.caption.weight(.medium)).foregroundStyle(.primary),
                    at: CGPoint(x: p.x + radius + 6, y: p.y - 1),
                    anchor: .leading
                )
            }
        }
    }

    private func chrome(in size: CGSize) -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Button { zoom = max(0.4, zoom * 0.8) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }.buttonStyle(.borderless)
                    Button { zoom = 1; panOffset = 0 } label: {
                        Image(systemName: "scope")
                    }.buttonStyle(.borderless)
                    Button { zoom = min(60, zoom * 1.25) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }.buttonStyle(.borderless)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.background.opacity(0.7)))
                .overlay(Capsule().stroke(.secondary.opacity(0.25), lineWidth: 0.5))
            }
            Spacer()
            HStack {
                Text("Each color = a case · drag to pan · pinch or use ± to zoom · click an event to edit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", zoom * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = value.translation.width
                if dragStartPan == 0 && value.translation == .zero {
                    dragStartPan = panOffset
                }
                panOffset = dragStartPan + delta
            }
            .onEnded { _ in dragStartPan = panOffset }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if pinchStartZoom == 1 { pinchStartZoom = zoom }
                zoom = min(max(pinchStartZoom * value, 0.4), 60)
            }
            .onEnded { _ in pinchStartZoom = zoom }
    }
}

// MARK: - Toggle row

private struct CaseToggleRow: View {
    let aCase: Case
    let color: Color
    @Binding var isOn: Bool
    let eventCount: Int

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(color)
                        .frame(width: 12, height: 12)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(aCase.title.isEmpty ? "Untitled" : aCase.title)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(isOn ? .primary : .secondary)
                    Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? color.opacity(0.15) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
