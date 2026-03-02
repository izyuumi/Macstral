import Foundation

/// Routes audio to the local Voxtral WebSocket inference server.
/// Keeps the same public interface so the rest of the app is unchanged.
@MainActor
class WebSocketClient: NSObject {

    // MARK: - Callbacks

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

    var hasActiveSession: Bool { isConnected }

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
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  let transcript = json["text"] as? String
            else { return }

            switch type {
            case "delta":
                let isIncremental = (json["is_incremental"] as? Bool) ?? false
                if isIncremental {
                    cumulativeDeltaText += transcript
                    onTranscriptDelta?(cumulativeDeltaText)
                } else {
                    cumulativeDeltaText = transcript
                    onTranscriptDelta?(transcript)
                }
                if let firstChunkToFirstDeltaMs = json["first_chunk_to_first_delta_ms"] as? Double {
                    onTimingEvent?(.firstChunkToFirstDelta(firstChunkToFirstDeltaMs))
                }
                if let feedAudioMs = json["feed_audio_ms"] as? Double {
                    onTimingEvent?(.feedAudio(feedAudioMs))
                }
            case "done":
                cumulativeDeltaText = ""
                onTranscriptDone?(transcript)
                if let finalizeMs = json["finalize_ms"] as? Double {
                    onTimingEvent?(.finalize(finalizeMs))
                }
            case "error":
                onError?(WebSocketError.serverError(transcript))
            default:
                break
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
        // The WebSocket handshake has completed — now it is safe to mark the session connected.
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Identity check: ignore callbacks from a stale or replaced task.
            guard self.webSocketTask === webSocketTask else { return }
            self.isConnected = true
            self.isAcceptingAudio = true
            self.cumulativeDeltaText = ""
            self.onSessionCreated?()
            self.receiveMessages()
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
