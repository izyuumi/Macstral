import Foundation
@preconcurrency import AVFAudio
import Speech

// WebSocketClient preserves the existing app-facing interface, but now routes audio to the
// built-in macOS speech recognizer instead of a separate WebSocket backend.
@MainActor
class WebSocketClient: NSObject {

    // MARK: - Callbacks

    var onSessionCreated: (() -> Void)?
    var onTranscriptDelta: ((String) -> Void)?
    var onTranscriptDone: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onDisconnect: (() -> Void)?

    // MARK: - Private State

    private let recognitionFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isConnected: Bool = false

    var hasActiveSession: Bool {
        isConnected
    }

    func probeOnDeviceRecognitionAvailability() -> LocalRecognitionAvailability {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return .requiresSpeechPermission
        }
        guard makeRecognizer() != nil else {
            return .unavailable
        }
        return .ready
    }

    // MARK: - Connection Management

    /// Starts a local recognition session. The URL parameter is ignored and preserved
    /// only to keep the rest of the app unchanged.
    func connect(to url: URL? = nil) {
        _ = url
        guard !isConnected else { return }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            onError?(LocalTranscriptionError.speechPermissionDenied)
            return
        }

        guard let recognizer = makeRecognizer() else {
            onError?(LocalTranscriptionError.onDeviceRecognitionUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        self.recognizer = recognizer
        recognitionRequest = request
        isConnected = true
        onSessionCreated?()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let transcript = result.bestTranscription.formattedString
                    self.onTranscriptDelta?(transcript)

                    if result.isFinal {
                        self.onTranscriptDone?(transcript)
                        self.resetSession(notifyDisconnect: false)
                        return
                    }
                }

                if let error {
                    let shouldReportError = self.isConnected
                    self.resetSession()
                    if shouldReportError {
                        self.onError?(error)
                    }
                }
            }
        }
    }

    /// Close the local recognition session and clean up state.
    func disconnect() {
        guard isConnected || recognitionTask != nil || recognitionRequest != nil else { return }
        recognitionTask?.cancel()
        resetSession()
    }

    // MARK: - Sending Messages

    /// Append raw PCM-16 mono 16 kHz audio to the local recognition request.
    func sendAudioChunk(_ data: Data) {
        guard isConnected, let request = recognitionRequest else { return }

        do {
            let buffer = try makeAudioBuffer(from: data)
            request.append(buffer)
        } catch {
            onError?(error)
        }
    }

    /// Signal end of audio input so the recognizer can produce a final transcript.
    func sendCommit() {
        guard isConnected else { return }
        recognitionRequest?.endAudio()
    }

    // MARK: - Private Helpers

    private func makeRecognizer() -> SFSpeechRecognizer? {
        let preferredLocales = [
            Locale.autoupdatingCurrent,
            Locale.current,
            Locale(identifier: "en-US")
        ]

        for locale in preferredLocales {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }

        if let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition {
            return recognizer
        }

        return nil
    }

    private func makeAudioBuffer(from data: Data) throws -> AVAudioPCMBuffer {
        guard data.count.isMultiple(of: MemoryLayout<Int16>.size) else {
            throw LocalTranscriptionError.invalidAudioChunk
        }

        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: recognitionFormat, frameCapacity: frameCount) else {
            throw LocalTranscriptionError.bufferAllocationFailed
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.int16ChannelData else {
            throw LocalTranscriptionError.bufferAllocationFailed
        }

        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress else { return }
            memcpy(channelData[0], source, data.count)
        }
        return buffer
    }

    private func resetSession(notifyDisconnect: Bool = true) {
        let wasConnected = isConnected
        isConnected = false
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil

        if notifyDisconnect, wasConnected {
            onDisconnect?()
        }
    }
}

enum LocalRecognitionAvailability {
    case ready
    case requiresSpeechPermission
    case unavailable
}

enum LocalTranscriptionError: LocalizedError {
    case speechPermissionDenied
    case onDeviceRecognitionUnavailable
    case invalidAudioChunk
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Speech recognition permission has not been granted."
        case .onDeviceRecognitionUnavailable:
            return "On-device speech recognition is not available for the current system language."
        case .invalidAudioChunk:
            return "The captured audio chunk is not valid PCM-16 data."
        case .bufferAllocationFailed:
            return "Macstral could not prepare audio for local transcription."
        }
    }
}
