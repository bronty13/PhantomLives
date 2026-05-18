import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Player-side preview overlays. Both effects are CoreImage filter
/// chains applied via `AVVideoComposition(applyingCIFiltersWithHandler:)`
/// so they never touch the underlying file — transcode output keeps
/// the source pixels verbatim.
///
/// Two overlays are exposed:
/// - **Zebra**: highlights pixels above a brightness threshold with a
///   diagonal yellow stripe pattern. Standard exposure-monitoring tool
///   for camera operators. Threshold is a 0–1 luma value.
/// - **Widescreen matte**: previews how the frame would look cropped to
///   a target display aspect (2.35, 2.39, 2.00, 1.85, 4:3, 1:1) by
///   blacking out the regions that would fall outside the crop.
enum MonitoringEffects {
    /// Build a CIImage from `source` with the requested overlays
    /// composited on top. If neither overlay is active, returns the
    /// input unchanged so the caller can short-circuit.
    static func apply(to source: CIImage,
                        zebraEnabled: Bool,
                        zebraThreshold: Double,
                        matteAspect: Double) -> CIImage {
        var image = source
        if zebraEnabled {
            image = applyZebra(image, threshold: zebraThreshold)
        }
        if matteAspect > 0 {
            image = applyMatte(image, targetAspect: matteAspect)
        }
        return image
    }

    // MARK: - Zebra

    /// Build the zebra overlay by masking a tiled stripe pattern over
    /// the source wherever luma exceeds `threshold`. Uses stock
    /// CIFilters (no custom Metal kernel) so it runs on every Mac
    /// PurpleReel supports without shader compilation friction.
    ///
    /// Pipeline:
    /// 1. `CIColorMatrix` to extract Rec.709 luma into all three
    ///    channels (mono pass).
    /// 2. `CIColorClamp` to threshold luma at the user-set level —
    ///    everything below becomes 0, everything above stays its
    ///    luma value.
    /// 3. Subtract `threshold` then divide by `(1 - threshold)` via
    ///    a second `CIColorMatrix` so any above-threshold pixel maps
    ///    to ≥0 alpha; clamp produces a clean binary mask.
    /// 4. `CIStripesGenerator` for a diagonal stripe pattern.
    /// 5. `CIBlendWithMask` to draw the stripes only where the mask is
    ///    bright. Everything else falls through unchanged.
    private static func applyZebra(_ source: CIImage,
                                    threshold: Double) -> CIImage {
        let extent = source.extent
        let t = max(0.0, min(1.0, threshold))

        // 1. Rec.709 luma into all RGB channels.
        let lumaMatrix = CIFilter.colorMatrix()
        lumaMatrix.inputImage = source
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        lumaMatrix.rVector = luma
        lumaMatrix.gVector = luma
        lumaMatrix.bVector = luma
        lumaMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let luminance = lumaMatrix.outputImage else { return source }

        // 2. Threshold: clamp the bottom of the range so anything
        //    below `t` becomes `t`, then subtract `t` and re-normalize
        //    to 0..1. The result is a mask where 0 = below-threshold,
        //    1 = at/above-threshold.
        let clampMin = CIFilter.colorClamp()
        clampMin.inputImage = luminance
        clampMin.minComponents = CIVector(x: CGFloat(t),
                                            y: CGFloat(t),
                                            z: CGFloat(t),
                                            w: 0)
        clampMin.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        guard let clamped = clampMin.outputImage else { return source }

        let normalize = CIFilter.colorMatrix()
        normalize.inputImage = clamped
        let scale = CGFloat(1.0 / max(0.001, 1.0 - t))
        let bias = CGFloat(-t / max(0.001, 1.0 - t))
        normalize.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        normalize.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        normalize.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        normalize.aVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        normalize.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        guard var mask = normalize.outputImage else { return source }
        mask = mask.cropped(to: extent)

        // 3. Tiled diagonal yellow/black stripes. `CIStripesGenerator`
        //    is horizontal; we rotate 45° around the image center for
        //    the conventional diagonal-zebra look.
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = CIColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        stripes.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        stripes.width = 6
        stripes.sharpness = 1
        stripes.center = CGPoint(x: extent.midX, y: extent.midY)
        guard var stripeImg = stripes.outputImage else { return source }
        // Rotate 45° around the image center for the canonical diagonal
        // zebra pattern (broadcast monitors use this orientation).
        let rotate = CGAffineTransform(translationX: extent.midX,
                                        y: extent.midY)
            .rotated(by: .pi / 4)
            .translatedBy(x: -extent.midX, y: -extent.midY)
        stripeImg = stripeImg.transformed(by: rotate).cropped(to: extent)

        // 4. Composite stripes over the original via the binary mask.
        let blend = CIFilter.blendWithMask()
        blend.inputImage = stripeImg
        blend.backgroundImage = source
        blend.maskImage = mask
        return (blend.outputImage ?? source).cropped(to: extent)
    }

    // MARK: - Widescreen matte

    /// Overlay top/bottom (or left/right) black bars to preview a
    /// crop to `targetAspect`. Doesn't actually crop pixels — the
    /// original frame is preserved underneath, just masked.
    ///
    /// - sourceAspect = W / H
    /// - if sourceAspect < target: source is too tall → letterbox top+bottom
    /// - if sourceAspect > target: source is too wide → pillarbox left+right
    /// - if equal: no-op
    private static func applyMatte(_ source: CIImage,
                                    targetAspect: Double) -> CIImage {
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return source }
        let sourceAspect = Double(extent.width / extent.height)
        let target = max(0.1, targetAspect)

        var result = source
        if abs(sourceAspect - target) < 0.001 {
            return source
        } else if sourceAspect < target {
            // Letterbox. Visible band height = width / target.
            let visibleH = CGFloat(Double(extent.width) / target)
            let barH = (extent.height - visibleH) / 2
            // Top bar.
            result = compositeBlack(over: result,
                                     rect: CGRect(x: extent.minX,
                                                  y: extent.maxY - barH,
                                                  width: extent.width,
                                                  height: barH))
            // Bottom bar.
            result = compositeBlack(over: result,
                                     rect: CGRect(x: extent.minX,
                                                  y: extent.minY,
                                                  width: extent.width,
                                                  height: barH))
        } else {
            // Pillarbox. Visible band width = height * target.
            let visibleW = CGFloat(Double(extent.height) * target)
            let barW = (extent.width - visibleW) / 2
            result = compositeBlack(over: result,
                                     rect: CGRect(x: extent.minX,
                                                  y: extent.minY,
                                                  width: barW,
                                                  height: extent.height))
            result = compositeBlack(over: result,
                                     rect: CGRect(x: extent.maxX - barW,
                                                  y: extent.minY,
                                                  width: barW,
                                                  height: extent.height))
        }
        return result.cropped(to: extent)
    }

    /// Source-over composite a black rectangle at `rect` over `base`.
    /// `CIImage(color:)` returns an infinite-extent solid-color image;
    /// cropping it produces the finite bar we want to overlay.
    private static func compositeBlack(over base: CIImage,
                                        rect: CGRect) -> CIImage {
        guard rect.width > 0, rect.height > 0 else { return base }
        let bar = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: rect)
        let comp = CIFilter.sourceOverCompositing()
        comp.inputImage = bar
        comp.backgroundImage = base
        return comp.outputImage ?? base
    }
}

/// Catalogue of common cinema and broadcast display aspects exposed
/// in the player's widescreen-matte picker. Aspect 0 means "off"; we
/// don't add it here — the UI shows that as a separate option.
enum WidescreenAspect: Double, CaseIterable, Identifiable {
    case anamorphic239 = 2.39
    case scope235      = 2.35
    case univisium200  = 2.00
    case flat185       = 1.85
    case widescreen169 = 1.7777
    case academy137    = 1.37
    case fourThree     = 1.3333
    case square        = 1.0

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .anamorphic239: return "2.39 : 1 (Anamorphic)"
        case .scope235:      return "2.35 : 1 (Scope)"
        case .univisium200:  return "2.00 : 1 (Univisium)"
        case .flat185:       return "1.85 : 1 (Flat)"
        case .widescreen169: return "16 : 9"
        case .academy137:    return "1.37 : 1 (Academy)"
        case .fourThree:     return "4 : 3"
        case .square:        return "1 : 1"
        }
    }
}
