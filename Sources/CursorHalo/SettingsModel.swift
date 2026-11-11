import AppKit
import Combine
import CoreFoundation

protocol SettingsStoring {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: SettingsStoring {}

enum ToggleShortcut: String, CaseIterable, Identifiable {
    case controlOptionH, controlOptionC, controlShiftH
    var id: String { rawValue }
    var title: String {
        switch self {
        case .controlOptionH: return "⌃ ⌥ H"
        case .controlOptionC: return "⌃ ⌥ C"
        case .controlShiftH: return "⌃ ⇧ H"
        }
    }
}

final class SettingsModel: ObservableObject {
    private let defaults: SettingsStoring
    var onChange: (() -> Void)?
    @Published var isEnabled: Bool { didSet { save() } }
    @Published var style: HaloStyle { didSet { save() } }
    @Published var color: HaloColor { didSet { save() } }
    @Published var diameter: Double {
        didSet {
            let valid = Self.clamp(diameter, to: 28...120, fallback: 56)
            if diameter != valid { diameter = valid }
            save()
        }
    }
    @Published var opacity: Double {
        didSet {
            let valid = Self.clamp(opacity, to: 0.2...1, fallback: 0.85)
            if opacity != valid { opacity = valid }
            save()
        }
    }
    @Published var lineWidth: Double {
        didSet {
            let valid = Self.clamp(lineWidth, to: 1...8, fallback: 3)
            if lineWidth != valid { lineWidth = valid }
            save()
        }
    }
    @Published var showsClicks: Bool { didSet { save() } }
    @Published var shortcut: ToggleShortcut { didSet { save() } }
    @Published var shortcutError: String?
    @Published var monitoringError: String?

    init(defaults: SettingsStoring = UserDefaults.standard) {
        self.defaults = defaults
        isEnabled = Self.boolean(defaults.object(forKey: "enabled"), fallback: true)
        style = HaloStyle(rawValue: defaults.object(forKey: "style") as? String ?? "") ?? .ring
        color = HaloColor(rawValue: defaults.object(forKey: "color") as? String ?? "") ?? .amber
        diameter = Self.number(defaults.object(forKey: "diameter"), range: 28...120, fallback: 56)
        opacity = Self.number(defaults.object(forKey: "opacity"), range: 0.2...1, fallback: 0.85)
        lineWidth = Self.number(defaults.object(forKey: "lineWidth"), range: 1...8, fallback: 3)
        showsClicks = Self.boolean(defaults.object(forKey: "showsClicks"), fallback: true)
        shortcut = ToggleShortcut(rawValue: defaults.object(forKey: "shortcut") as? String ?? "") ?? .controlOptionH
    }

    var configuration: OverlayConfiguration {
        OverlayConfiguration(isEnabled: isEnabled, style: style, color: color,
            diameter: diameter, opacity: opacity, lineWidth: lineWidth, showsClicks: showsClicks)
    }

    func resetAppearance() {
        style = .ring
        color = .amber
        diameter = 56
        opacity = 0.85
        lineWidth = 3
        showsClicks = true
    }

    private func save() {
        defaults.set(isEnabled, forKey: "enabled")
        defaults.set(style.rawValue, forKey: "style")
        defaults.set(color.rawValue, forKey: "color")
        defaults.set(diameter, forKey: "diameter")
        defaults.set(opacity, forKey: "opacity")
        defaults.set(lineWidth, forKey: "lineWidth")
        defaults.set(showsClicks, forKey: "showsClicks")
        defaults.set(shortcut.rawValue, forKey: "shortcut")
        onChange?()
    }

    // UserDefaults' bool/double convenience accessors coerce strings and booleans.
    // Reject wrong types instead of silently turning a damaged preference into 0.
    private static func boolean(_ value: Any?, fallback: Bool) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return fallback }
        return number.boolValue
    }

    private static func number(_ value: Any?, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return fallback }
        return clamp(number.doubleValue, to: range, fallback: fallback)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}
