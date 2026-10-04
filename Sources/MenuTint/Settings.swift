import AppKit

/// User preferences, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let colorHex = "colorHex"
        static let rainbow = "rainbow"
        static let sensitivity = "sensitivity"
        static let intensity = "intensity"
        static let recentColors = "recentColors"
    }

    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// Tint colour as "#RRGGBB" (sRGB).
    var colorHex: String {
        get { defaults.string(forKey: Key.colorHex) ?? "#32ADE6" }
        set { defaults.set(newValue, forKey: Key.colorHex) }
    }

    /// When true, a rainbow gradient is used instead of `colorHex`.
    var rainbow: Bool {
        get { defaults.object(forKey: Key.rainbow) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.rainbow) }
    }

    /// 0...1 — higher values also recolour dimmer (grey) items.
    var sensitivity: Double {
        get { defaults.object(forKey: Key.sensitivity) as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: Key.sensitivity) }
    }

    /// 0...1 — how much of the tint is applied.
    var intensity: Double {
        get { defaults.object(forKey: Key.intensity) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: Key.intensity) }
    }

    /// Custom colours used recently (newest first).
    var recentColors: [String] {
        get { defaults.stringArray(forKey: Key.recentColors) ?? [] }
        set { defaults.set(Array(newValue.prefix(Self.maxRecentColors)), forKey: Key.recentColors) }
    }

    static let maxRecentColors = 12

    func addRecentColor(_ hex: String) {
        var colors = recentColors.filter { $0.caseInsensitiveCompare(hex) != .orderedSame }
        colors.insert(hex.uppercased(), at: 0)
        recentColors = colors
    }

    var color: NSColor {
        NSColor(hex: colorHex) ?? .systemTeal
    }

    /// Whiteness (0...1) below which nothing is recoloured. Higher sensitivity
    /// lowers it so dim grey items are recoloured too.
    var whitenessFloor: Double {
        0.35 * (1 - sensitivity)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        if string.count == 3 {
            // #RGB → #RRGGBB
            string = string.map { "\($0)\($0)" }.joined()
        }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? .white
        func byte(_ component: CGFloat) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
    }
}
