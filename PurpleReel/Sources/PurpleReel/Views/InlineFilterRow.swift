import SwiftUI

/// One row of Kyno's full-width inline filter UI. Edits a single
/// `FilterCriterion` in place — operator dropdown + value editor +
/// unit dropdown + remove (⊖) button. Only the criteria with
/// "continuous" values (Duration / Size / Rating) render as inline
/// rows; discrete criteria (codec, resolution preset, tag, folder,
/// online status) stay as compact pills in the legacy bar.
///
/// Wiring: the row reads its current criterion from `criterion`,
/// rebuilds a new one whenever the user edits a control, and calls
/// `onReplace(new)` so AppState can swap it in-place via
/// `replaceFilter(_:with:)`.
struct InlineFilterRow: View {
    let criterion: FilterCriterion
    let onReplace: (FilterCriterion) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch criterion {
            case .durationAtLeastSeconds, .durationAtMostSeconds:
                durationRow
            case .sizeAtLeastMB, .sizeAtMostMB:
                sizeRow
            case .ratingAtLeast(let n):
                ratingRow(stars: n)
            default:
                // Discrete criterion — fall back to the legacy pill
                // shape so the row still shows the label and supports
                // removal. Inline editing for discrete criteria would
                // require a unique picker per case; not worth the
                // surface area today.
                pillFallback
            }
            Spacer()
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("Remove this filter")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Duration

    @ViewBuilder
    private var durationRow: some View {
        let (currentSeconds, isAtLeast): (Double, Bool) = {
            switch criterion {
            case .durationAtLeastSeconds(let s): return (s, true)
            case .durationAtMostSeconds(let s):  return (s, false)
            default:                              return (0, true)
            }
        }()
        Text("Duration")
            .frame(width: 70, alignment: .leading)
            .foregroundStyle(.secondary)
        Picker("", selection: Binding<Bool>(
            get: { isAtLeast },
            set: { newAtLeast in
                onReplace(newAtLeast
                          ? .durationAtLeastSeconds(currentSeconds)
                          : .durationAtMostSeconds(currentSeconds))
            }
        )) {
            Text("is at least").tag(true)
            Text("is at most").tag(false)
        }
        .labelsHidden()
        .frame(width: 120)
        TextField("", text: Binding<String>(
            get: { formatHHMMSS(currentSeconds) },
            set: { newText in
                let secs = parseHHMMSS(newText) ?? currentSeconds
                onReplace(isAtLeast
                          ? .durationAtLeastSeconds(secs)
                          : .durationAtMostSeconds(secs))
            }
        ))
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
        .frame(width: 100)
        Text("hh:mm:ss").foregroundStyle(.secondary)
    }

    // MARK: - Size

    @ViewBuilder
    private var sizeRow: some View {
        let (currentMB, isAtLeast): (Int, Bool) = {
            switch criterion {
            case .sizeAtLeastMB(let mb): return (mb, true)
            case .sizeAtMostMB(let mb):  return (mb, false)
            default:                      return (0, true)
            }
        }()
        Text("Size")
            .frame(width: 70, alignment: .leading)
            .foregroundStyle(.secondary)
        Picker("", selection: Binding<Bool>(
            get: { isAtLeast },
            set: { newAtLeast in
                onReplace(newAtLeast
                          ? .sizeAtLeastMB(currentMB)
                          : .sizeAtMostMB(currentMB))
            }
        )) {
            Text("is greater than").tag(true)
            Text("is less than").tag(false)
        }
        .labelsHidden()
        .frame(width: 140)
        TextField("", value: Binding<Int>(
            get: { currentMB },
            set: { newMB in
                onReplace(isAtLeast
                          ? .sizeAtLeastMB(newMB)
                          : .sizeAtMostMB(newMB))
            }
        ), format: .number)
        .textFieldStyle(.roundedBorder)
        .frame(width: 100)
        Picker("", selection: Binding<Unit>(
            get: { currentMB >= 1024 && currentMB % 1024 == 0 ? .gb : .mb },
            set: { newUnit in
                let normalized = newUnit == .gb
                    ? max(1, currentMB / 1024) * 1024
                    : currentMB
                onReplace(isAtLeast
                          ? .sizeAtLeastMB(normalized)
                          : .sizeAtMostMB(normalized))
            }
        )) {
            Text("MB").tag(Unit.mb)
            Text("GB").tag(Unit.gb)
        }
        .labelsHidden()
        .frame(width: 70)
    }

    private enum Unit: Hashable { case mb, gb }

    // MARK: - Rating

    @ViewBuilder
    private func ratingRow(stars: Int) -> some View {
        Text("Rating")
            .frame(width: 70, alignment: .leading)
            .foregroundStyle(.secondary)
        Text("is at least")
            .frame(width: 120, alignment: .leading)
            .foregroundStyle(.secondary)
        Stepper(value: Binding<Int>(
            get: { stars },
            set: { onReplace(.ratingAtLeast(max(1, min(5, $0)))) }
        ), in: 1...5) {
            Text(String(repeating: "★", count: stars))
                .foregroundStyle(.yellow)
        }
        .frame(width: 160)
    }

    // MARK: - Fallback pill for discrete criteria

    @ViewBuilder
    private var pillFallback: some View {
        Text(criterion.displayLabel)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.20), in: Capsule())
    }

    // MARK: - Time formatting

    /// Format seconds as "HH:MM:SS". Used for the editable Duration
    /// field. Always emits the hours block so the input shape stays
    /// stable while the user edits.
    private func formatHHMMSS(_ s: Double) -> String {
        let total = max(0, Int(s.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    /// Parse "H:MM:SS" / "MM:SS" / "SS" into seconds. Accepts shorter
    /// forms because typing "120" should produce 120 seconds, not
    /// "00:01:20" (which can be inferred by the formatter on the
    /// next render).
    private func parseHHMMSS(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":").map(String.init)
        switch parts.count {
        case 3:
            guard let h = Int(parts[0]), let m = Int(parts[1]),
                  let s = Int(parts[2]) else { return nil }
            return Double(h * 3600 + m * 60 + s)
        case 2:
            guard let m = Int(parts[0]), let s = Int(parts[1]) else { return nil }
            return Double(m * 60 + s)
        case 1:
            guard let s = Int(parts[0]) else { return nil }
            return Double(s)
        default:
            return nil
        }
    }
}
