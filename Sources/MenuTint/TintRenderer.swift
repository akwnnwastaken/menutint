import CoreImage
import Foundation
import CoreVideo
import IOSurface

/// Rebuilds the menu bar with its white items recoloured.
///
/// Two captures of the same strip are used:
/// - `scene`: the menu bar exactly as it looks on screen,
/// - `items`: only the menu bar's own windows, over black.
///
/// App menu titles (Finder, File, Edit…) don't show up in `items` (they are drawn
/// with vibrancy), so for the area left of the status items the whiteness is
/// taken from `scene` instead. The menu bar background is dark there and
/// coloured pixels are ignored, so only the light text is picked up.
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
        /// `speed` 0...1: 0 = still, otherwise the rainbow flows left to right.
        case rainbow(speed: Double)
    }

    var fill: Fill
    /// 0..<1 — how far the flowing rainbow has moved (one full cycle = 1).
    var rainbowPhase: CGFloat = 0

    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Works in (non-linear) sRGB, the space macOS composites the menu bar in,
    /// so the subtraction above undoes the original blending exactly.
    private lazy var context = CIContext(options: [
        .workingColorSpace: sRGB,
        .cacheIntermediates: false,
    ])
    private let maskFilter = CIFilter(name: "CIColorCubeWithColorSpace")!

    /// Output surfaces, rendered on the GPU and shown by the overlay layer as-is
    /// (no copy back to the CPU). Several are rotated so the one on screen is
    /// never overwritten.
    private var surfaces: [IOSurface] = []
    private var nextSurface = 0

    init(maskCube: Data, fill: Fill) {
        self.fill = fill
        maskFilter.setValue(MaskLUT.dimension, forKey: "inputCubeDimension")
        maskFilter.setValue(sRGB, forKey: "inputColorSpace")
        setMaskCube(maskCube)
    }

    func setMaskCube(_ data: Data) {
        maskFilter.setValue(data, forKey: "inputCubeData")
    }

    /// - Parameter appMenuWidth: width in pixels, from the left edge, of the area
    ///   holding the app menus.
    func render(scene: CIImage, items: CIImage, appMenuWidth: CGFloat) -> IOSurface? {
        let extent = scene.extent

        // a: how white each pixel of the items is (0 = not part of a white item).
        maskFilter.setValue(items, forKey: kCIInputImageKey)
        guard var whiteness = maskFilter.outputImage?.cropped(to: extent) else { return nil }

        if appMenuWidth > 0 {
            maskFilter.setValue(scene, forKey: kCIInputImageKey)
            if let sceneWhiteness = maskFilter.outputImage {
                // The real background still adds some whiteness here; drop the
                // weakest part so the bar itself isn't recoloured.
                let menuRect = CGRect(x: extent.minX, y: extent.minY, width: min(appMenuWidth, extent.width), height: extent.height)
                let menuWhiteness = sceneWhiteness
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 1.25, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: 1.25, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 1.25, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                        "inputBiasVector": CIVector(x: -0.25, y: -0.25, z: -0.25, w: 0),
                    ])
                    .applyingFilter("CIColorClamp")
                    .cropped(to: menuRect)
                whiteness = menuWhiteness
                    .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: whiteness])
                    .cropped(to: extent)
            }
        }

        let color: CIImage
        switch fill {
        case .solid(let tint):
            color = CIImage(color: tint).cropped(to: extent)
        case .rainbow:
            color = Self.rainbow(covering: extent, phase: rainbowPhase)
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
        guard let surface = takeSurface(width: Int(extent.width), height: Int(extent.height)) else { return nil }
        context.render(output, to: surface, bounds: extent, colorSpace: sRGB)
        return surface
    }

    private func takeSurface(width: Int, height: Int) -> IOSurface? {
        if surfaces.first.map({ $0.width != width || $0.height != height }) ?? true {
            surfaces = (0..<3).compactMap { _ in makeSurface(width: width, height: height) }
            nextSurface = 0
        }
        guard !surfaces.isEmpty else { return nil }
        // Skip any surface the window server is still showing.
        for _ in 0..<surfaces.count {
            let surface = surfaces[nextSurface]
            nextSurface = (nextSurface + 1) % surfaces.count
            if !surface.isInUse {
                return surface
            }
        }
        return nil
    }

    private func makeSurface(width: Int, height: Int) -> IOSurface? {
        guard let surface = IOSurface(properties: [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]) else { return nil }
        if let colorSpace = sRGB.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, colorSpace)
        }
        return surface
    }

    // MARK: - Rainbow

    /// The strip holds two full hue cycles, so it can be shifted by up to one
    /// cycle and still cover the whole bar seamlessly.
    private static let rainbowWidth = 512

    private static let rainbowStrip: CIImage = {
        let width = rainbowWidth
        var pixels = [UInt8](repeating: 255, count: width * 4)
        for x in 0..<width {
            let (r, g, b) = hsvToRGB(h: 2 * (Double(x) + 0.5) / Double(width), s: 0.75, v: 1)
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

    /// One hue cycle spans the bar's width; increasing `phase` moves it to the right.
    private static func rainbow(covering extent: CGRect, phase: CGFloat) -> CIImage {
        let offset = extent.minX + (phase - 1) * extent.width
        return rainbowStrip
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: 2 * extent.width / CGFloat(rainbowWidth), y: extent.height))
            .transformed(by: CGAffineTransform(translationX: offset, y: 0))
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
