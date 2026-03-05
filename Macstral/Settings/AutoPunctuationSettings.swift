import Foundation

// MARK: - AutoPunctuationSettings

/// Persists the auto-punctuation toggle preference.
/// On by default — users who want raw output can turn it off in Preferences.
enum AutoPunctuationSettings {
    static let key = "autoPunctuationEnabled"

    static var isEnabled: Bool {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    // MARK: Injectable accessors (for unit testing)

    static func load(from defaults: UserDefaults = .standard) -> Bool {
        // Default is true — if the key has never been written, treat as enabled.
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    static func save(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
