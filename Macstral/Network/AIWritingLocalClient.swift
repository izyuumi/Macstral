import Foundation

// MARK: - AIWritingLocalClient

/// Sends rewrite requests to the local Voxtral/MLX WebSocket server. This uses a short-lived
/// connection so it does not interfere with the persistent dictation socket.
@MainActor
final class AIWritingLocalClient: NSObject {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    func rewrite(request: AIWritingRequest, port: Int) async throws -> String {
        disconnect()
        guard let url = URL(string: "ws://127.0.0.1:\(port)") else {
            throw AIWritingError.invalidEndpoint
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()

        defer { disconnect() }

        try await send(task, json: [
            "cmd": "rewrite_text",
            "instructions": AIWritingPromptBuilder.instructions,
            "input": AIWritingPromptBuilder.input(for: request),
        ])

        while true {
            let message = try await receiveString(task)
            guard let payload = Self.parseJSON(message),
                  let type = payload["type"] as? String
            else { continue }
            switch type {
            case "rewrite_done":
                return (payload["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            case "error":
                throw AIWritingError.httpStatus(500, payload["text"] as? String ?? "local rewrite failed")
            default:
                continue
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
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
