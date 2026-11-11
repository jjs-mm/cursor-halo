import Foundation
import Testing
@testable import CursorHalo

@Suite
@MainActor
struct SettingsModelTests {
    @Test
    func missingOrWrongTypePreferencesUseDefaultsWithoutWriting() {
        let store = MemorySettingsStore(values: [
            "enabled": "false", "showsClicks": 0, "diameter": "90",
            "opacity": true, "lineWidth": [2], "style": "unsupported",
            "color": 5, "shortcut": false
        ])
        let model = SettingsModel(defaults: store)
        #expect(model.isEnabled)
        #expect(model.showsClicks)
        #expect(model.diameter == 56)
        #expect(model.opacity == 0.85)
        #expect(model.lineWidth == 3)
        #expect(model.style == .ring)
        #expect(model.color == .amber)
        #expect(model.shortcut == .controlOptionH)
        #expect(store.writeCount == 0)
    }

    @Test
    func existingTypedPreferencesRemainCompatible() {
        let store = MemorySettingsStore(values: [
            "enabled": false, "showsClicks": false, "diameter": 80,
            "opacity": 0.6, "lineWidth": 5.5, "style": "disc",
            "color": "pink", "shortcut": "controlOptionC"
        ])
        let model = SettingsModel(defaults: store)
        #expect(!model.isEnabled)
        #expect(!model.showsClicks)
        #expect(model.diameter == 80)
        #expect(model.opacity == 0.6)
        #expect(model.lineWidth == 5.5)
        #expect(model.style == .disc)
        #expect(model.color == .pink)
        #expect(model.shortcut == .controlOptionC)
    }

    @Test
    func damagedNumbersAreClampedOrReplacedBeforeRendering() {
        let store = MemorySettingsStore(values: [
            "diameter": Double.nan, "opacity": Double.infinity, "lineWidth": -5
        ])
        let model = SettingsModel(defaults: store)
        #expect(model.diameter == 56)
        #expect(model.opacity == 0.85)
        #expect(model.lineWidth == 1)

        model.diameter = 1000
        model.opacity = -.infinity
        model.lineWidth = .nan
        #expect(model.diameter == 120)
        #expect(model.opacity == 0.85)
        #expect(model.lineWidth == 3)
        #expect((store.values["diameter"] as? Double) == 120)
        #expect((store.values["opacity"] as? Double) == 0.85)
        #expect((store.values["lineWidth"] as? Double) == 3)
        #expect(model.configuration.diameter.isFinite)
        #expect(model.configuration.opacity.isFinite)
        #expect(model.configuration.lineWidth.isFinite)
    }

    @Test
    func roundTripAndAppearanceResetPreserveUnrelatedSettings() {
        let store = MemorySettingsStore()
        let model = SettingsModel(defaults: store)
        model.isEnabled = false
        model.shortcut = .controlShiftH
        model.style = .disc
        model.color = .blue
        model.diameter = 100
        model.resetAppearance()

        let restored = SettingsModel(defaults: store)
        #expect(!restored.isEnabled)
        #expect(restored.shortcut == .controlShiftH)
        #expect(restored.style == .ring)
        #expect(restored.color == .amber)
        #expect(restored.diameter == 56)
        #expect(restored.showsClicks)
    }
}

private final class MemorySettingsStore: SettingsStoring {
    var values: [String: Any]
    private(set) var writeCount = 0
    init(values: [String: Any] = [:]) { self.values = values }
    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
        writeCount += 1
    }
}
