import AppKit

/// Colour sets for the flowing rainbow.
enum RainbowStyle: String, CaseIterable {
    case classic
    case pastel
    case deep
    case neon
    case sunset
    case ocean
    case forest
    case fire
    case aurora
    case candy

    var title: String {
        switch self {
        case .classic: return "Klasik"
        case .pastel: return "Pastel (açık tonlar)"
        case .deep: return "Derin (koyu tonlar)"
        case .neon: return "Neon"
        case .sunset: return "Gün Batımı"
        case .ocean: return "Okyanus"
        case .forest: return "Orman"
        case .fire: return "Ateş"
        case .aurora: return "Kutup Işıkları"
        case .candy: return "Şeker"
        }
    }

    /// One full cycle of colours; the cycle wraps back to its first colour.
    var cycle: [NSColor] {
        switch self {
        case .classic: return Self.hues(saturation: 0.75, brightness: 1)
        case .pastel: return Self.hues(saturation: 0.35, brightness: 1)
        case .deep: return Self.hues(saturation: 0.95, brightness: 0.65)
        case .neon: return Self.hues(saturation: 1, brightness: 1)
        case .sunset: return Self.colors("#FF9500", "#FF5E3A", "#FF2D55", "#C643FC")
        case .ocean: return Self.colors("#34E0D0", "#00C6FF", "#0072FF", "#5856D6")
        case .forest: return Self.colors("#A8E063", "#34C759", "#0B8A3E", "#6BCB77")
        case .fire: return Self.colors("#FFD60A", "#FF9500", "#FF3B30", "#FF6B00")
        case .aurora: return Self.colors("#00F5A0", "#00D9F5", "#7B61FF", "#C86DD7")
        case .candy: return Self.colors("#FF77E9", "#FFD3F2", "#7AF0FF", "#B28DFF")
        }
    }

    /// Gradient stops for two seamless cycles (the overlay shifts by one cycle).
    var gradientColors: [CGColor] {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = cycle + cycle + [cycle[0]]
        return colors.map { color in
            let rgb = color.usingColorSpace(.sRGB) ?? .white
            return CGColor(colorSpace: sRGB, components: [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, 1])!
        }
    }

    private static func hues(saturation: CGFloat, brightness: CGFloat) -> [NSColor] {
        (0..<12).map { NSColor(hue: CGFloat($0) / 12, saturation: saturation, brightness: brightness, alpha: 1) }
    }

    private static func colors(_ hexes: String...) -> [NSColor] {
        hexes.map { NSColor(hex: $0) ?? .white }
    }
}
