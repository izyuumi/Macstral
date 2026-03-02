import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Subsystems

    private let appState = AppState()
    private let backendManager = PythonBackendManager()
    private let audioManager = AudioCaptureManager()
    private let webSocketClient = WebSocketClient()
    private let hotkeyManager = HotkeyManager()
    private let textInserter = AccessibilityTextInserter()
    private var statusBarController: StatusBarController?
    private var hudPanel: DictationHUDPanel?
    private var onboardingWindow: OnboardingWindow?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        setupBackendCallbacks()
        setupWebSocketCallbacks()
        setupAudioCallback()
        setupHotkey()

        checkPermissions()

        if appState.isOnboardingNeeded {
            showOnboarding()
        } else {
            startBackend()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.teardown()
        backendManager.stop()
    }

    // MARK: - Permissions

    private func checkPermissions() {
        appState.hasMicPermission = PermissionChecker.checkMicrophonePermission()
        appState.hasSpeechPermission = PermissionChecker.checkSpeechPermission()
        appState.hasAccessibilityPermission = PermissionChecker.checkAccessibilityPermission()

        let allGranted = appState.hasMicPermission && appState.hasSpeechPermission && appState.hasAccessibilityPermission
        appState.isOnboardingNeeded = !allGranted
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        onboardingWindow = OnboardingWindow(appState: appState) { [weak self] in
            guard let self else { return }
            self.appState.isOnboardingNeeded = false
            self.onboardingWindow = nil
            self.startBackend()
        }
        onboardingWindow?.show()
    }

    // MARK: - Backend

    private func startBackend() {
        backendManager.start()
        Task {
            await backendManager.waitForReady()
        }
    }

    private func setupBackendCallbacks() {
        backendManager.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.appState.backendStatus = status
            self.statusBarController?.updateStatus(status)
        }
        backendManager.onLog = { message in
            print(message)
        }
    }

    // MARK: - WebSocket

    private func setupWebSocketCallbacks() {
        webSocketClient.onSessionCreated = { [weak self] in
            print("[WebSocket] Session created")
            self?.appState.dictationStatus = .listening
        }

        webSocketClient.onTranscriptDelta = { [weak self] transcript in
            self?.appState.liveTranscript = transcript
        }

        webSocketClient.onTranscriptDone = { [weak self] text in
            guard let self else { return }
            self.appState.finalTranscript = text
            self.appState.dictationStatus = .inserting
            self.textInserter.insertText(text)
            self.finishDictation()
        }

        webSocketClient.onError = { [weak self] error in
            print("[WebSocket] Error: \(error.localizedDescription)")
            if self?.appState.dictationStatus != .idle {
                self?.finishDictation()
            }
        }
    }

    // MARK: - Audio

    private func setupAudioCallback() {
        audioManager.onAudioChunk = { [weak self] data in
            self?.webSocketClient.sendAudioChunk(data)
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onKeyDown = { [weak self] in
            self?.startDictation()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            self?.stopDictation()
        }
        hotkeyManager.setup()
    }

    // MARK: - Dictation Flow

    private func startDictation() {
        guard appState.backendStatus == .ready else {
            print("[Dictation] Backend not ready, ignoring hotkey.")
            return
        }
        guard appState.dictationStatus == .idle else { return }

        appState.liveTranscript = ""
        appState.finalTranscript = ""

        webSocketClient.connect()
        guard webSocketClient.hasActiveSession else { return }

        appState.dictationStatus = .listening

        if hudPanel == nil {
            hudPanel = DictationHUDPanel(appState: appState)
        }
        hudPanel?.show()

        do {
            try audioManager.startCapture()
        } catch {
            print("[Dictation] Failed to start audio capture: \(error)")
            webSocketClient.disconnect()
            appState.dictationStatus = .idle
            hudPanel?.hide()
        }
    }

    private func stopDictation() {
        guard appState.dictationStatus == .listening else { return }

        audioManager.stopCapture()
        appState.dictationStatus = .processing
        webSocketClient.sendCommit()
    }

    private func finishDictation() {
        webSocketClient.disconnect()
        hudPanel?.hide()
        appState.dictationStatus = .idle
    }
}
