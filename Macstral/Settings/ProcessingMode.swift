import Foundation

// MARK: - ProcessingMode

/// Where transcription and note generation run.
///
/// - `onDevice`: the local Voxtral/MLX server. The default, fully Free, works offline.
/// - `cloud`: the Macstral-hosted proxy (Pro only). Can be faster or more accurate depending on
///   the Mac. Falls back to on-device automatically on any connection error.
enum ProcessingMode: String, CaseIterable, Identifiable {
    case onDevice = "onDevice"
    case cloud    = "cloud"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: return "On-device"
        case .cloud:    return "Cloud (Pro)"
        }
    }
}

// MARK: - ProcessingModeSettings

enum ProcessingModeSettings {
    static let key = "processingMode"
    static let defaultMode: ProcessingMode = .onDevice

    // MARK: Convenience accessors (use UserDefaults.standard)

    static var current: ProcessingMode {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    // MARK: Injectable accessors (for unit testing)

    static func load(from defaults: UserDefaults = .standard) -> ProcessingMode {
        guard let raw = defaults.string(forKey: key),
              let mode = ProcessingMode(rawValue: raw) else { return defaultMode }
        return mode
    }

    static func save(_ mode: ProcessingMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Endpoint resolution

/// Resolves which processing endpoint to use for a given user/tier/setting combination. Pure and
/// testable: cloud is used only when it is unlocked (Pro), selected, and actually configured.
enum ProcessingEndpoint: Equatable {
    /// Use the local server on the given loopback port.
    case onDevice(port: Int)
    /// Use the Macstral proxy with the given bearer token.
    case cloud(authToken: String)

    /// - Parameters:
    ///   - isPro: whether the user has an active Pro entitlement.
    ///   - mode: the user's selected processing mode.
    ///   - cloudConfigured: whether a real proxy host is configured.
    ///   - authToken: the license key for proxy auth (non-nil only when Pro).
    ///   - localPort: the local server port, if running.
    static func resolve(
        isPro: Bool,
        mode: ProcessingMode,
        cloudConfigured: Bool,
        authToken: String?,
        localPort: Int?
    ) -> ProcessingEndpoint? {
        if mode == .cloud,
           FeatureGate.isCloudProcessingUnlocked(isPro: isPro),
           cloudConfigured,
           let authToken {
            return .cloud(authToken: authToken)
        }
        if let localPort {
            return .onDevice(port: localPort)
        }
        return nil
    }
}
