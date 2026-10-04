import Foundation

/// Builds the 3D lookup table (for `CIColorCubeWithColorSpace`) that turns a pixel
/// of the menu-bar-windows-only capture (items over black) into the item's
/// "whiteness" `a` — for an item of grey level g drawn with coverage c, `a ≈ g·c`.
///
/// The smallest channel is used, so coloured icons (battery green, orange dots…)
/// produce little or no `a` and stay as they are.
enum MaskLUT {
    static let dimension = 32

    /// - Parameters:
    ///   - floor: whiteness below this is ignored (e.g. a faint menu bar backdrop).
    ///   - intensity: 0...1, scales the result.
    static func make(floor: Double, intensity: Double) -> Data {
        let n = dimension
        let floor = Float(min(max(floor, 0), 0.9))
        let strength = Float(min(max(intensity, 0), 1))
        let step = 1 / Float(n - 1)

        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        // Core Image expects red to vary fastest, then green, then blue.
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let whiteness = min(Float(r), Float(g), Float(b)) * step
                    let value = max(0, (whiteness - floor) / (1 - floor)) * strength
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
}
