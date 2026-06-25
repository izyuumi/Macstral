import Foundation

// MARK: - AIWritingResult

struct AIWritingResult: Equatable {
    var text: String
    var task: AIWritingTask
    var providerUsed: AIWritingProvider
    var usedFallback: Bool
}

// MARK: - AIWritingEngine

@MainActor
final class AIWritingEngine {
    private let credentialStore: AIWritingCredentialStoring
    private let cloudClient: AIWritingCloudClient
    private let localClient: AIWritingLocalClient

    init(
        credentialStore: AIWritingCredentialStoring? = nil,
        cloudClient: AIWritingCloudClient? = nil,
        localClient: AIWritingLocalClient? = nil
    ) {
        self.credentialStore = credentialStore ?? KeychainAIWritingCredentialStore.shared
        self.cloudClient = cloudClient ?? AIWritingCloudClient()
        self.localClient = localClient ?? AIWritingLocalClient()
    }

    func process(
        rawTranscript: String,
        context: FocusedTextContext,
        languageCode: String?,
        localPort: Int?
    ) async -> AIWritingResult {
        let task = AIWritingIntentClassifier.classify(rawTranscript: rawTranscript, context: context)
        let request = AIWritingRequest(
            rawTranscript: rawTranscript,
            task: task,
            context: context,
            languageCode: languageCode
        )
        let configuration = AIWritingSettings.current
        let fallback = AIWritingPromptBuilder.fallbackText(for: request)

        switch configuration.provider {
        case .formattingOnly:
            return AIWritingResult(
                text: fallback,
                task: task,
                providerUsed: .formattingOnly,
                usedFallback: false
            )

        case .local:
            if let local = await tryLocalRewrite(request: request, localPort: localPort) {
                return AIWritingResult(text: local, task: task, providerUsed: .local, usedFallback: false)
            }
            return AIWritingResult(text: fallback, task: task, providerUsed: .formattingOnly, usedFallback: true)

        case .openAI, .openAICompatible:
            if let key = credentialStore.loadAPIKey(),
               let online = await tryOnlineRewrite(request: request, configuration: configuration, apiKey: key) {
                return AIWritingResult(text: online, task: task, providerUsed: configuration.provider, usedFallback: false)
            }
            if configuration.fallbackToLocal,
               let local = await tryLocalRewrite(request: request, localPort: localPort) {
                return AIWritingResult(text: local, task: task, providerUsed: .local, usedFallback: true)
            }
            return AIWritingResult(text: fallback, task: task, providerUsed: .formattingOnly, usedFallback: true)
        }
    }

    private func tryOnlineRewrite(
        request: AIWritingRequest,
        configuration: AIWritingConfiguration,
        apiKey: String
    ) async -> String? {
        do {
            let text = try await cloudClient.rewrite(
                request: request,
                configuration: configuration,
                apiKey: apiKey
            )
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        } catch {
            print("[AIWriting] Online rewrite failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func tryLocalRewrite(request: AIWritingRequest, localPort: Int?) async -> String? {
        guard let localPort else { return nil }
        do {
            let text = try await localClient.rewrite(request: request, port: localPort)
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        } catch {
            print("[AIWriting] Local rewrite failed: \(error.localizedDescription)")
            return nil
        }
    }
}
