import Foundation

/// A dedicated WebSocket client for the Audio Notes feature. It talks to the same local
/// Voxtral/notes server as `WebSocketClient`, but over its own connection and with an
/// async/await request-response shape rather than the streaming-callback shape dictation uses.
///
/// Two operations:
///   • `transcribeSegment` — runs one short audio segment through the streaming ASR session
///     (start_session → audio → commit → done) and returns the finalized text.
///   • `generateNotes` — asks the server's local LLM to turn a transcript into Markdown notes.
@MainActor
final class AudioNotesBackendClient: NSObject {

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    var isConnected: Bool { task != nil }

    // MARK: - Connection

    /// Opens a WebSocket to the local server on `port`. Idempotent.
    func connect(port: Int) {
        guard let url = URL(string: "ws://127.0.0.1:\(port)") else { return }
        connect(with: URLRequest(url: url))
    }

    /// Opens a WebSocket to the Macstral cloud proxy, authenticating with the user's license key.
    /// The proxy speaks the same protocol as the local server. Idempotent.
    func connect(url: URL, authToken: String) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        connect(with: request)
    }

    private func connect(with request: URLRequest) {
        guard task == nil else { return }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Segment transcription

    /// Transcribes one audio segment (raw PCM-16 mono 16 kHz). Returns the finalized text.
    /// Keep segments short (≈10–20 s) so the model's end-of-utterance detection lines up with
    /// our explicit commit and no trailing audio is dropped.
    func transcribeSegment(_ pcm: Data, language: String?) async throws -> String {
        let task = try requireTask()

        var startPayload: [String: String] = ["cmd": "start_session"]
        if let language, language != "auto" { startPayload["language"] = language }
        try await send(task, json: startPayload)

        if !pcm.isEmpty {
            try await task.send(.data(pcm))
        }
        try await task.send(.string("commit"))

        // Wait for the finalized transcript. The server emits zero or more "delta" frames,
        // then exactly one "done".
        while true {
            let message = try await receiveString(task)
            guard let payload = Self.parseJSON(message) else { continue }
            switch payload["type"] as? String {
            case "done":
                return (payload["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            case "error":
                throw AudioNotesBackendError.server(payload["text"] as? String ?? "unknown error")
            default:
                continue // ignore deltas and timing-only frames
            }
        }
    }

    // MARK: - Notes generation

    /// Asks the server's local LLM to produce Markdown notes from `transcript`.
    func generateNotes(transcript: String) async throws -> String {
        let task = try requireTask()
        try await send(task, json: ["cmd": "generate_notes", "transcript": transcript])

        while true {
            let message = try await receiveString(task)
            guard let payload = Self.parseJSON(message) else { continue }
            switch payload["type"] as? String {
            case "notes_done":
                return (payload["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            case "error":
                throw AudioNotesBackendError.server(payload["text"] as? String ?? "unknown error")
            default:
                continue
            }
        }
    }

    // MARK: - Helpers

    private func requireTask() throws -> URLSessionWebSocketTask {
        guard let task else { throw AudioNotesBackendError.notConnected }
        return task
    }

    private func send(_ task: URLSessionWebSocketTask, json: [String: String]) async throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        let string = String(decoding: data, as: UTF8.self)
        try await task.send(.string(string))
    }

    private func receiveString(_ task: URLSessionWebSocketTask) async throws -> String {
        switch try await task.receive() {
        case .string(let text):
            return text
        case .data(let data):
            return String(decoding: data, as: UTF8.self)
        @unknown default:
            return ""
        }
    }

    private static func parseJSON(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}

// MARK: - Errors

enum AudioNotesBackendError: LocalizedError {
    case notConnected
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to the transcription server."
        case .server(let message):
            return "Server error: \(message)"
        }
    }
}
