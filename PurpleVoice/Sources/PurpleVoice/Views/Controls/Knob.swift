import SwiftUI

/// A rotary knob bound to an `Optional<Double>` filter parameter, where
/// `nil` means "inherit the profile default" and a set value means
/// "override." The knob always shows a concrete value (the default when
/// the binding is nil); turning it sets the override, and a small reset
/// pill / double-click clears it back to nil.
///
/// Interaction: drag vertically (up = increase, down = decrease),
/// ~150 pt of travel sweeps the full range; values snap to `step`.
/// Double-click resets to the profile default.
///
/// The visual is a 270° arc track with a filled value arc and a pointer
/// — the gap sits at the bottom, min at lower-left, max at lower-right.
struct Knob: View {
    let label: String
    @Binding var value: Double?
    let defaultValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    /// Dimmed + non-interactive when the underlying filter stage is
    /// inactive (e.g. de-esser knob while the de-esser is off).
    var enabled: Bool = true
    /// Formats the readout. Defaults to step-appropriate precision.
    var format: ((Double) -> String)? = nil

    private let diameter: CGFloat = 58
    private let sweep: Double = 270   // degrees of travel

    @State private var dragStart: Double?

    private var effective: Double { value ?? defaultValue }
    private var isOverride: Bool { value != nil }
    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((effective - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            dial
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .gesture(enabled ? dragGesture : nil)
                .onTapGesture(count: 2) { if enabled { value = nil } }
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityValue(readout)
                .accessibilityAdjustableAction { direction in
                    guard enabled else { return }
                    switch direction {
                    case .increment: setSnapped(effective + step)
                    case .decrement: setSnapped(effective - step)
                    @unknown default: break
                    }
                }

            HStack(spacing: 3) {
                Text(readout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isOverride ? .primary : .secondary)
                if isOverride && enabled {
                    Button { value = nil } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to default (\(formatted(defaultValue))\(unitSuffix))")
                }
            }
        }
        .opacity(enabled ? 1 : 0.4)
        .help(enabled ? "Drag to adjust · double-click to reset" : "Inactive for the current settings")
    }

    private var dial: some View {
        ZStack {
            // Track (full 270° arc, gap at bottom).
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Value arc.
            Circle()
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(isOverride ? Color.accentColor : Color.secondary,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Knob body.
            Circle()
                .fill(.background)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                .padding(8)

            // Pointer — points lower-left at min, up at mid, lower-right at max.
            Capsule()
                .fill(isOverride ? Color.accentColor : Color.primary.opacity(0.7))
                .frame(width: 3, height: diameter * 0.26)
                .offset(y: -diameter * 0.20)
                .rotationEffect(.degrees(-sweep / 2 + fraction * sweep))
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if dragStart == nil { dragStart = effective }
                let span = range.upperBound - range.lowerBound
                // 150 pt of vertical travel = full range; up increases.
                let delta = Double(-g.translation.height) / 150.0 * span
                setSnapped((dragStart ?? effective) + delta)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func setSnapped(_ raw: Double) {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        let snapped = (clamped / step).rounded() * step
        value = min(max(snapped, range.lowerBound), range.upperBound)
    }

    private var readout: String { "\(formatted(effective))\(unitSuffix)" }
    private var unitSuffix: String { unit.isEmpty ? "" : " \(unit)" }

    private func formatted(_ v: Double) -> String {
        if let format { return format(v) }
        if step >= 1 { return String(format: "%.0f", v) }
        if step >= 0.1 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}
