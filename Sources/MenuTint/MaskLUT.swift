import Foundation

/// Builds the 3D lookup table (for `CIColorCubeWithColorSpace`) that decides how
/// strongly each captured menu bar pixel is recoloured.
///
/// Bright, unsaturated pixels (white/light-grey icons and text) get a weight
/// close to 1; dark or colourful pixels (background, wallpaper, coloured icons)
/// get 0 and are left untouched.
enum MaskLUT {
    static let dimension = 32

    static func make(threshold: Double, intensity: Double) -> Data {
        let n = dimension
        let upper = Float(threshold)
        let lower = max(0, upper - 0.15)
        let strength = Float(min(max(intensity, 0), 1))
        let step = 1 / Float(n - 1)

        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        // Core Image expects red to vary fastest, then green, then blue.
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rf = Float(r) * step
                    let gf = Float(g) * step
                    let bf = Float(b) * step
                    let luminance = 0.2126 * rf + 0.7152 * gf + 0.0722 * bf
                    let saturation = max(rf, gf, bf) - min(rf, gf, bf)
                    let weight = smoothstep(lower, upper, luminance)
                        * (1 - smoothstep(0.10, 0.30, saturation))
                        * strength
                    // The cube's output is converted from sRGB back to Core Image's
                    // linear working space, so pre-encode the weight to keep it linear.
                    let value = linearToSRGB(weight)
                    cube[i] = value
                    cube[i + 1] = value
                    cube[i + 2] = value
                    cube[i + 3] = 1
                    i += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func linearToSRGB(_ value: Float) -> Float {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}
