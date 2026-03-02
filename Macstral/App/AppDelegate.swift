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
    private var stopCommitTask: Task<Void, Never>?
    private var liveCommitTask: Task<Void, Never>?
    private var sessionBufferedAudioBytes = 0
    private var latestTranscript = ""
    private var isCommitInFlight = false
    private var isFinalCommitRequested = false
    private var dictationStartedAt: TimeInterval = 0
    private var isAudioCaptureActive = false
    private var isFinishingDictation = false
    private let liveCommitIntervalNs: UInt64 = 400_000_000
    private let liveCommitMinimumAudioBytes = 2_400
    private let minimumKeyHoldToStopSeconds: TimeInterval = 0.2

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

        let allGranted = appState.hasMicPermission && appState.hasAccessibilityPermission
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
            self.isCommitInFlight = false
            // Guard against a late handshake arriving after the user cancelled dictation.
            // If dictationStatus is no longer .listening the session is stale; tear it down.
            guard self.appState.dictationStatus == .listening else {
                self.webSocketClient.disconnect()
                return
            }
            // Start audio capture only after the WebSocket handshake has succeeded.
            do {
                try self.audioManager.startCapture()
                self.isAudioCaptureActive = true
                self.dictationStartedAt = ProcessInfo.processInfo.systemUptime
            } catch {
                print("[Dictation] Failed to start audio capture: \(error)")
                self.webSocketClient.disconnect()
                self.appState.dictationStatus = .idle
                self.hudPanel?.hide()
            }
        }

        webSocketClient.onTranscriptDelta = { [weak self] transcript in
            guard let self else { return }
            if !transcript.isEmpty {
                self.latestTranscript = transcript
            }
            self.appState.liveTranscript = self.latestTranscript
        }

        webSocketClient.onTranscriptDone = { [weak self] text in
            guard let self else { return }
            self.isCommitInFlight = false
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.latestTranscript = trimmed
            }
            self.appState.liveTranscript = self.latestTranscript

            if self.appState.dictationStatus == .processing {
                if self.isFinalCommitRequested,
                   self.sessionBufferedAudioBytes > 0,
                   self.requestCommit(force: true) {
                    return
                }
                let finalText = self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                self.appState.finalTranscript = finalText
                if !finalText.isEmpty {
                    self.appState.dictationStatus = .inserting
                    self.textInserter.insertText(finalText)
                }
                self.finishDictation()
            }
        }

        webSocketClient.onError = { [weak self] error in
            print("[WebSocket] Error: \(error.localizedDescription)")
            if self?.appState.dictationStatus != .idle {
                self?.finishDictation()
            }
        }

        webSocketClient.onDisconnect = { [weak self] in
            guard let self else { return }
            guard !self.isFinishingDictation else { return }
            guard self.appState.dictationStatus != .idle else { return }
            self.finishDictation()
        }
    }

    // MARK: - Audio

    private func setupAudioCallback() {
        audioManager.onAudioChunk = { [weak self] data in
            self?.handleAudioChunk(data)
        }
    }

    private func handleAudioChunk(_ data: Data) {
        guard appState.dictationStatus == .listening || appState.dictationStatus == .processing else { return }
        if webSocketClient.sendAudioChunk(data) {
            sessionBufferedAudioBytes += data.count
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
        stopCommitTask?.cancel()
        stopCommitTask = nil
        liveCommitTask?.cancel()
        liveCommitTask = nil
        isCommitInFlight = false
        isFinalCommitRequested = false
        sessionBufferedAudioBytes = 0
        latestTranscript = ""
        dictationStartedAt = 0
        isAudioCaptureActive = false
        isFinishingDictation = false

        if hudPanel == nil {
            hudPanel = DictationHUDPanel(appState: appState)
        }
        hudPanel?.show()

        let serverURL = URL(string: "ws://127.0.0.1:\(port)")!
        webSocketClient.connect(to: serverURL)
        liveCommitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.liveCommitIntervalNs)
                guard self.appState.dictationStatus == .listening else { continue }
                _ = self.requestCommit(force: false)
            }
        }
        // Audio capture is started in onSessionCreated, after the WebSocket handshake completes.
    }

    private func stopDictation() {
        guard appState.dictationStatus == .listening else { return }
        guard isAudioCaptureActive else { return }
        let heldFor = ProcessInfo.processInfo.systemUptime - dictationStartedAt
        if heldFor < minimumKeyHoldToStopSeconds {
            return
        }

        audioManager.stopCapture()
        isAudioCaptureActive = false
        appState.dictationStatus = .processing
        isFinalCommitRequested = true
        liveCommitTask?.cancel()
        liveCommitTask = nil
        stopCommitTask?.cancel()
        stopCommitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard self.appState.dictationStatus == .processing else { return }
            if !self.requestCommit(force: true) {
                self.finishDictation()
            }
        }
    }

    private func finishDictation() {
        guard !isFinishingDictation else { return }
        isFinishingDictation = true
        stopCommitTask?.cancel()
        stopCommitTask = nil
        liveCommitTask?.cancel()
        liveCommitTask = nil
        isCommitInFlight = false
        isFinalCommitRequested = false
        sessionBufferedAudioBytes = 0
        latestTranscript = ""
        dictationStartedAt = 0
        if isAudioCaptureActive {
            audioManager.stopCapture()
            isAudioCaptureActive = false
        }
        appState.dictationStatus = .idle
        webSocketClient.disconnect()
        hudPanel?.hide()
        isFinishingDictation = false
    }

    private func requestCommit(force: Bool) -> Bool {
        guard webSocketClient.hasActiveSession else { return false }
        guard !isCommitInFlight else { return true }
        if !force && sessionBufferedAudioBytes < liveCommitMinimumAudioBytes {
            return true
        }
        if webSocketClient.sendCommit() {
            isCommitInFlight = true
            sessionBufferedAudioBytes = 0
            return true
        }
        return false
    }
}
