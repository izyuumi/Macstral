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
    private var setupTask: Task<Void, Never>?

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
            startVoxtralSetup()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        setupTask?.cancel()
        hotkeyManager.teardown()
        backendManager.stop()
    }

    // MARK: - Permissions

    private func checkPermissions() {
        appState.hasMicPermission = PermissionChecker.checkMicrophonePermission()
        appState.hasAccessibilityPermission = PermissionChecker.checkAccessibilityPermission()

        let allGranted = appState.hasMicPermission && appState.hasAccessibilityPermission && appState.isVoxtralReady
        appState.isOnboardingNeeded = !allGranted
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        // Start Voxtral setup immediately during onboarding
        startVoxtralSetup()

        onboardingWindow = OnboardingWindow(
            appState: appState,
            onPermissionStateChanged: { [weak self] in
                self?.checkPermissions()
            },
            onComplete: { [weak self] in
                guard let self else { return }
                self.appState.isOnboardingNeeded = false
                self.onboardingWindow = nil
            }
        )
        onboardingWindow?.show()
    }

    // MARK: - Voxtral Setup

    private func startVoxtralSetup() {
        setupTask?.cancel()
        setupTask = Task { [weak self] in
            guard let self else { return }
            await self.backendManager.prepareAndStart()
        }
    }

    // MARK: - Backend Callbacks

    private func setupBackendCallbacks() {
        backendManager.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.appState.backendStatus = status
            self.statusBarController?.updateStatus(status)
        }

        backendManager.onSetupProgress = { [weak self] step, progress, statusText in
            guard let self else { return }
            self.appState.setupStep = step
            self.appState.setupProgress = progress
            self.appState.setupStatusText = statusText
        }

        backendManager.onLog = { message in
            print(message)
        }
    }

    // MARK: - WebSocket

    private func setupWebSocketCallbacks() {
        webSocketClient.onSessionCreated = { [weak self] in
            guard let self else { return }
            print("[WebSocket] Session created")
            self.appState.dictationStatus = .listening
            // Start audio capture only after the WebSocket handshake has succeeded.
            do {
                try self.audioManager.startCapture()
            } catch {
                print("[Dictation] Failed to start audio capture: \(error)")
                self.webSocketClient.disconnect()
                self.appState.dictationStatus = .idle
                self.hudPanel?.hide()
            }
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
        // Use dictationStatus as the re-entrancy guard. Set it eagerly before connect()
        // so a second hotkey press while the WebSocket handshake is in-flight is ignored.
        guard appState.dictationStatus == .idle else { return }
        guard let port = backendManager.serverPort else {
            print("[Dictation] No server port available.")
            return
        }

        appState.liveTranscript = ""
        appState.finalTranscript = ""
        appState.dictationStatus = .listening

        if hudPanel == nil {
            hudPanel = DictationHUDPanel(appState: appState)
        }
        hudPanel?.show()

        let serverURL = URL(string: "ws://127.0.0.1:\(port)")!
        webSocketClient.connect(to: serverURL)
        // Audio capture is started in onSessionCreated, after the WebSocket handshake completes.
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
