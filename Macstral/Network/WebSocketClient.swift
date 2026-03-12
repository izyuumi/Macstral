import Foundation

/// Routes audio to the local Voxtral WebSocket inference server.
/// Keeps the same public interface so the rest of the app is unchanged.
@MainActor
class WebSocketClient: NSObject {

    // MARK: - Callbacks

    var onConnected: (() -> Void)?
    var onSessionCreated: (() -> Void)?
    var onTranscriptDelta: ((String) -> Void)?
    var onTranscriptDone: ((String) -> Void)?
    var onTimingEvent: ((ServerTimingEvent) -> Void)?
    var onError: ((Error) -> Void)?
    var onDisconnect: (() -> Void)?

    // MARK: - Private State

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var isAcceptingAudio = false
    private var cumulativeDeltaText = ""

    /// Whether the underlying WebSocket transport is connected.
    var hasActiveConnection: Bool { isConnected }
    /// Whether a dictation session is active and audio can be sent.
    var hasActiveSession: Bool { isConnected && isAcceptingAudio }

    // MARK: - Connection Management

    /// Connects to the Voxtral WebSocket server at the given URL.
    /// `isConnected` and `onSessionCreated` are deferred until the WebSocket handshake succeeds
    /// via `urlSession(_:webSocketTask:didOpenWithProtocol:)`.
    func connect(to url: URL? = nil) {
        guard !isConnected else { return }
        // Guard against duplicate connections: if a task is already in flight, bail out.
        guard self.webSocketTask == nil else { return }
        guard let url else {
            onError?(WebSocketError.noServerURL)
            return
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
        // Do NOT set isConnected here; wait for didOpenWithProtocol to confirm the handshake.
    }

    /// Disconnect and clean up.
    func disconnect() {
        guard isConnected || webSocketTask != nil else { return }
        isConnected = false
        isAcceptingAudio = false
        cumulativeDeltaText = ""
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    // MARK: - Sending Messages

    /// Send raw PCM-16 mono 16 kHz audio data to the server.
    @discardableResult
    func sendAudioChunk(_ data: Data) -> Bool {
        guard isConnected, isAcceptingAudio, let task = webSocketTask else { return false }
        task.send(.data(data)) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.onError?(error)
                }
            }
        }
        return true
    }

    /// Signal end of audio input so the server produces a final transcript.
    @discardableResult
    func sendCommit() -> Bool {
        guard isConnected, let task = webSocketTask else { return false }
        task.send(.string("commit")) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.onError?(error)
                }
            }
        }
        return true
    }

    // MARK: - Session Management (Persistent Connection)

    /// Start a new dictation session on the already-open WebSocket.
    /// Sends "start_session" to the server and immediately marks the client
    /// as ready to accept audio. No round-trip wait is needed because
    /// WebSocket messages are ordered — the server will process start_session
    /// before any subsequent audio chunks.
    func startSession(language: String? = nil) {
        guard isConnected, let task = webSocketTask else { return }
        cumulativeDeltaText = ""
        isAcceptingAudio = true

        // Send a JSON start_session with optional language hint.
        // The server falls back to auto-detect when language is nil or "auto".
        var payload: [String: String] = ["cmd": "start_session"]
        if let lang = language, lang != "auto" {
            payload["language"] = lang
        }
        let message: String
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            message = json
        } else {
            message = "start_session"  // safe fallback
        }

        task.send(.string(message)) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.onError?(error)
                }
            }
        }
        onSessionCreated?()
    }

    /// End the current dictation session without closing the WebSocket.
    func endSession() {
        isAcceptingAudio = false
        cumulativeDeltaText = ""
    }

    // MARK: - Receive Loop

    private func receiveMessages() {
        guard let task = webSocketTask, isConnected else { return }

        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isConnected else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessages()

                case .failure(let error):
                    let wasConnected = self.isConnected
                    self.isConnected = false
                    self.isAcceptingAudio = false
                    self.webSocketTask = nil
                    self.urlSession?.invalidateAndCancel()
                    self.urlSession = nil
                    if wasConnected {
                        self.onError?(error)
                        self.onDisconnect?()
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let result = parseServerMessage(text) else { return }
            switch result {
            case .delta(let transcript, let isIncremental, let firstChunkMs, let feedAudioMs):
                if isIncremental {
                    cumulativeDeltaText += transcript
                    onTranscriptDelta?(cumulativeDeltaText)
                } else {
                    cumulativeDeltaText = transcript
                    onTranscriptDelta?(transcript)
                }
                if let ms = firstChunkMs { onTimingEvent?(.firstChunkToFirstDelta(ms)) }
                if let ms = feedAudioMs  { onTimingEvent?(.feedAudio(ms)) }

            case .done(let transcript, let finalizeMs):
                cumulativeDeltaText = ""
                onTranscriptDone?(transcript)
                if let ms = finalizeMs { onTimingEvent?(.finalize(ms)) }

            case .error(let message):
                onError?(WebSocketError.serverError(message))
            }

        case .data:
            break // Unexpected binary frame; ignore.

        @unknown default:
            break
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketClient: URLSessionWebSocketDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // The WebSocket handshake has completed — the transport is ready.
        // Session creation is deferred to startSession() which sends "start_session".
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Identity check: ignore callbacks from a stale or replaced task.
            guard self.webSocketTask === webSocketTask else { return }
            self.isConnected = true
            self.receiveMessages()
            self.onConnected?()
        }
    }

    /// Handles transport-level failures that occur before the WebSocket handshake completes
    /// (e.g., DNS resolution failure, ECONNREFUSED, TLS error).  `didOpenWithProtocol` is
    /// never called in these cases, so without this delegate method the caller would never
    /// learn that the connection attempt failed.
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return } // nil means the task finished cleanly
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Only act if the handshake never completed (isConnected still false) and the
            // failing task is the one we started.
            guard !self.isConnected,
                  self.webSocketTask === (task as? URLSessionWebSocketTask)
            else { return }
            self.webSocketTask = nil
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
            self.onError?(error)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.webSocketTask === webSocketTask else { return }
            let wasConnected = self.isConnected
            self.isConnected = false
            self.isAcceptingAudio = false
            self.cumulativeDeltaText = ""
            self.webSocketTask = nil
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
            if wasConnected {
                self.onDisconnect?()
            }
        }
    }
}

// MARK: - Errors

enum WebSocketError: LocalizedError {
    case noServerURL
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .noServerURL:
            return "No server URL provided for WebSocket connection."
        case .serverError(let msg):
            return "Server error: \(msg)"
        }
    }
}

enum ServerTimingEvent {
    case firstChunkToFirstDelta(Double)
    case feedAudio(Double)
    case finalize(Double)
}
