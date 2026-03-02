import Foundation
import Observation

// MARK: - BackendStatus

enum BackendStatus: Equatable {
    case stopped
    case starting
    case ready
    case error(String)
}

// MARK: - DictationStatus

enum DictationStatus: Equatable {
    case idle
    case listening
    case processing
    case inserting
}

enum ModelPreparationStatus: Equatable {
    case unknown
    case checking
    case preparing
    case ready
    case unavailable(String)
}

// MARK: - AppState

@Observable
final class AppState {

    // MARK: Backend

    var backendStatus: BackendStatus = .stopped

    // MARK: Dictation

    var dictationStatus: DictationStatus = .idle
    var liveTranscript: String = ""
    var finalTranscript: String = ""

    // MARK: Permissions & Onboarding

    var isOnboardingNeeded: Bool = true
    var hasMicPermission: Bool = false
    var hasSpeechPermission: Bool = false
    var hasAccessibilityPermission: Bool = false
    var modelPreparationStatus: ModelPreparationStatus = .unknown

    var isModelReadyForUse: Bool {
        if case .ready = modelPreparationStatus {
            return true
        }
        return false
    }
}
