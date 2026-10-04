import CoreImage
import Foundation

/// Rebuilds the menu bar with its white items recoloured.
///
/// Two captures of the same strip are used:
/// - `scene`: the menu bar exactly as it looks on screen,
/// - `items`: only the menu bar's own windows, over black.
///
/// A white item drawn with coverage `a` over background `bg` looks like
/// `bg·(1−a) + a`. Subtracting `a·(1 − tint)` gives `bg·(1−a) + a·tint`: the same
/// item in the tint colour, with its anti-aliased edges blended into the real
/// background. The result is opaque around the items so the white originals
/// underneath are fully covered; everywhere else it is transparent.
///
/// Not thread-safe: use it from a single queue.
final class TintRenderer {
    enum Fill {
        case solid(CIColor)
        case rainbow
    }

    var fill: Fill

    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Works in (non-linear) sRGB, the space macOS composites the menu bar in,
    /// so the subtraction above undoes the original blending exactly.
    private lazy var context = CIContext(options: [
        .workingColorSpace: sRGB,
        .cacheIntermediates: false,
    ])
    private let maskFilter = CIFilter(name: "CIColorCubeWithColorSpace")!

    init(maskCube: Data, fill: Fill) {
        self.fill = fill
        maskFilter.setValue(MaskLUT.dimension, forKey: "inputCubeDimension")
        maskFilter.setValue(sRGB, forKey: "inputColorSpace")
        setMaskCube(maskCube)
    }

    func setMaskCube(_ data: Data) {
        maskFilter.setValue(data, forKey: "inputCubeData")
    }

    func render(scene: CIImage, items: CIImage) -> CGImage? {
        let extent = scene.extent

        // a: how white each pixel of the items is (0 = not part of a white item).
        maskFilter.setValue(items, forKey: kCIInputImageKey)
        guard let whiteness = maskFilter.outputImage?.cropped(to: extent) else { return nil }

        let color: CIImage
        switch fill {
        case .solid(let tint):
            color = CIImage(color: tint).cropped(to: extent)
        case .rainbow:
            color = Self.rainbow(covering: extent)
        }

        // a · (1 − tint)
        let delta = color
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: whiteness])
        // scene − a · (1 − tint)
        let recoloured = delta
            .applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: scene])
            .cropped(to: extent)

        // Cover the items (plus a 2 px margin) completely; leave the rest of the bar live.
        let coverMask = whiteness
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 2])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 12, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 12, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 12, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .applyingFilter("CIColorClamp")
            .cropped(to: extent)

        let output = recoloured.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
            kCIInputMaskImageKey: coverMask,
        ])
        return context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: sRGB)
    }

    // MARK: - Rainbow

    private static let rainbowWidth = 256

    private static let rainbowStrip: CIImage = {
        let width = rainbowWidth
        var pixels = [UInt8](repeating: 255, count: width * 4)
        for x in 0..<width {
            // Stop before the hue wraps back to red.
            let (r, g, b) = hsvToRGB(h: 0.85 * Double(x) / Double(width - 1), s: 0.75, v: 1)
            pixels[x * 4] = UInt8((r * 255).rounded())
            pixels[x * 4 + 1] = UInt8((g * 255).rounded())
            pixels[x * 4 + 2] = UInt8((b * 255).rounded())
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
        return CIImage(cgImage: image)
    }()

    private static func rainbow(covering extent: CGRect) -> CIImage {
        rainbowStrip
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(rainbowWidth), y: extent.height))
            .cropped(to: extent)
    }

    private static func hsvToRGB(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let sector = (h * 6).truncatingRemainder(dividingBy: 6)
        let c = v * s
        let x = c * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
