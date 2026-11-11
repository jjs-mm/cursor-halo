import AppKit

enum HaloStyle: String, CaseIterable, Identifiable {
    case ring, disc
    var id: String { rawValue }
    var title: String { self == .ring ? "Ring" : "Soft disc" }
}

enum HaloColor: String, CaseIterable, Identifiable {
    case amber, mint, blue, pink, white
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var nsColor: NSColor {
        switch self {
        case .amber: return NSColor(srgbRed: 1, green: 0.75, blue: 0.18, alpha: 1)
        case .mint: return NSColor(srgbRed: 0.25, green: 0.91, blue: 0.72, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.28, green: 0.67, blue: 1, alpha: 1)
        case .pink: return NSColor(srgbRed: 1, green: 0.39, blue: 0.64, alpha: 1)
        case .white: return .white
        }
    }
}

struct OverlayConfiguration {
    var isEnabled = true
    var style: HaloStyle = .ring
    var color: HaloColor = .amber
    var diameter: CGFloat = 56
    var opacity: CGFloat = 0.85
    var lineWidth: CGFloat = 3
    var showsClicks = true

    var validated: OverlayConfiguration {
        var result = self
        result.diameter = diameter.isFinite ? min(120, max(28, diameter)) : 56
        result.opacity = opacity.isFinite ? min(1, max(0.2, opacity)) : 0.85
        result.lineWidth = lineWidth.isFinite ? min(8, max(1, lineWidth)) : 3
        return result
    }
}
