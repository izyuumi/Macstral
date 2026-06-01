import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Subsystems

    private let appState = AppState()
    private let licenseManager = LicenseManager.shared
    private let backendManager = PythonBackendManager()
    private let audioManager = AudioCaptureManager()
    private let webSocketClient = WebSocketClient()
    private let hotkeyManager = HotkeyManager()
    private let textInserter = AccessibilityTextInserter()
    private let transcriptHistory = TranscriptHistory()
    private let audioNotesStore = AudioNotesStore()
    private var audioNotesRecorder: AudioNotesRecorder?
    private var statusBarController: StatusBarController?
    private var hudPanel: DictationHUDPanel?
    private var onboardingWindow: OnboardingWindow?
    private var preferencesWindow: PreferencesWindow?
    private var historyWindow: HistoryWindow?
    private var audioNotesWindow: AudioNotesWindow?
    private var setupTask: Task<Void, Never>?
    private var stopCommitTask: Task<Void, Never>?
    private var liveCommitTask: Task<Void, Never>?
    private var sessionBufferedAudioBytes = 0
    private var latestTranscript = ""
    private var dictationTargetAppBundleIdentifier = "unknown"
    private var isCommitInFlight = false
    private var isFinalCommitRequested = false
    private var dictationStartedAt: TimeInterval = 0
    private var isAudioCaptureActive = false
    private var isFinishingDictation = false
    private var pendingAudioChunks: [Data] = []
    private var pendingAudioBytes = 0
    private let pendingAudioBufferLimitBytes = 512_000
    private let liveCommitIntervalNs: UInt64 = 400_000_000
    private let liveCommitMinimumAudioBytes = 2_400
    private let minimumKeyHoldToStopSeconds: TimeInterval = 0.2
    private var hotkeyDownAt: TimeInterval?
    private var wsOpenAt: TimeInterval?
    private var firstAudioSentAt: TimeInterval?
    private var firstDeltaAt: TimeInterval?
    private var stopRequestedAt: TimeInterval?
    private var commitSentAt: TimeInterval?
    private var startupLagSamples: [Double] = []
    private var wsHandshakeSamples: [Double] = []
    private var wsOpenToFirstAudioSamples: [Double] = []
    private var firstAudioToFirstDeltaSamples: [Double] = []
    private var stopToDoneSamples: [Double] = []
    private var commitToDoneSamples: [Double] = []
    private let debugTranscriptionLogging = (ProcessInfo.processInfo.environment["MACSTRAL_DEBUG_TRANSCRIPTION"] ?? "").lowercased() == "1"

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        setupPreferences()
        setupAudioNotes()
        setupBackendCallbacks()
        setupWebSocketCallbacks()
        setupAudioCallback()
        setupHotkey()

        checkPermissions()

        // Re-validate the Pro license in the background; cold-start state is already
        // resolved synchronously from Keychain by LicenseManager.init.
        Task { [licenseManager] in await licenseManager.validate() }

        if appState.isOnboardingNeeded {
            showOnboarding()
        } else {
            startVoxtralSetup()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        setupTask?.cancel()
        webSocketClient.disconnect()
        hotkeyManager.teardown()
        backendManager.stop()
    }

    // MARK: - Feature Gating

    /// The language code sent to the backend. All languages run on-device and are Free, so the
    /// user's choice is sent through unchanged.
    private var effectiveLanguageCode: String? {
        LanguageSettings.current.backendCode
    }

    // MARK: - Processing Endpoint (on-device vs. cloud)

    /// Set once a cloud connection attempt fails, pinning the rest of this app session to the
    /// on-device path so dictation keeps working offline. Cleared only on relaunch.
    private var cloudConnectionDisabled = false
    /// Whether the in-flight persistent connection was opened against the cloud proxy.
    private var attemptedCloudConnect = false

    /// Resolves which transcription endpoint dictation should use, honoring the Pro gate, the
    /// user's selected mode, whether a proxy is configured, and any earlier cloud failure.
    private var dictationEndpoint: ProcessingEndpoint? {
        ProcessingEndpoint.resolve(
            isPro: licenseManager.isPro,
            mode: cloudConnectionDisabled ? .onDevice : ProcessingModeSettings.current,
            cloudConfigured: MacstralCloudConfig.isConfigured,
            authToken: licenseManager.cloudAuthToken,
            localPort: backendManager.serverPort
        )
    }

    /// Opens the persistent transcription socket if it isn't already connected, choosing the
    /// cloud proxy or the local server per `dictationEndpoint`.
    private func connectDictationSocketIfNeeded() {
        guard !webSocketClient.hasActiveConnection else { return }
        switch dictationEndpoint {
        case .cloud(let token):
            attemptedCloudConnect = true
            print("[WebSocket] Connecting to Macstral cloud proxy…")
            webSocketClient.connect(to: MacstralCloudConfig.streamURL, authToken: token)
        case .onDevice(let port):
            attemptedCloudConnect = false
            webSocketClient.connect(to: URL(string: "ws://127.0.0.1:\(port)")!)
        case nil:
            break
        }
    }

    /// If a cloud connection attempt failed before the handshake completed, disable cloud for the
    /// rest of the session and reconnect on-device so the user is never left without dictation.
    private func handlePossibleCloudConnectionFailure() {
        guard attemptedCloudConnect,
              !cloudConnectionDisabled,
              !webSocketClient.hasActiveConnection else { return }
        cloudConnectionDisabled = true
        attemptedCloudConnect = false
        print("[WebSocket] Cloud connection failed — falling back to on-device for this session.")
        connectDictationSocketIfNeeded()
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
            // Establish the persistent transcription socket when the backend becomes ready.
            // (The local backend is started even in cloud mode so on-device fallback is available.)
            if status == .ready {
                self.connectDictationSocketIfNeeded()
            }
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
        webSocketClient.onConnected = { [weak self] in
            guard let self else { return }
            print("[WebSocket] Persistent connection established")
            // If dictation is waiting for the connection, start a session now.
            // In normal mode during .listening, skip — audio is still being recorded locally.
            if self.appState.dictationMode == .normal && self.appState.dictationStatus == .listening {
                return
            }
            if self.appState.dictationStatus == .listening || self.appState.dictationStatus == .processing {
                self.webSocketClient.startSession(language: self.effectiveLanguageCode)
            }
        }

        webSocketClient.onSessionCreated = { [weak self] in
            guard let self else { return }
            print("[WebSocket] Session created")
            self.isCommitInFlight = false
            let now = ProcessInfo.processInfo.systemUptime
            self.wsOpenAt = now
            self.recordDurationSample(
                from: self.hotkeyDownAt,
                to: now,
                label: "hotkey->session_ready",
                in: &self.wsHandshakeSamples
            )
            guard self.appState.dictationStatus == .listening || self.appState.dictationStatus == .processing else {
                self.webSocketClient.endSession()
                return
            }
            if !self.flushPendingAudioChunks() {
                self.finishDictation()
                return
            }
            // Normal mode: audio was buffered locally and flushed above.
            // If we're already in .processing, send commit now.
            if self.appState.dictationStatus == .processing && self.isFinalCommitRequested {
                print("[Dictation] onSessionCreated: flushed pending audio, sending commit")
                if !self.requestCommit(force: true) {
                    self.finishDictation()
                }
            }
        }

        webSocketClient.onTranscriptDelta = { [weak self] transcript in
            guard let self else { return }
            if self.debugTranscriptionLogging {
                print("[Dictation] onTranscriptDelta: \"\(transcript.prefix(80))\"")
            }
            if self.firstDeltaAt == nil {
                let now = ProcessInfo.processInfo.systemUptime
                self.firstDeltaAt = now
                self.recordDurationSample(
                    from: self.hotkeyDownAt,
                    to: now,
                    label: "hotkey->first_delta",
                    in: &self.startupLagSamples
                )
                self.recordDurationSample(
                    from: self.firstAudioSentAt,
                    to: now,
                    label: "first_audio_sent->first_delta",
                    in: &self.firstAudioToFirstDeltaSamples
                )
            }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.latestTranscript = trimmed
            }
            // Only update live transcript UI in streaming mode.
            if self.appState.dictationMode == .streaming {
                self.appState.liveTranscript = self.latestTranscript
            }
        }

        webSocketClient.onTranscriptDone = { [weak self] text in
            guard let self else { return }
            self.isCommitInFlight = false
            let now = ProcessInfo.processInfo.systemUptime
            self.recordDurationSample(
                from: self.stopRequestedAt,
                to: now,
                label: "stop->done",
                in: &self.stopToDoneSamples
            )
            self.recordDurationSample(
                from: self.commitSentAt,
                to: now,
                label: "commit->done",
                in: &self.commitToDoneSamples
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if self.debugTranscriptionLogging {
                print("[Dictation] onTranscriptDone: \"\(trimmed.prefix(80))\" status=\(self.appState.dictationStatus) finalCommitReq=\(self.isFinalCommitRequested) bufferedBytes=\(self.sessionBufferedAudioBytes)")
            } else {
                print("[Dictation] onTranscriptDone: status=\(self.appState.dictationStatus) finalCommitReq=\(self.isFinalCommitRequested) bufferedBytes=\(self.sessionBufferedAudioBytes)")
            }
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
                let rawFinal = self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                // Auto-punctuate/format the final transcript. Runs on-device and is Free for
                // everyone. Runs only on the final `done` text, never during streaming (avoids
                // cursor jumps).
                let finalText = TranscriptFormatter.format(rawFinal)
                self.appState.finalTranscript = finalText
                if !finalText.isEmpty {
                    self.transcriptHistory.add(
                        finalText,
                        appBundleIdentifier: self.dictationTargetAppBundleIdentifier
                    )
                    if self.debugTranscriptionLogging {
                        print("[Dictation] Inserting text: \"\(finalText.prefix(80))\"")
                    } else {
                        print("[Dictation] Inserting text (\(finalText.count) chars)")
                    }
                    self.appState.dictationStatus = .inserting
                    self.textInserter.insertText(finalText)
                } else {
                    print("[Dictation] WARNING: finalText is empty, nothing to insert.")
                }
                self.finishDictation()
            } else {
                print("[Dictation] onTranscriptDone ignored: status is \(self.appState.dictationStatus), not .processing")
            }
        }

        webSocketClient.onError = { [weak self] error in
            guard let self else { return }
            print("[WebSocket] Error: \(error.localizedDescription)")
            if self.appState.dictationStatus != .idle {
                self.finishDictation()
            }
            // A pre-handshake failure on the cloud proxy reports via onError (not onDisconnect),
            // so attempt the on-device fallback here.
            self.handlePossibleCloudConnectionFailure()
        }

        webSocketClient.onTimingEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .firstChunkToFirstDelta(let ms):
                self.recordServerTiming(ms: ms, label: "server_first_chunk->first_delta", in: &self.firstAudioToFirstDeltaSamples)
            case .feedAudio(let ms):
                print("[Timing] server feed_audio_ms=\(String(format: "%.1f", ms))")
            case .finalize(let ms):
                print("[Timing] server finalize_ms=\(String(format: "%.1f", ms))")
            }
        }

        webSocketClient.onDisconnect = { [weak self] in
            guard let self else { return }
            print("[WebSocket] onDisconnect: isFinishing=\(self.isFinishingDictation) status=\(self.appState.dictationStatus)")
            if !self.isFinishingDictation, self.appState.dictationStatus != .idle {
                print("[WebSocket] Unexpected disconnect during dictation — finishing")
                self.finishDictation()
            }
            // Reconnect persistent WebSocket if backend is still ready.
            if self.appState.backendStatus == .ready {
                print("[WebSocket] Reconnecting persistent connection...")
                self.connectDictationSocketIfNeeded()
            }
        }
    }

    // MARK: - Audio

    private func setupAudioCallback() {
        audioManager.onAudioChunk = { [weak self] data in
            self?.handleAudioChunk(data)
        }
    }

    private var audioChunkCount = 0
    /// Rolling window of recent RMS levels for smoothed waveform display.
    private var audioLevelHistory: [Float] = []
    private let audioLevelHistoryCapacity = 10
    private func handleAudioChunk(_ data: Data) {
        guard appState.dictationStatus == .listening || appState.dictationStatus == .processing else { return }

        // Compute RMS audio level for waveform visualization
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        let sumOfSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = sqrt(sumOfSquares / Double(max(samples.count, 1)))
        let db = 20 * log10(max(rms, 1) / 32768.0)
        let normalized = Float(max(0, min(1, (db + 50) / 50)))
        audioLevelHistory.append(normalized)
        if audioLevelHistory.count > audioLevelHistoryCapacity {
            audioLevelHistory.removeFirst()
        }
        appState.audioLevel = audioLevelHistory.reduce(0, +) / Float(audioLevelHistory.count)

        if appState.dictationMode == .normal {
            // Normal mode: always buffer locally — audio is sent in bulk when the user stops.
            enqueuePendingAudioChunk(data)
            audioChunkCount += 1
            if debugTranscriptionLogging && (audioChunkCount == 1 || audioChunkCount % 20 == 0) {
                print("[Dictation] Audio chunk #\(audioChunkCount): \(data.count) bytes, pendingBytes=\(pendingAudioBytes)")
            }
            return
        }

        // Streaming mode: send audio in real-time.
        if webSocketClient.sendAudioChunk(data) {
            if firstAudioSentAt == nil {
                let now = ProcessInfo.processInfo.systemUptime
                firstAudioSentAt = now
                recordDurationSample(
                    from: wsOpenAt,
                    to: now,
                    label: "ws_open->first_audio_sent",
                    in: &wsOpenToFirstAudioSamples
                )
            }
            sessionBufferedAudioBytes += data.count
            audioChunkCount += 1
            if debugTranscriptionLogging && (audioChunkCount == 1 || audioChunkCount % 20 == 0) {
                print("[Dictation] Audio chunk #\(audioChunkCount): \(data.count) bytes, total buffered=\(sessionBufferedAudioBytes)")
            }
        } else if (appState.dictationStatus == .listening || appState.dictationStatus == .processing) && !webSocketClient.hasActiveSession {
            // Buffer audio when in .processing state (key released before WS handshake)
            // so that speech captured before the WebSocket opens is not dropped.
            enqueuePendingAudioChunk(data)
        }
    }

    // MARK: - Preferences

    private func setupPreferences() {
        let prefsWindow = PreferencesWindow(transcriptHistory: transcriptHistory, licenseManager: licenseManager)
        prefsWindow.onHotkeyChanged = { [weak self] key, mods in
            self?.hotkeyManager.reconfigure(key: key, modifiers: mods)
        }
        prefsWindow.onModelQualityChanged = { [weak self] newQuality in
            self?.handleModelQualityChange(newQuality)
        }
        preferencesWindow = prefsWindow

        statusBarController?.onPreferencesRequested = { [weak self] in
            self?.preferencesWindow?.show()
        }
        historyWindow = HistoryWindow(history: transcriptHistory)
        statusBarController?.onHistoryRequested = { [weak self] in
            self?.historyWindow?.show()
        }
        statusBarController?.onPasteLastTranscriptionRequested = { [weak self] in
            self?.pasteLastTranscription()
        }
    }

    // MARK: - Audio Notes

    private func setupAudioNotes() {
        let recorder = AudioNotesRecorder(
            appState: appState,
            store: audioNotesStore,
            portProvider: { [weak self] in self?.backendManager.serverPort },
            languageProvider: { [weak self] in self?.effectiveLanguageCode },
            endpointProvider: { [weak self] in self?.dictationEndpoint }
        )
        audioNotesRecorder = recorder

        audioNotesWindow = AudioNotesWindow(
            store: audioNotesStore,
            appState: appState,
            onStartRecording: { [weak self] in self?.audioNotesRecorder?.startRecording() },
            onStopRecording: { [weak self] in self?.audioNotesRecorder?.stopRecording() },
            onRegenerate: { [weak self] note in self?.audioNotesRecorder?.regenerateNotes(for: note) },
            onExport: { [weak self] note in self?.exportAudioNote(note) }
        )

        statusBarController?.onAudioNotesRequested = { [weak self] in
            self?.audioNotesWindow?.show()
        }
        statusBarController?.onToggleAudioRecordingRequested = { [weak self] in
            self?.toggleAudioNotesRecording()
        }

        observeAudioNotesStatus()
    }

    /// Starts or stops the system-audio recording depending on the current state.
    private func toggleAudioNotesRecording() {
        guard let recorder = audioNotesRecorder else { return }
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            guard appState.backendStatus == .ready else {
                appState.audioNotesStatus = .error("Transcription engine isn't ready yet.")
                return
            }
            recorder.startRecording()
        }
    }

    /// Re-arming observer that mirrors the Audio Notes pipeline state into the menu bar.
    private func observeAudioNotesStatus() {
        withObservationTracking {
            _ = appState.audioNotesStatus
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusBarController?.updateAudioNotesStatus(self.appState.audioNotesStatus)
                self.observeAudioNotesStatus()
            }
        }
    }

    /// Copies a note's title, AI notes, and full transcript to the clipboard as Markdown.
    private func exportAudioNote(_ note: AudioNote) {
        var parts = ["# \(note.title)"]
        if !note.notes.isEmpty { parts.append(note.notes) }
        if !note.transcript.isEmpty { parts.append("## Transcript\n\n\(note.transcript)") }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(parts.joined(separator: "\n\n"), forType: .string)
    }

    // MARK: - Model Quality

    private func handleModelQualityChange(_ quality: ModelQuality) {
        // Surface the "Loading model..." state immediately.
        appState.setupStep = .launching
        appState.setupStatusText = "Loading \(quality.displayName) model…"
        webSocketClient.disconnect()
        Task {
            await backendManager.restartForModelSwitch()
            // Re-connect the transcription socket (local server port changed on restart).
            connectDictationSocketIfNeeded()
            appState.setupStep = .ready
        }
    }

    private func pasteLastTranscription() {
        let finalTranscript = appState.finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTranscript.isEmpty else { return }
        textInserter.insertText(finalTranscript)
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
        guard backendManager.serverPort != nil else {
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
        pendingAudioChunks.removeAll(keepingCapacity: false)
        pendingAudioBytes = 0
        hotkeyDownAt = ProcessInfo.processInfo.systemUptime
        dictationTargetAppBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        wsOpenAt = nil
        firstAudioSentAt = nil
        firstDeltaAt = nil
        stopRequestedAt = nil
        commitSentAt = nil

        if hudPanel == nil {
            hudPanel = DictationHUDPanel(appState: appState)
        }
        hudPanel?.show()

        do {
            try audioManager.startCapture()
            isAudioCaptureActive = true
            dictationStartedAt = ProcessInfo.processInfo.systemUptime
        } catch {
            print("[Dictation] Failed to start audio capture: \(error)")
            appState.dictationStatus = .idle
            hudPanel?.hide()
            return
        }

        if appState.dictationMode == .normal {
            // Normal mode: buffer audio locally, defer WS session until stop.
            // Ensure persistent connection is alive for when we need it later.
            connectDictationSocketIfNeeded()
        } else {
            // Streaming mode: start WS session immediately for real-time transcription.
            if webSocketClient.hasActiveConnection {
                webSocketClient.startSession(language: self.effectiveLanguageCode)
            } else {
                connectDictationSocketIfNeeded()
                // onConnected callback will call startSession() once the handshake completes.
            }
        }
    }

    private func stopDictation() {
        // Allow stopping from both .listening and .processing states.
        // In .processing state (e.g. user presses key again), cancel immediately.
        if appState.dictationStatus == .processing {
            print("[Dictation] stopDictation: cancelling from .processing state")
            finishDictation()
            return
        }
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
            print("[Dictation] stopDictation: held too briefly (\(heldFor)s), stopping dictation")
            finishDictation()
            return
        }

        print("[Dictation] stopDictation: stopping audio, bufferedBytes=\(sessionBufferedAudioBytes) pendingBytes=\(pendingAudioBytes) commitInFlight=\(isCommitInFlight)")
        stopRequestedAt = ProcessInfo.processInfo.systemUptime
        audioManager.stopCapture()
        isAudioCaptureActive = false
        appState.dictationStatus = .processing
        isFinalCommitRequested = true
        liveCommitTask?.cancel()
        liveCommitTask = nil

        if appState.dictationMode == .normal {
            // Normal mode: keep HUD visible to show processing state.
            // Start WS session now to flush all buffered audio and commit.
            // The onSessionCreated callback will flush pending chunks and send commit.
            print("[Dictation] stopDictation (normal): starting WS session to flush \(pendingAudioBytes) pending bytes")
            if webSocketClient.hasActiveConnection {
                webSocketClient.startSession(language: self.effectiveLanguageCode)
            } else if dictationEndpoint != nil {
                connectDictationSocketIfNeeded()
                // onConnected → startSession → onSessionCreated → flush + commit
            } else {
                print("[Dictation] stopDictation (normal): no connection or endpoint, finishing")
                finishDictation()
            }
        } else {
            // Streaming mode: commit immediately — audio was already sent in real-time.
            print("[Dictation] stopDictation (streaming): sending commit immediately")
            if !requestCommit(force: true) {
                print("[Dictation] stopDictation: requestCommit failed, finishing dictation")
                finishDictation()
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
        dictationTargetAppBundleIdentifier = "unknown"
        dictationStartedAt = 0
        pendingAudioChunks.removeAll(keepingCapacity: false)
        pendingAudioBytes = 0
        hotkeyDownAt = nil
        wsOpenAt = nil
        firstAudioSentAt = nil
        firstDeltaAt = nil
        stopRequestedAt = nil
        commitSentAt = nil
        if isAudioCaptureActive {
            audioManager.stopCapture()
            isAudioCaptureActive = false
        }
        appState.audioLevel = 0
        audioLevelHistory.removeAll(keepingCapacity: true)
        appState.dictationStatus = .idle
        webSocketClient.endSession()
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
            commitSentAt = ProcessInfo.processInfo.systemUptime
            sessionBufferedAudioBytes = 0
            return true
        }
        print("[Dictation] requestCommit(force=\(force)): sendCommit() failed")
        return false
    }

    private func enqueuePendingAudioChunk(_ data: Data) {
        pendingAudioChunks.append(data)
        pendingAudioBytes += data.count
        // In streaming mode, cap the buffer to prevent unbounded growth during WS handshake.
        // In normal mode, keep all audio — the entire recording is sent at once.
        if appState.dictationMode == .streaming {
            while pendingAudioBytes > pendingAudioBufferLimitBytes, !pendingAudioChunks.isEmpty {
                let removed = pendingAudioChunks.removeFirst()
                pendingAudioBytes -= removed.count
            }
        }
    }

    private func flushPendingAudioChunks() -> Bool {
        guard !pendingAudioChunks.isEmpty else { return true }
        for chunk in pendingAudioChunks {
            if !webSocketClient.sendAudioChunk(chunk) {
                print("[Dictation] Failed to flush pending audio chunk")
                pendingAudioChunks.removeAll(keepingCapacity: false)
                pendingAudioBytes = 0
                return false
            }
            if firstAudioSentAt == nil {
                let now = ProcessInfo.processInfo.systemUptime
                firstAudioSentAt = now
                recordDurationSample(
                    from: wsOpenAt,
                    to: now,
                    label: "ws_open->first_audio_sent",
                    in: &wsOpenToFirstAudioSamples
                )
            }
            sessionBufferedAudioBytes += chunk.count
            audioChunkCount += 1
        }
        pendingAudioChunks.removeAll(keepingCapacity: false)
        pendingAudioBytes = 0
        return true
    }

    private func recordDurationSample(from start: TimeInterval?, to end: TimeInterval, label: String, in samples: inout [Double]) {
        guard let start else { return }
        let ms = max(0, (end - start) * 1000.0)
        recordSample(ms: ms, label: label, in: &samples)
    }

    private func recordServerTiming(ms: Double, label: String, in samples: inout [Double]) {
        recordSample(ms: max(0, ms), label: label, in: &samples)
    }

    private func recordSample(ms: Double, label: String, in samples: inout [Double]) {
        samples.append(ms)
        if samples.count > 20 {
            samples.removeFirst(samples.count - 20)
        }
        let median = percentile(samples, percentile: 0.5)
        let p95 = percentile(samples, percentile: 0.95)
        print("[Timing] \(label): latest=\(String(format: "%.1f", ms))ms median=\(String(format: "%.1f", median))ms p95=\(String(format: "%.1f", p95))ms n=\(samples.count)")
    }

    private func percentile(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let clamped = min(max(percentile, 0), 1)
        let index = Int(round(Double(sorted.count - 1) * clamped))
        return sorted[index]
    }
}
