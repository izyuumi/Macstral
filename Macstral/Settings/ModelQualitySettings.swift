import Foundation

// MARK: - ModelQuality

/// The three quality tiers surfaced in the Macstral Preferences.
/// All models are from mlx-community and run fully on-device via MLX.
enum ModelQuality: String, CaseIterable, Identifiable {
    /// mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit — current default, already downloaded.
    case fast     = "fast"
    /// mlx-community/Voxtral-Mini-4B-Realtime-6bit — higher accuracy, requires ~1.2 GB extra.
    case balanced = "balanced"
    /// mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16 — best accuracy, requires ~8.4 GB.
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
        case .fast:     return "2.4 GB"
        case .balanced: return "3.6 GB"
        case .accurate: return "8.4 GB"
        }
    }

    var modelID: String {
        switch self {
        case .fast:     return "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"
        case .balanced: return "mlx-community/Voxtral-Mini-4B-Realtime-6bit"
        case .accurate: return "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16"
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
    private static let key = "modelQuality"

    static var current: ModelQuality {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let quality = ModelQuality(rawValue: raw) else { return .fast }
            return quality
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
