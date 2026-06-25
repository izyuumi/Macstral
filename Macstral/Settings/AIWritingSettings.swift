import Foundation

// MARK: - AIWritingProvider

/// Where Macstral sends the "raw speech → finished writing" step.
///
/// The default is online OpenAI because it gives the best rewrite quality for most users. The
/// local option keeps the offline-first path available, and formatting-only is the deterministic
/// no-LLM fallback.
enum AIWritingProvider: String, CaseIterable, Identifiable {
    case openAI = "openAI"
    case openAICompatible = "openAICompatible"
    case local = "local"
    case formattingOnly = "formattingOnly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:             return "OpenAI"
        case .openAICompatible:   return "OpenAI-compatible"
        case .local:              return "Local LLM"
        case .formattingOnly:     return "Formatting only"
        }
    }

    var detail: String {
        switch self {
        case .openAI:
            return "Uses your OpenAI API key for the highest-quality rewrite layer."
        case .openAICompatible:
            return "Uses your own OpenAI-compatible chat endpoint and API key."
        case .local:
            return "Runs the rewrite layer on this Mac through the bundled local LLM."
        case .formattingOnly:
            return "Uses fast punctuation and capitalization only. No model call."
        }
    }

    var isOnline: Bool {
        switch self {
        case .openAI, .openAICompatible: return true
        case .local, .formattingOnly:    return false
        }
    }
}

// MARK: - AIWritingConfiguration

struct AIWritingConfiguration: Equatable {
    var provider: AIWritingProvider
    var openAIModel: String
    var compatibleBaseURL: String
    var compatibleModel: String
    var fallbackToLocal: Bool

    var activeModel: String {
        switch provider {
        case .openAI:             return openAIModel
        case .openAICompatible:   return compatibleModel
        case .local:              return "local"
        case .formattingOnly:     return "formatting"
        }
    }
}

// MARK: - AIWritingSettings

enum AIWritingSettings {
    static let providerKey = "aiWritingProvider"
    static let openAIModelKey = "aiWritingOpenAIModel"
    static let compatibleBaseURLKey = "aiWritingCompatibleBaseURL"
    static let compatibleModelKey = "aiWritingCompatibleModel"
    static let fallbackToLocalKey = "aiWritingFallbackToLocal"

    static let defaultProvider: AIWritingProvider = .openAI
    static let defaultOpenAIModel = "gpt-5.5"
    static let defaultCompatibleBaseURL = "https://api.openai.com/v1"
    static let defaultCompatibleModel = "gpt-5.5"
    static let defaultFallbackToLocal = true

    static var current: AIWritingConfiguration {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    static func load(from defaults: UserDefaults = .standard) -> AIWritingConfiguration {
        let providerRaw = defaults.string(forKey: providerKey) ?? defaultProvider.rawValue
        let provider = AIWritingProvider(rawValue: providerRaw) ?? defaultProvider
        let openAIModel = nonEmpty(defaults.string(forKey: openAIModelKey), fallback: defaultOpenAIModel)
        let compatibleBaseURL = nonEmpty(defaults.string(forKey: compatibleBaseURLKey), fallback: defaultCompatibleBaseURL)
        let compatibleModel = nonEmpty(defaults.string(forKey: compatibleModelKey), fallback: defaultCompatibleModel)
        let fallbackToLocal: Bool
        if defaults.object(forKey: fallbackToLocalKey) == nil {
            fallbackToLocal = defaultFallbackToLocal
        } else {
            fallbackToLocal = defaults.bool(forKey: fallbackToLocalKey)
        }
        return AIWritingConfiguration(
            provider: provider,
            openAIModel: openAIModel,
            compatibleBaseURL: compatibleBaseURL,
            compatibleModel: compatibleModel,
            fallbackToLocal: fallbackToLocal
        )
    }

    static func save(_ configuration: AIWritingConfiguration, to defaults: UserDefaults = .standard) {
        defaults.set(configuration.provider.rawValue, forKey: providerKey)
        defaults.set(configuration.openAIModel, forKey: openAIModelKey)
        defaults.set(configuration.compatibleBaseURL, forKey: compatibleBaseURLKey)
        defaults.set(configuration.compatibleModel, forKey: compatibleModelKey)
        defaults.set(configuration.fallbackToLocal, forKey: fallbackToLocalKey)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: providerKey)
        defaults.removeObject(forKey: openAIModelKey)
        defaults.removeObject(forKey: compatibleBaseURLKey)
        defaults.removeObject(forKey: compatibleModelKey)
        defaults.removeObject(forKey: fallbackToLocalKey)
    }

    private static func nonEmpty(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
