import Foundation

// MARK: - AIWritingError

enum AIWritingError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case httpStatus(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an API key in Preferences to use online AI writing."
        case .invalidEndpoint:
            return "The AI writing endpoint URL is invalid."
        case .httpStatus(let status, let body):
            return "AI writing request failed (\(status)): \(body)"
        case .emptyResponse:
            return "The AI writing provider returned an empty response."
        }
    }
}

// MARK: - AIWritingCloudClient

final class AIWritingCloudClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func rewrite(
        request: AIWritingRequest,
        configuration: AIWritingConfiguration,
        apiKey: String
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw AIWritingError.missingAPIKey }

        switch configuration.provider {
        case .openAI:
            return try await rewriteWithOpenAIResponses(
                request: request,
                model: configuration.openAIModel,
                apiKey: trimmedKey
            )
        case .openAICompatible:
            return try await rewriteWithOpenAICompatibleChat(
                request: request,
                baseURL: configuration.compatibleBaseURL,
                model: configuration.compatibleModel,
                apiKey: trimmedKey
            )
        case .local, .formattingOnly:
            throw AIWritingError.invalidEndpoint
        }
    }

    // MARK: - OpenAI Responses API

    private func rewriteWithOpenAIResponses(
        request: AIWritingRequest,
        model: String,
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw AIWritingError.invalidEndpoint
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "instructions": AIWritingPromptBuilder.instructions,
            "input": AIWritingPromptBuilder.input(for: request),
            "max_output_tokens": 900,
        ] as [String: Any])

        let data = try await send(urlRequest)
        guard let text = AIWritingCloudResponseParser.parseOpenAIResponses(data), !text.isEmpty else {
            throw AIWritingError.emptyResponse
        }
        return text
    }

    // MARK: - OpenAI-compatible Chat Completions

    private func rewriteWithOpenAICompatibleChat(
        request: AIWritingRequest,
        baseURL: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        guard let url = Self.endpoint(baseURL: baseURL, path: "chat/completions") else {
            throw AIWritingError.invalidEndpoint
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": AIWritingPromptBuilder.instructions],
                ["role": "user", "content": AIWritingPromptBuilder.input(for: request)],
            ],
            "max_tokens": 900,
        ] as [String: Any])

        let data = try await send(urlRequest)
        guard let text = AIWritingCloudResponseParser.parseChatCompletions(data), !text.isEmpty else {
            throw AIWritingError.emptyResponse
        }
        return text
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIWritingError.httpStatus(http.statusCode, body)
        }
        return data
    }

    private static func endpoint(baseURL: String, path: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }
        let existingPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [existingPath, suffix]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return components.url
    }
}

// MARK: - AIWritingCloudResponseParser

enum AIWritingCloudResponseParser {
    nonisolated static func parseOpenAIResponses(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let outputText = json["output_text"] as? String {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let output = json["output"] as? [[String: Any]] else { return nil }
        let pieces = output.flatMap { item -> [String] in
            guard let content = item["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { part in
                guard let type = part["type"] as? String,
                      type == "output_text" || type == "text"
                else { return nil }
                return part["text"] as? String
            }
        }
        return pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func parseChatCompletions(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
