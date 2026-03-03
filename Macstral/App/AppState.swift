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

// MARK: - DictationMode

enum DictationMode: String, CaseIterable {
    case normal = "normal"
    case streaming = "streaming"
}

// MARK: - SetupStep

enum SetupStep: Equatable {
    case idle
    case downloadingPython
    case installingDeps
    case downloadingModel
    case launching
    case ready
    case error(String)
}

// MARK: - AppState

@Observable
final class AppState {

    // MARK: Backend

    var backendStatus: BackendStatus = .stopped

    // MARK: Voxtral Setup

    var setupStep: SetupStep = .idle
    var setupProgress: Double = 0.0
    var setupStatusText: String = ""

    // MARK: Dictation

    var dictationStatus: DictationStatus = .idle
    var liveTranscript: String = ""
    var finalTranscript: String = ""

    // MARK: Dictation Mode

    var dictationMode: DictationMode {
        get { DictationMode(rawValue: UserDefaults.standard.string(forKey: "dictationMode") ?? "") ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "dictationMode") }
    }

    // MARK: Permissions & Onboarding

    var isOnboardingNeeded: Bool = true
    var hasMicPermission: Bool = false
    var hasAccessibilityPermission: Bool = false

    var isVoxtralReady: Bool {
        if case .ready = setupStep {
            return true
        }
        return false
    }
}
