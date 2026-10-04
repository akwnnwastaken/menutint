import Foundation

/// Builds the 3D lookup table (for `CIColorCubeWithColorSpace`) that turns a
/// captured menu bar pixel into the coverage of the tint colour.
///
/// Only the menu bar's own windows are captured, over a black background, so a
/// white item's anti-aliased pixel is roughly `white * coverage`. The smallest
/// channel is used as the "whiteness": white/grey items have all channels high,
/// coloured icons (battery green, orange dots…) have at least one low channel
/// and are left alone.
enum MaskLUT {
    static let dimension = 32

    static func make(threshold: Double, intensity: Double) -> Data {
        let n = dimension
        let upper = Float(threshold)
        let lower = upper * 0.15
        let strength = Float(min(max(intensity, 0), 1))
        let step = 1 / Float(n - 1)

        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        // Core Image expects red to vary fastest, then green, then blue.
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let whiteness = min(Float(r), Float(g), Float(b)) * step
                    let coverage = smoothstep(lower, upper, whiteness)
                    // Lean towards full coverage so edges don't keep a white fringe.
                    let boosted = 1 - (1 - coverage) * (1 - coverage)
                    let weight = boosted * strength
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
