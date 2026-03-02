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
            print("[Dictation] onTranscriptDelta: \"\(transcript.prefix(80))\"")
            if !transcript.isEmpty {
                self.latestTranscript = transcript
            }
            self.appState.liveTranscript = self.latestTranscript
        }

        webSocketClient.onTranscriptDone = { [weak self] text in
            guard let self else { return }
            self.isCommitInFlight = false
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[Dictation] onTranscriptDone: \"\(trimmed.prefix(80))\" status=\(self.appState.dictationStatus) finalCommitReq=\(self.isFinalCommitRequested) bufferedBytes=\(self.sessionBufferedAudioBytes)")
            if !trimmed.isEmpty {
                self.latestTranscript = trimmed
            }
            self.appState.liveTranscript = self.latestTranscript

            if self.appState.dictationStatus == .processing {
                if self.isFinalCommitRequested,
                   self.sessionBufferedAudioBytes > 0,
                   self.requestCommit(force: true) {
                    print("[Dictation] Re-committing remaining audio")
                    return
                }
                let finalText = self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                self.appState.finalTranscript = finalText
                if !finalText.isEmpty {
                    print("[Dictation] Inserting text: \"\(finalText.prefix(80))\"")
                    self.appState.dictationStatus = .inserting
                    self.textInserter.insertText(finalText)
                } else {
                    print("[Dictation] WARNING: finalText is empty, nothing to insert. latestTranscript=\"\(self.latestTranscript)\"")
                }
                self.finishDictation()
            } else {
                print("[Dictation] onTranscriptDone ignored: status is \(self.appState.dictationStatus), not .processing")
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
            print("[WebSocket] onDisconnect: isFinishing=\(self.isFinishingDictation) status=\(self.appState.dictationStatus)")
            guard !self.isFinishingDictation else { return }
            guard self.appState.dictationStatus != .idle else { return }
            print("[WebSocket] Unexpected disconnect during dictation — finishing")
            self.finishDictation()
        }
    }

    // MARK: - Audio

    private func setupAudioCallback() {
        audioManager.onAudioChunk = { [weak self] data in
            self?.handleAudioChunk(data)
        }
    }

    private var audioChunkCount = 0
    private func handleAudioChunk(_ data: Data) {
        guard appState.dictationStatus == .listening || appState.dictationStatus == .processing else { return }
        if webSocketClient.sendAudioChunk(data) {
            sessionBufferedAudioBytes += data.count
            audioChunkCount += 1
            if audioChunkCount == 1 || audioChunkCount % 20 == 0 {
                print("[Dictation] Audio chunk #\(audioChunkCount): \(data.count) bytes, total buffered=\(sessionBufferedAudioBytes)")
            }
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
        audioChunkCount = 0

        if hudPanel == nil {
            hudPanel = DictationHUDPanel(appState: appState)
        }
        hudPanel?.show()

        let serverURL = URL(string: "ws://127.0.0.1:\(port)")!
        webSocketClient.connect(to: serverURL)
        // No live commits while listening — transcribe all audio in one shot when
        // the user releases the hotkey.  This avoids paying the ~1.4 s encoder +
        // prefill overhead on every partial commit and lets the model process the
        // full utterance at once, which is significantly faster for the 4B model.
        // Audio capture is started in onSessionCreated, after the WebSocket handshake completes.
    }

    private func stopDictation() {
        guard appState.dictationStatus == .listening else {
            print("[Dictation] stopDictation: ignored, status=\(appState.dictationStatus)")
            return
        }
        guard isAudioCaptureActive else {
            print("[Dictation] stopDictation: ignored, audio capture not active")
            return
        }
        let heldFor = ProcessInfo.processInfo.systemUptime - dictationStartedAt
        if heldFor < minimumKeyHoldToStopSeconds {
            print("[Dictation] stopDictation: ignored, held too briefly (\(heldFor)s)")
            return
        }

        print("[Dictation] stopDictation: stopping audio, bufferedBytes=\(sessionBufferedAudioBytes) commitInFlight=\(isCommitInFlight)")
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
            guard self.appState.dictationStatus == .processing else {
                print("[Dictation] stopCommitTask: status changed to \(self.appState.dictationStatus), skipping")
                return
            }
            print("[Dictation] stopCommitTask: firing after 60ms delay")
            if !self.requestCommit(force: true) {
                print("[Dictation] stopCommitTask: requestCommit failed, finishing dictation")
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
        guard webSocketClient.hasActiveSession else {
            print("[Dictation] requestCommit(force=\(force)): no active session")
            return false
        }
        guard !isCommitInFlight else {
            print("[Dictation] requestCommit(force=\(force)): commit already in flight")
            return true
        }
        if !force && sessionBufferedAudioBytes < liveCommitMinimumAudioBytes {
            return true
        }
        if webSocketClient.sendCommit() {
            print("[Dictation] requestCommit(force=\(force)): sent commit, bufferedBytes=\(sessionBufferedAudioBytes)")
            isCommitInFlight = true
            sessionBufferedAudioBytes = 0
            return true
        }
        print("[Dictation] requestCommit(force=\(force)): sendCommit() failed")
        return false
    }
}
