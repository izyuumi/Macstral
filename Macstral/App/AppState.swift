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
    var audioLevel: Float = 0.0
    var liveTranscript: String = ""
    var finalTranscript: String = ""

    // MARK: Transcript History

    /// Session-scoped transcript history, newest entry first. Capped at 50.
    var transcriptHistory: [String] = []
    private let maxHistoryCount = 50

    /// Prepend a non-empty transcript to history, trimming to the cap.
    func appendToHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcriptHistory.insert(trimmed, at: 0)
        if transcriptHistory.count > maxHistoryCount {
            transcriptHistory = Array(transcriptHistory.prefix(maxHistoryCount))
        }
    }

    func clearHistory() {
        transcriptHistory = []
    }

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
