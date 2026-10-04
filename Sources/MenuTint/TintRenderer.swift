import CoreImage
import CoreVideo
import Foundation
import IOSurface

/// Splits the menu bar into the two images the overlay needs to show its white
/// items in any colour.
///
/// Two captures of the same strip are used:
/// - `scene`: the menu bar exactly as it looks on screen,
/// - `items`: only the menu bar's own windows, over black.
///
/// A white item drawn with coverage `a` over background `bg` looks like
/// `bg·(1−a) + a`. The overlay shows `(scene − a) + a·colour`, i.e.
/// `bg·(1−a) + a·colour`: the same item in the new colour, with anti-aliased
/// edges blended into the real background. The two terms are produced here:
///
/// - `base` = `scene − a`, opaque around the items (2 px margin) so the white
///   originals underneath are fully covered, transparent everywhere else;
/// - `mask` = `a` as alpha, through which the overlay adds the colour.
///
/// Because the colour is applied by Core Animation, a flowing rainbow costs
/// nothing here: these images only change when the menu bar does.
///
/// App menu titles (Finder, File, Edit…) don't show up in `items` (they are drawn
/// with vibrancy), so for the area left of the status items the whiteness is
/// taken from `scene` instead. The menu bar background is dark there and
/// coloured pixels are ignored, so only the light text is picked up.
///
/// Not thread-safe: use it from a single queue.
final class TintRenderer {
    enum Fill {
        case solid(CGColor)
        /// `speed` 0...1: 0 = still, otherwise the rainbow flows left to right.
        case rainbow(speed: Double)
    }

    struct Output {
        let base: IOSurface
        let mask: IOSurface
    }

    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Works in (non-linear) sRGB, the space macOS composites the menu bar in,
    /// so the subtraction above undoes the original blending exactly.
    private lazy var context = CIContext(options: [
        .workingColorSpace: sRGB,
        .cacheIntermediates: false,
    ])
    private let maskFilter = CIFilter(name: "CIColorCubeWithColorSpace")!

    /// Output surfaces, rendered on the GPU and shown by the overlay as-is (no copy
    /// back to the CPU). Several pairs are rotated so the ones on screen are never
    /// overwritten.
    private var surfaces: [(base: IOSurface, mask: IOSurface)] = []
    private var nextSurface = 0

    init(maskCube: Data) {
        maskFilter.setValue(MaskLUT.dimension, forKey: "inputCubeDimension")
        maskFilter.setValue(sRGB, forKey: "inputColorSpace")
        setMaskCube(maskCube)
    }

    func setMaskCube(_ data: Data) {
        maskFilter.setValue(data, forKey: "inputCubeData")
    }

    /// - Parameter appMenuWidth: width in pixels, from the left edge, of the area
    ///   holding the app menus.
    func render(scene: CIImage, items: CIImage, appMenuWidth: CGFloat) -> Output? {
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

        // scene − a
        let withoutWhite = whiteness
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

        let base = withoutWhite.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
            kCIInputMaskImageKey: coverMask,
        ])

        // Whiteness as (premultiplied) alpha, for the colour layer's mask.
        let mask = whiteness.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 1, y: 0, z: 0, w: 0),
        ])

        guard let target = takeSurfaces(width: Int(extent.width), height: Int(extent.height)) else { return nil }
        context.render(base, to: target.base, bounds: extent, colorSpace: sRGB)
        context.render(mask, to: target.mask, bounds: extent, colorSpace: sRGB)
        return Output(base: target.base, mask: target.mask)
    }

    private func takeSurfaces(width: Int, height: Int) -> (base: IOSurface, mask: IOSurface)? {
        if surfaces.first.map({ $0.base.width != width || $0.base.height != height }) ?? true {
            surfaces = (0..<3).compactMap { _ in
                guard let base = makeSurface(width: width, height: height),
                      let mask = makeSurface(width: width, height: height)
                else { return nil }
                return (base, mask)
            }
            nextSurface = 0
        }
        guard !surfaces.isEmpty else { return nil }
        // Skip any pair the window server is still showing.
        for _ in 0..<surfaces.count {
            let pair = surfaces[nextSurface]
            nextSurface = (nextSurface + 1) % surfaces.count
            if !pair.base.isInUse && !pair.mask.isInUse {
                return pair
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
}
