import Foundation

// MARK: - TranscriptionLanguage

/// Languages surfaced in the Macstral language picker.
/// Tiers from the voxtral-multilingual-2026-03.md research brief.
enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto   = "auto"
    case en     = "en"
    case ja     = "ja"
    case fr     = "fr"
    case de     = "de"
    case es     = "es"
    case it     = "it"
    case pt     = "pt"
    case zh     = "zh"

    var id: String { rawValue }

    /// Display name shown in the picker.
    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .en:   return "English"
        case .ja:   return "Japanese (Beta)"
        case .fr:   return "French"
        case .de:   return "German"
        case .es:   return "Spanish"
        case .it:   return "Italian"
        case .pt:   return "Portuguese"
        case .zh:   return "Chinese — Mandarin (Beta)"
        }
    }

    /// Flag emoji for visual context.
    var flag: String {
        switch self {
        case .auto: return "🌐"
        case .en:   return "🇺🇸"
        case .ja:   return "🇯🇵"
        case .fr:   return "🇫🇷"
        case .de:   return "🇩🇪"
        case .es:   return "🇪🇸"
        case .it:   return "🇮🇹"
        case .pt:   return "🇧🇷"
        case .zh:   return "🇨🇳"
        }
    }

    /// Whether this language is marked experimental by the research brief.
    var isBeta: Bool {
        switch self {
        case .ja, .zh: return true
        default:       return false
        }
    }

    /// The language code sent to the Python backend, or nil for auto-detect.
    var backendCode: String? {
        self == .auto ? nil : rawValue
    }
}

// MARK: - LanguageSettings

enum LanguageSettings {
    static let key = "preferredLanguage"
    static let defaultLanguage: TranscriptionLanguage = .auto

    // MARK: Convenience accessors (use UserDefaults.standard)

    static var current: TranscriptionLanguage {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    // MARK: Injectable accessors (for unit testing)

    static func load(from defaults: UserDefaults = .standard) -> TranscriptionLanguage {
        guard let raw = defaults.string(forKey: key),
              let lang = TranscriptionLanguage(rawValue: raw) else { return defaultLanguage }
        return lang
    }

    static func save(_ language: TranscriptionLanguage, to defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: key)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
