import Foundation

/// SMPTE non-drop timecode helpers. Drop-frame is intentionally not
/// implemented: most non-broadcast NLE work treats 29.97 as 30 for
/// display purposes, and Final Cut Pro shows the same.
enum Timecode {
    static func format(seconds: Double, fps: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00:00:00" }
        let frameRate = max(1, fps.rounded()).clamped(to: 1...120)
        let totalFrames = Int((seconds * frameRate).rounded(.down))
        let f = Int(frameRate)
        let frames = totalFrames % f
        let totalSec = totalFrames / f
        let s = totalSec % 60
        let m = (totalSec / 60) % 60
        let h = totalSec / 3600
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, frames)
    }

    static func frameDuration(fps: Double) -> Double {
        guard fps > 0 else { return 1.0 / 30.0 }
        return 1.0 / fps
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
