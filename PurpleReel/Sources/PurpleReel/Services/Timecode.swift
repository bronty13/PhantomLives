import Foundation

/// SMPTE timecode helpers. Drop-frame is opt-in via the
/// `useDropFrameTimecode` defaults key (Settings → Advanced); when
/// on AND the fps is a drop-frame family rate (29.97 / 59.94), the
/// formatter drops two frames at every minute boundary except the
/// tenth (the standard SMPTE-12M rule). Otherwise we run as
/// non-drop, which is what Final Cut Pro shows by default.
enum Timecode {
    static func format(seconds: Double, fps: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00:00:00" }
        let dropFrameOn = UserDefaults.standard.bool(forKey: "useDropFrameTimecode")
        let isDropRate = abs(fps - 29.97) < 0.05 || abs(fps - 59.94) < 0.05
        if dropFrameOn && isDropRate {
            return formatDropFrame(seconds: seconds, fps: fps)
        }
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

    /// SMPTE-12M drop-frame for 29.97 (drops 2 frames per minute
    /// except every 10th) and 59.94 (drops 4 per minute except every
    /// 10th). The colon separator changes to `;` between seconds and
    /// frames per industry convention.
    private static func formatDropFrame(seconds: Double, fps: Double) -> String {
        let nominalFps: Int = abs(fps - 59.94) < 0.05 ? 60 : 30
        let dropFramesPerMinute = nominalFps == 60 ? 4 : 2
        let actualFps = Double(nominalFps) * 1000.0 / 1001.0
        // Total real frames (round to nearest to absorb floating-point
        // drift on long durations).
        let totalFrames = Int((seconds * actualFps).rounded())
        let framesPer10Min = nominalFps * 60 * 10 - dropFramesPerMinute * 9
        let framesPerMin = nominalFps * 60 - dropFramesPerMinute
        var f = totalFrames
        let d = f / framesPer10Min
        let m = f % framesPer10Min
        if m > dropFramesPerMinute {
            f = f
                + dropFramesPerMinute * 9 * d
                + dropFramesPerMinute * ((m - dropFramesPerMinute) / framesPerMin)
        } else {
            f = f + dropFramesPerMinute * 9 * d
        }
        let frRate = nominalFps
        let frames = f % frRate
        let secs   = (f / frRate) % 60
        let mins   = (f / (frRate * 60)) % 60
        let hours  = f / (frRate * 3600)
        return String(format: "%02d:%02d:%02d;%02d", hours, mins, secs, frames)
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
