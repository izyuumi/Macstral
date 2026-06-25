import SwiftUI

// MARK: - AIWritingPreferencesView

struct AIWritingPreferencesView: View {
    @State private var provider: AIWritingProvider
    @State private var openAIModel: String
    @State private var compatibleBaseURL: String
    @State private var compatibleModel: String
    @State private var fallbackToLocal: Bool
    @State private var apiKeyInput: String = ""
    @State private var hasSavedAPIKey: Bool = false
    @State private var keyMessage: String?

    private let credentialStore = KeychainAIWritingCredentialStore.shared

    init() {
        let configuration = AIWritingSettings.current
        _provider = State(initialValue: configuration.provider)
        _openAIModel = State(initialValue: configuration.openAIModel)
        _compatibleBaseURL = State(initialValue: configuration.compatibleBaseURL)
        _compatibleModel = State(initialValue: configuration.compatibleModel)
        _fallbackToLocal = State(initialValue: configuration.fallbackToLocal)
    }

    var body: some View {
        Form {
            providerSection
            keySection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear {
            refreshAPIKeyState()
        }
        .onChange(of: provider) { _, _ in saveSettings() }
        .onChange(of: openAIModel) { _, _ in saveSettings() }
        .onChange(of: compatibleBaseURL) { _, _ in saveSettings() }
        .onChange(of: compatibleModel) { _, _ in saveSettings() }
        .onChange(of: fallbackToLocal) { _, _ in saveSettings() }
    }

    private var providerSection: some View {
        Section {
            providerPicker
            providerModelFields
            fallbackToggle
        } footer: {
            Text(providerFooterText)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var providerPicker: some View {
        LabeledContent("AI writing") {
            Picker("", selection: $provider) {
                ForEach(AIWritingProvider.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 220)
        }
    }

    @ViewBuilder
    private var providerModelFields: some View {
        switch provider {
        case .openAI:
            LabeledContent("Model") {
                TextField(AIWritingSettings.defaultOpenAIModel, text: $openAIModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
        case .openAICompatible:
            LabeledContent("Base URL") {
                TextField(AIWritingSettings.defaultCompatibleBaseURL, text: $compatibleBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
            LabeledContent("Model") {
                TextField(AIWritingSettings.defaultCompatibleModel, text: $compatibleModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
        case .local, .formattingOnly:
            EmptyView()
        }
    }

    @ViewBuilder
    private var fallbackToggle: some View {
        if provider != .formattingOnly {
            Toggle("Use local/offline fallback", isOn: $fallbackToLocal)
        }
    }

    @ViewBuilder
    private var keySection: some View {
        if provider.isOnline {
            Section {
                LabeledContent("API key") {
                    SecureField(hasSavedAPIKey ? "Saved in Keychain" : "Paste API key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                HStack {
                    Spacer()
                    Button("Save API Key", action: saveAPIKey)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Forget Key", action: clearAPIKey)
                        .disabled(!hasSavedAPIKey)
                }
                if let keyMessage {
                    Text(keyMessage)
                        .font(.caption)
                        .foregroundColor(messageColor(for: keyMessage))
                }
            } footer: {
                Text(keyFooterText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private var providerFooterText: String {
        switch provider {
        case .openAI:
            return "Online AI writing is the default. Macstral sends raw transcripts and selected-text context to OpenAI when a key is saved."
        case .openAICompatible:
            return "Uses your configured OpenAI-compatible chat endpoint for the rewrite step."
        case .local:
            return "Runs the rewrite step on this Mac using the bundled local LLM. This keeps the writing layer offline."
        case .formattingOnly:
            return "Uses deterministic local punctuation and capitalization only. No AI rewrite request is made."
        }
    }

    private var keyFooterText: String {
        if hasSavedAPIKey {
            return "Your API key is stored in Keychain and used only for AI writing requests."
        }
        return "Add your own API key to enable online AI writing; otherwise Macstral uses the selected fallback."
    }

    private func saveSettings() {
        AIWritingSettings.current = AIWritingConfiguration(
            provider: provider,
            openAIModel: normalized(openAIModel, fallback: AIWritingSettings.defaultOpenAIModel),
            compatibleBaseURL: normalized(compatibleBaseURL, fallback: AIWritingSettings.defaultCompatibleBaseURL),
            compatibleModel: normalized(compatibleModel, fallback: AIWritingSettings.defaultCompatibleModel),
            fallbackToLocal: fallbackToLocal
        )
    }

    private func refreshAPIKeyState() {
        hasSavedAPIKey = credentialStore.loadAPIKey() != nil
    }

    private func saveAPIKey() {
        do {
            try credentialStore.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            keyMessage = "API key saved in Keychain."
            refreshAPIKeyState()
        } catch {
            keyMessage = "Error saving API key: \(error.localizedDescription)"
        }
    }

    private func clearAPIKey() {
        do {
            try credentialStore.clearAPIKey()
            apiKeyInput = ""
            keyMessage = "API key removed."
            refreshAPIKeyState()
        } catch {
            keyMessage = "Error removing API key: \(error.localizedDescription)"
        }
    }

    private func messageColor(for message: String) -> Color {
        message.lowercased().contains("error") ? .red : .secondary
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
