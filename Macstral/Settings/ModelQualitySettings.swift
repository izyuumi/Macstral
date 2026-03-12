import Foundation

// MARK: - ModelQuality

/// The three quality tiers surfaced in the Macstral Preferences.
/// All models are from mlx-community and run fully on-device via MLX.
enum ModelQuality: String, CaseIterable, Identifiable {
    /// mlx-community/granite-4.0-1b-speech-8bit — current default, already downloaded.
    case fast     = "fast"
    /// mlx-community/granite-4.0-1b-speech-8bit — same model, balanced tier alias.
    case balanced = "balanced"
    /// mlx-community/granite-4.0-1b-speech-8bit — same model, accurate tier alias.
    case accurate = "accurate"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast:     return "Fast"
        case .balanced: return "Balanced"
        case .accurate: return "Accurate"
        }
    }

    var sizeLabel: String {
        switch self {
        case .fast:     return "1.0 GB"
        case .balanced: return "1.0 GB"
        case .accurate: return "1.0 GB"
        }
    }

    var modelID: String {
        switch self {
        case .fast:     return "mlx-community/granite-4.0-1b-speech-8bit"
        case .balanced: return "mlx-community/granite-4.0-1b-speech-8bit"
        case .accurate: return "mlx-community/granite-4.0-1b-speech-8bit"
        }
    }

    /// Human-readable download confirmation message for non-fast tiers.
    var downloadConfirmationMessage: String {
        "Switching to \(displayName) quality requires downloading \(sizeLabel) of model weights. "
        + "This happens once and the model is stored in Macstral's Application Support folder. Continue?"
    }

    /// Fast tier is already downloaded as part of initial setup; others require a separate download.
    var requiresDownload: Bool { self != .fast }
}

// MARK: - ModelQualitySettings

enum ModelQualitySettings {
    static let key = "modelQuality"
    static let defaultQuality: ModelQuality = .fast

    // MARK: Convenience accessors (use UserDefaults.standard)

    static var current: ModelQuality {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    // MARK: Injectable accessors (for unit testing)

    static func load(from defaults: UserDefaults = .standard) -> ModelQuality {
        guard let raw = defaults.string(forKey: key),
              let quality = ModelQuality(rawValue: raw) else { return defaultQuality }
        return quality
    }

    static func save(_ quality: ModelQuality, to defaults: UserDefaults = .standard) {
        defaults.set(quality.rawValue, forKey: key)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
