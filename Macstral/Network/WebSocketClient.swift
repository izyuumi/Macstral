import Foundation

/// Routes audio to the local Voxtral WebSocket inference server.
/// Keeps the same public interface so the rest of the app is unchanged.
@MainActor
class WebSocketClient: NSObject {

    // MARK: - Callbacks

    var onSessionCreated: (() -> Void)?
    var onTranscriptDelta: ((String) -> Void)?
    var onTranscriptDone: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onDisconnect: (() -> Void)?

    // MARK: - Private State

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var isConnecting = false

    var hasActiveSession: Bool { isConnected }

    // MARK: - Connection Management

    /// Connects to the Voxtral WebSocket server at the given URL.
    func connect(to url: URL? = nil) {
        guard !isConnected, !isConnecting else { return }
        guard let url else {
            onError?(WebSocketError.noServerURL)
            return
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        isConnecting = true
        receiveMessages()
    }

    /// Disconnect and clean up.
    func disconnect() {
        guard isConnected || isConnecting || webSocketTask != nil else { return }
        let wasActive = isConnected || isConnecting
        isConnected = false
        isConnecting = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        if wasActive {
            onDisconnect?()
        }
    }

    // MARK: - Sending Messages

    /// Send raw PCM-16 mono 16 kHz audio data to the server.
    func sendAudioChunk(_ data: Data) {
        guard isConnected, let task = webSocketTask else { return }
        task.send(.data(data)) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.onError?(error)
                }
            }
        }
    }

    /// Signal end of audio input so the server produces a final transcript.
    func sendCommit() {
        guard isConnected, let task = webSocketTask else { return }
        task.send(.string("commit")) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.onError?(error)
                }
            }
        }
    }

    // MARK: - Receive Loop

    private func receiveMessages() {
        guard let task = webSocketTask, isConnected || isConnecting else { return }

        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isConnected || self.isConnecting else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessages()

                case .failure(let error):
                    let wasActive = self.isConnected || self.isConnecting
                    self.isConnected = false
                    self.isConnecting = false
                    self.webSocketTask = nil
                    self.urlSession?.invalidateAndCancel()
                    self.urlSession = nil
                    if wasActive {
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
                onTranscriptDelta?(transcript)
            case "done":
                onTranscriptDone?(transcript)
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
        didOpenWithProtocol protocolName: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isConnecting || self.isConnected else { return }
            self.isConnecting = false
            self.isConnected = true
            self.onSessionCreated?()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isConnected || self.isConnecting else { return }
            self.isConnected = false
            self.isConnecting = false
            self.webSocketTask = nil
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
            self.onDisconnect?()
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
