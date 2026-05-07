import SwiftUI

/// Phase-2 horizontal timeline: pan/zoom Canvas rendering of a case's events
/// along a time axis. Drag to pan, scroll/magnify to zoom, click an event
/// dot to open the editor, double-click empty space to add a new event at
/// that point in time. Sharing the same `[Event]` slice as the vertical
/// list view, so filter state is honored.
struct HorizontalTimelineView: View {
    @EnvironmentObject private var appState: AppState
    let caseId: String
    let events: [Event]   // already filtered upstream

    /// Persisted-only-in-memory pan offset (positive = pan right). Each
    /// CaseDetailView session resets to "auto-fit" on first appear.
    @State private var panOffset: CGFloat = 0
    @State private var dragStartPan: CGFloat = 0
    /// Zoom multiplier on top of the auto-fit baseline. 1 = full extent
    /// fits the visible canvas; bigger = magnify.
    @State private var zoom: CGFloat = 1
    @State private var pinchStartZoom: CGFloat = 1

    @State private var hoveredEventId: String?
    @State private var editingEvent: Event?
    @State private var didAutoFit = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if events.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    canvas(in: geo.size)
                    overlayChrome(in: geo.size)
                }
            }
            .onAppear {
                if !didAutoFit {
                    panOffset = 0
                    zoom = 1
                    didAutoFit = true
                }
            }
            .onChange(of: events) { _, _ in
                // If the user changes filters and the selected event vanishes
                // from the visible set, drop the hover state.
                if let h = hoveredEventId,
                   !events.contains(where: { $0.id == h }) {
                    hoveredEventId = nil
                }
            }
            .sheet(item: $editingEvent) { ev in
                EventEditorSheet(event: ev, isNew: false)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No events match the current filters.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Canvas

    private func canvas(in size: CGSize) -> some View {
        let layout = TimelineLayout(events: events, size: size, zoom: zoom, panOffset: panOffset)
        return Canvas(rendersAsynchronously: false) { ctx, _ in
            drawAxis(ctx: ctx, layout: layout)
            drawEvents(ctx: ctx, layout: layout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(panGesture)
        .gesture(zoomGesture)
        .onTapGesture { tapLocation in
            handleTap(at: tapLocation, layout: layout)
        }
    }

    // MARK: - Drawing

    private func drawAxis(ctx: GraphicsContext, layout: TimelineLayout) {
        let theme = appState.currentTheme

        // Horizontal track
        var trackPath = Path()
        trackPath.move(to: CGPoint(x: 0, y: layout.axisY))
        trackPath.addLine(to: CGPoint(x: layout.size.width, y: layout.axisY))
        ctx.stroke(trackPath, with: .color(theme.timelineTrackColor), lineWidth: 1.5)

        // Year/month tick marks. Choose tick granularity based on visible span.
        let span = layout.visibleSpanSeconds
        let granularity: TimelineLayout.Granularity = {
            if span > 365 * 86400 * 8 { return .year }
            if span > 365 * 86400 * 1.5 { return .quarter }
            if span > 30 * 86400 * 4 { return .month }
            return .week
        }()

        for tick in layout.ticks(granularity: granularity) {
            let x = tick.x
            let major = tick.isMajor
            var p = Path()
            let h: CGFloat = major ? 14 : 7
            p.move(to: CGPoint(x: x, y: layout.axisY - h))
            p.addLine(to: CGPoint(x: x, y: layout.axisY + h))
            ctx.stroke(p, with: .color(theme.timelineTrackColor.opacity(major ? 0.7 : 0.35)),
                        lineWidth: 1)
            if major {
                let text = Text(tick.label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                ctx.draw(text, at: CGPoint(x: x, y: layout.axisY + 22), anchor: .center)
            }
        }
    }

    private func drawEvents(ctx: GraphicsContext, layout: TimelineLayout) {
        // Place each event at its date-x; if multiple events fall in the same
        // few pixels, fan them out vertically so they don't overlap.
        let placements = layout.placements()

        for placement in placements {
            let ev = placement.event
            let x = placement.x
            let y = placement.y
            let imp = ev.importanceEnum
            let isHovered = ev.id == hoveredEventId

            let radius: CGFloat = isHovered ? 9 : 7
            let dotRect = CGRect(x: x - radius, y: y - radius,
                                  width: radius * 2, height: radius * 2)

            // Halo
            if isHovered {
                ctx.fill(
                    Path(ellipseIn: dotRect.insetBy(dx: -8, dy: -8)),
                    with: .color(imp.tint.opacity(0.25))
                )
            }

            ctx.fill(Path(ellipseIn: dotRect), with: .color(imp.tint))
            ctx.stroke(Path(ellipseIn: dotRect),
                        with: .color(.white.opacity(0.85)), lineWidth: 1.5)

            // Stem connecting dot to axis if it's been pushed off-axis to avoid overlap
            if abs(y - layout.axisY) > 1 {
                var stem = Path()
                stem.move(to: CGPoint(x: x, y: layout.axisY))
                stem.addLine(to: CGPoint(x: x, y: y))
                ctx.stroke(stem, with: .color(imp.tint.opacity(0.4)), lineWidth: 0.8)
            }

            // Title — only render if there's enough room (at high zoom levels
            // we draw more labels)
            if !ev.title.isEmpty && (isHovered || layout.shouldLabel) {
                let label = Text(ev.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                ctx.draw(
                    label,
                    at: CGPoint(x: x + radius + 6, y: y - 1),
                    anchor: .leading
                )
            }
        }
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
            .onEnded { _ in
                dragStartPan = panOffset
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if pinchStartZoom == 1 {
                    pinchStartZoom = zoom
                }
                let next = pinchStartZoom * value
                zoom = min(max(next, 0.4), 60)
            }
            .onEnded { _ in
                pinchStartZoom = zoom
            }
    }

    // MARK: - Hit testing

    private func handleTap(at location: CGPoint, layout: TimelineLayout) {
        if let hit = layout.event(at: location, hitRadius: 12) {
            editingEvent = hit
        }
    }

    // MARK: - Overlay chrome (zoom controls, hint text)

    private func overlayChrome(in size: CGSize) -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        zoom = max(0.4, zoom * 0.8)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Zoom out")
                    Button {
                        zoom = 1
                        panOffset = 0
                    } label: {
                        Image(systemName: "scope")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset (auto-fit)")
                    Button {
                        zoom = min(60, zoom * 1.25)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Zoom in")
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.background.opacity(0.7)))
                .overlay(Capsule().stroke(.secondary.opacity(0.25), lineWidth: 0.5))
            }
            Spacer()
            HStack {
                Text("Drag to pan · pinch or use ± to zoom · click an event to edit")
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
}

// MARK: - Layout math

/// Pure layout struct — given a set of events, a canvas size, and the
/// current zoom/pan, produces tick marks and event placements. Lifted out of
/// the view so the math is testable and the Canvas closure stays small.
struct TimelineLayout {
    let events: [Event]
    let size: CGSize
    let zoom: CGFloat
    let panOffset: CGFloat

    /// Cached parsed dates so we don't re-parse on every method call.
    private let parsed: [(event: Event, date: Date)]
    private let domainStart: Date
    private let domainEnd: Date
    /// Width of the entire domain at zoom = 1 (fits the canvas exactly).
    private let baseDomainWidth: CGFloat

    var axisY: CGFloat { size.height / 2 }

    /// Whether to draw event labels by default (only at higher zoom levels).
    var shouldLabel: Bool { zoom >= 1.2 }

    /// Total seconds of *visible* timespan — used to decide tick granularity.
    var visibleSpanSeconds: TimeInterval {
        let total = domainEnd.timeIntervalSince(domainStart)
        return total / Double(zoom)
    }

    init(events: [Event], size: CGSize, zoom: CGFloat, panOffset: CGFloat) {
        self.events = events
        self.size = size
        self.zoom = zoom
        self.panOffset = panOffset

        let parsed = events.compactMap { ev -> (Event, Date)? in
            guard let d = ev.parsedStart else { return nil }
            return (ev, d)
        }
        self.parsed = parsed

        if let lo = parsed.map(\.1).min(), let hi = parsed.map(\.1).max() {
            // Pad the domain by ~5% on each side so dots don't sit on the canvas edge.
            let padSec = max(86400, hi.timeIntervalSince(lo) * 0.05)
            domainStart = lo.addingTimeInterval(-padSec)
            domainEnd = hi.addingTimeInterval(padSec)
        } else {
            // Single event or none — just use a 1-year window centered on today.
            domainStart = Date().addingTimeInterval(-180 * 86400)
            domainEnd = Date().addingTimeInterval(180 * 86400)
        }
        baseDomainWidth = size.width
    }

    /// Map a date to the canvas X coordinate.
    func x(for date: Date) -> CGFloat {
        let total = domainEnd.timeIntervalSince(domainStart)
        guard total > 0 else { return size.width / 2 + panOffset }
        let frac = CGFloat(date.timeIntervalSince(domainStart) / total)
        return frac * baseDomainWidth * zoom + panOffset
    }

    /// Inverse: pixel X → date. Used by hit-test and "create at point" gestures.
    func date(for x: CGFloat) -> Date {
        let total = domainEnd.timeIntervalSince(domainStart)
        let frac = (x - panOffset) / (baseDomainWidth * zoom)
        return domainStart.addingTimeInterval(total * Double(frac))
    }

    // MARK: - Tick marks

    enum Granularity { case week, month, quarter, year }

    struct Tick { let date: Date; let x: CGFloat; let label: String; let isMajor: Bool }

    func ticks(granularity: Granularity) -> [Tick] {
        var ticks: [Tick] = []
        let cal = Calendar(identifier: .gregorian)
        var cursor = domainStart

        let majorComponent: Calendar.Component
        let stepComponent: Calendar.Component
        let stepValue: Int
        let labelFmt: DateFormatter
        switch granularity {
        case .year:
            majorComponent = .year
            stepComponent = .year
            stepValue = 1
            labelFmt = TimelineDateFormatters.yearOnly
            cursor = cal.startOfYear(for: domainStart)
        case .quarter:
            majorComponent = .year
            stepComponent = .month
            stepValue = 3
            labelFmt = TimelineDateFormatters.monthYear
            cursor = cal.startOfMonth(for: domainStart)
        case .month:
            majorComponent = .month
            stepComponent = .month
            stepValue = 1
            labelFmt = TimelineDateFormatters.monthYear
            cursor = cal.startOfMonth(for: domainStart)
        case .week:
            majorComponent = .month
            stepComponent = .weekOfYear
            stepValue = 1
            labelFmt = TimelineDateFormatters.dayMonth
            cursor = cal.startOfWeek(for: domainStart)
        }

        while cursor <= domainEnd {
            let xPx = x(for: cursor)
            // Skip ticks far outside the visible canvas to keep draw time bounded.
            if xPx > -120 && xPx < size.width + 120 {
                let isMajor: Bool = {
                    switch granularity {
                    case .year:    return true
                    case .quarter: return cal.component(.month, from: cursor) == 1
                    case .month:   return cal.component(.month, from: cursor) == 1
                    case .week:    return cal.component(.day, from: cursor) <= 7
                    }
                }()
                let label: String = {
                    switch granularity {
                    case .year:    return labelFmt.string(from: cursor)
                    case .quarter: return labelFmt.string(from: cursor)
                    case .month:
                        // Only label Januarys at month granularity to avoid clutter.
                        if cal.component(.month, from: cursor) == 1 {
                            return labelFmt.string(from: cursor)
                        }
                        return labelFmt.shortMonthSymbols[cal.component(.month, from: cursor) - 1]
                    case .week:    return labelFmt.string(from: cursor)
                    }
                }()
                _ = majorComponent  // silence unused-let; reserved for finer-grained logic
                ticks.append(Tick(date: cursor, x: xPx, label: label, isMajor: isMajor))
            }
            guard let next = cal.date(byAdding: stepComponent, value: stepValue, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }

    // MARK: - Event placement (collision-resolved)

    struct Placement { let event: Event; let x: CGFloat; let y: CGFloat }

    /// Lays each event at its (x, axisY) and bumps overlapping ones up/down
    /// alternately so the Canvas isn't a wall of stacked dots.
    func placements() -> [Placement] {
        let collisionRadius: CGFloat = 14
        let lane: CGFloat = 18
        let baseY = axisY

        let sorted = parsed.sorted { $0.date < $1.date }
        var laneEnd: [CGFloat] = []     // for each lane, the rightmost X consumed
        var laneAssignments: [Int] = []  // 0 = on-axis; ±1, ±2, … = lanes above/below

        for (_, date) in sorted {
            let x = self.x(for: date)
            var placedLane = 0
            // Check axis lane first
            if let last = laneEnd.first, last + collisionRadius < x {
                laneEnd[0] = x
                placedLane = 0
            } else if laneEnd.isEmpty {
                laneEnd = [x]
                placedLane = 0
            } else {
                // Find the first non-conflicting alternate lane (1, -1, 2, -2, …)
                var step = 1
                while true {
                    for sign in [1, -1] {
                        let absLane = step
                        let signedLane = sign * absLane
                        let idx = absLane * 2 - (sign == 1 ? 1 : 0)
                        // Ensure laneEnd is long enough
                        while laneEnd.count <= idx {
                            laneEnd.append(-CGFloat.infinity)
                        }
                        if laneEnd[idx] + collisionRadius < x {
                            laneEnd[idx] = x
                            placedLane = signedLane
                            break
                        }
                    }
                    if placedLane != 0 { break }
                    step += 1
                    if step > 10 { break }   // safety bound
                }
            }
            laneAssignments.append(placedLane)
        }

        var out: [Placement] = []
        for (i, item) in sorted.enumerated() {
            let ln = laneAssignments[i]
            let y = baseY + CGFloat(ln) * lane
            out.append(Placement(event: item.event, x: x(for: item.date), y: y))
        }
        return out
    }

    /// Returns the event whose dot covers the given point, if any.
    func event(at point: CGPoint, hitRadius: CGFloat) -> Event? {
        let placements = placements()
        // Reverse so dots drawn last (visually on top) win the hit test.
        for p in placements.reversed() {
            let dx = p.x - point.x
            let dy = p.y - point.y
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                return p.event
            }
        }
        return nil
    }
}

// MARK: - Calendar conveniences

private extension Calendar {
    func startOfYear(for date: Date) -> Date {
        let comps = dateComponents([.year], from: date)
        return self.date(from: comps) ?? date
    }
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? date
    }
}
