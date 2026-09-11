import Foundation
import Observation
import DuoCore

/// Everything the person can change, backed by `UserDefaults`.
@MainActor
@Observable
final class Preferences {

    static let shared = Preferences()

    private enum Key {
        static let effect = "effect"
        static let isEnabled = "isEnabled"
        static let focusOnWake = "focusOnWake"
        static let showsAngleInMenuBar = "showsAngleInMenuBar"
        static let checksForUpdates = "checksForUpdates"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let skippedUpdateVersion = "skippedUpdateVersion"
        static let effectSchema = "effectSchema"
        static let all = [effect, isEnabled, focusOnWake, showsAngleInMenuBar, checksForUpdates,
                          hasCompletedOnboarding, lastUpdateCheck, skippedUpdateVersion]
    }

    private let defaults: UserDefaults

    var effect: EffectSettings {
        didSet { save(effect, forKey: Key.effect) }
    }
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }
    /// Un-frost the desktop when the Mac wakes.
    var focusOnWake: Bool {
        didSet { defaults.set(focusOnWake, forKey: Key.focusOnWake) }
    }
    var showsAngleInMenuBar: Bool {
        didSet { defaults.set(showsAngleInMenuBar, forKey: Key.showsAngleInMenuBar) }
    }
    var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Key.checksForUpdates) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }
    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Key.lastUpdateCheck) }
    }
    var skippedUpdateVersion: String? {
        didSet { defaults.set(skippedUpdateVersion, forKey: Key.skippedUpdateVersion) }
    }

    /// The preset the current look equals, or `nil` for a custom look.
    var preset: EffectPreset? { EffectPreset.matching(effect) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.focusOnWake: true,
            Key.showsAngleInMenuBar: false,
            Key.checksForUpdates: true,
            Key.hasCompletedOnboarding: false,
        ])
        // The look was retuned in schema 2 (no sheen or grain, reference
        // geometry); settings saved before that start again from Duo.
        let schema = 4
        if defaults.integer(forKey: Key.effectSchema) < schema {
            defaults.removeObject(forKey: Key.effect)
            defaults.set(schema, forKey: Key.effectSchema)
        }
        effect = Self.load(EffectSettings.self, forKey: Key.effect, from: defaults) ?? .duo
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        focusOnWake = defaults.bool(forKey: Key.focusOnWake)
        showsAngleInMenuBar = defaults.bool(forKey: Key.showsAngleInMenuBar)
        checksForUpdates = defaults.bool(forKey: Key.checksForUpdates)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
        skippedUpdateVersion = defaults.string(forKey: Key.skippedUpdateVersion)
    }

    func apply(_ preset: EffectPreset) {
        effect = preset.settings
    }

    func resetEverything() {
        for key in Key.all { defaults.removeObject(forKey: key) }
        effect = .duo
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        focusOnWake = defaults.bool(forKey: Key.focusOnWake)
        showsAngleInMenuBar = defaults.bool(forKey: Key.showsAngleInMenuBar)
        checksForUpdates = defaults.bool(forKey: Key.checksForUpdates)
        lastUpdateCheck = nil
        skippedUpdateVersion = nil
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
