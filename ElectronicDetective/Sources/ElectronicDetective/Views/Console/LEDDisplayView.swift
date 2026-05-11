import SwiftUI

/// 8-character LED readout. Renders a monospaced uppercase string against a
/// dark recessed panel with a warm red glow. The full 14-segment look lands
/// in M3 once the segment font is dropped into `Resources/Fonts/`.
struct LEDDisplayView: View {
    let line: LEDLine

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.10, green: 0.04, blue: 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.30, green: 0.15, blue: 0.10), lineWidth: 2)
                )
                .frame(height: 70)
            Text(displayString)
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .tracking(6)
                .foregroundStyle(glowColor)
                .shadow(color: glowColor.opacity(0.7), radius: 6)
                .shadow(color: glowColor.opacity(0.35), radius: 14)
        }
    }

    private var displayString: String {
        let raw: String
        switch line {
        case .off:                 raw = ""
        case .ready:               raw = "READY"
        case .prompt(let s):       raw = s
        case .echo(let s):         raw = s
        case .answer(let s):       raw = s
        case .error(let s):        raw = "E:\(s)"
        case .verdict(let ok):     raw = ok ? "SOLVED" : "WRONG"
        }
        return raw.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    private var glowColor: Color {
        switch line {
        case .error, .verdict(false): return Color(red: 1.0, green: 0.35, blue: 0.25)
        case .verdict(true):          return Color(red: 0.55, green: 1.0, blue: 0.55)
        default:                      return Color(red: 1.0, green: 0.35, blue: 0.20)
        }
    }
}
