import CoreImage
import Foundation

/// Turns a captured menu bar frame into an overlay image that contains only the
/// recoloured items (everything else is transparent).
///
/// Not thread-safe: use it from a single queue.
final class TintRenderer {
    enum Fill {
        case solid(CIColor)
        case rainbow
    }

    var fill: Fill

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
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

    func render(_ input: CIImage) -> CGImage? {
        let extent = input.extent

        // Greyscale weight map: how much of each pixel gets recoloured.
        maskFilter.setValue(input, forKey: kCIInputImageKey)
        guard let mask = maskFilter.outputImage else { return nil }

        // Keep the original brightness so anti-aliasing and dimmed items survive.
        let luminance = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])

        let color: CIImage
        switch fill {
        case .solid(let tint):
            color = CIImage(color: tint).cropped(to: extent)
        case .rainbow:
            color = Self.rainbow(covering: extent)
        }

        let tinted = color.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: luminance,
        ])
        let output = tinted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
            kCIInputMaskImageKey: mask,
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
