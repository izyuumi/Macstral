import AppKit
import Foundation

/// Orchestrates the Audio Notes pipeline:
///   record system audio → buffer raw PCM to a temp file → segment + transcribe via Voxtral →
///   generate Markdown notes via the local LLM → persist an `AudioNote`.
///
/// Drives `AppState.audioNotesStatus` so the UI can reflect each phase.
@MainActor
final class AudioNotesRecorder {

    // MARK: - Dependencies

    private let appState: AppState
    private let store: AudioNotesStore
    private let capture = SystemAudioCaptureManager()
    private let micCapture = AudioCaptureManager()
    private let client = AudioNotesBackendClient()
    private let portProvider: () -> Int?
    private let languageProvider: () -> String?
    private let endpointProvider: () -> ProcessingEndpoint?

    // MARK: - Constants

    /// 15 s of PCM-16 mono 16 kHz = 16000 × 2 × 15 bytes. Short segments keep the model's
    /// end-of-utterance detection aligned with our explicit per-segment commit.
    private static let segmentBytes = 16_000 * 2 * 15
    private static let bytesPerSecond = 16_000 * 2

    // MARK: - State

    private var writer: AudioFileWriter?
    private var recordingURL: URL?
    private var micWriter: AudioFileWriter?
    private var micURL: URL?
    private var isMicActive = false
    private var timerTask: Task<Void, Never>?
    private var recordingStartedAt: TimeInterval = 0
    private var processingTask: Task<Void, Never>?

    var isRecording: Bool {
        if case .recording = appState.audioNotesStatus { return true }
        return false
    }

    init(
        appState: AppState,
        store: AudioNotesStore,
        portProvider: @escaping () -> Int?,
        languageProvider: @escaping () -> String?,
        endpointProvider: @escaping () -> ProcessingEndpoint?
    ) {
        self.appState = appState
        self.store = store
        self.portProvider = portProvider
        self.languageProvider = languageProvider
        self.endpointProvider = endpointProvider
    }

    /// Connects `client` to the resolved processing endpoint (cloud proxy or local server).
    /// Returns `false` when no endpoint is available.
    private func connectClient() -> Bool {
        switch endpointProvider() {
        case .cloud(let token):
            client.connect(url: MacstralCloudConfig.streamURL, authToken: token)
            return true
        case .onDevice(let port):
            client.connect(port: port)
            return true
        case nil:
            return false
        }
    }

    // MARK: - Recording control

    /// Begins capturing system audio. Requires the Voxtral backend to be ready (needed for the
    /// transcription that follows the stop).
    func startRecording() {
        guard case .idle = appState.audioNotesStatus else { return }
        guard portProvider() != nil else {
            appState.audioNotesStatus = .error("Transcription engine isn't ready yet.")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macstral-audionote-\(UUID().uuidString).pcm")
        guard let writer = AudioFileWriter(url: url) else {
            appState.audioNotesStatus = .error("Couldn't create a temporary recording file.")
            return
        }
        self.writer = writer
        self.recordingURL = url

        capture.onAudioChunk = { data in
            writer.write(data)
        }

        do {
            try capture.startCapture()
        } catch {
            capture.onAudioChunk = nil
            _ = writer.finishAndByteCount()
            try? FileManager.default.removeItem(at: url)
            self.writer = nil
            self.recordingURL = nil
            appState.audioNotesStatus = .error(error.localizedDescription)
            return
        }

        startMicrophoneIfEnabled()

        recordingStartedAt = ProcessInfo.processInfo.systemUptime
        appState.audioNotesRecordingSeconds = 0
        appState.audioNotesProgressText = ""
        appState.audioNotesStatus = .recording
        startTimer()
    }

    /// Starts microphone capture alongside the system tap when the user has opted in and granted
    /// mic permission. Best-effort: a mic failure leaves the system-audio recording running.
    private func startMicrophoneIfEnabled() {
        guard appState.audioNotesIncludeMicrophone, appState.hasMicPermission else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macstral-audionote-mic-\(UUID().uuidString).pcm")
        guard let micWriter = AudioFileWriter(url: url) else { return }

        micCapture.onAudioChunk = { data in
            micWriter.write(data)
        }
        do {
            try micCapture.startCapture()
            self.micWriter = micWriter
            self.micURL = url
            self.isMicActive = true
        } catch {
            micCapture.onAudioChunk = nil
            _ = micWriter.finishAndByteCount()
            try? FileManager.default.removeItem(at: url)
            print("[AudioNotesRecorder] Microphone capture failed, continuing system-audio only: \(error)")
        }
    }

    /// Stops capture and kicks off transcription + notes generation.
    func stopRecording() {
        guard case .recording = appState.audioNotesStatus else { return }
        capture.stopCapture()
        capture.onAudioChunk = nil
        if isMicActive {
            micCapture.stopCapture()
            micCapture.onAudioChunk = nil
            isMicActive = false
        }
        stopTimer()

        _ = writer?.finishAndByteCount()
        _ = micWriter?.finishAndByteCount()
        writer = nil
        micWriter = nil
        guard let systemURL = recordingURL else {
            try? micURL.map { try FileManager.default.removeItem(at: $0) }
            micURL = nil
            appState.audioNotesStatus = .idle
            return
        }
        let micRecordingURL = micURL
        recordingURL = nil
        micURL = nil

        appState.audioNotesStatus = .transcribing
        appState.audioNotesProgressText = "Preparing transcription…"

        processingTask = Task { [weak self] in
            await self?.process(systemURL: systemURL, micURL: micRecordingURL)
        }
    }

    // MARK: - Notes regeneration

    /// Re-runs notes generation for an existing note (e.g. after editing or a failed first pass).
    func regenerateNotes(for note: AudioNote) {
        guard case .idle = appState.audioNotesStatus else { return }
        guard endpointProvider() != nil else {
            appState.audioNotesStatus = .error("Transcription engine isn't ready yet.")
            return
        }
        appState.audioNotesStatus = .generatingNotes
        appState.audioNotesProgressText = "Generating notes…"

        processingTask = Task { [weak self] in
            guard let self else { return }
            _ = self.connectClient()
            do {
                let notes = try await self.client.generateNotes(transcript: note.transcript)
                var updated = note
                updated.notes = notes
                self.store.update(updated)
                self.appState.audioNotesStatus = .idle
                self.appState.audioNotesProgressText = ""
            } catch {
                self.appState.audioNotesStatus = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Pipeline

    private func process(systemURL: URL, micURL: URL?) async {
        defer {
            try? FileManager.default.removeItem(at: systemURL)
            try? micURL.map { try FileManager.default.removeItem(at: $0) }
        }

        guard connectClient() else {
            appState.audioNotesStatus = .error("Transcription engine isn't ready yet.")
            return
        }

        // Mix the system-audio and (optional) microphone tracks. Both are PCM-16 mono 16 kHz,
        // so they can be summed sample-for-sample.
        let systemPCM = (try? Data(contentsOf: systemURL)) ?? Data()
        let micPCM = micURL.flatMap { try? Data(contentsOf: $0) } ?? Data()
        let pcm = Self.mixPCM(systemPCM, micPCM)
        guard !pcm.isEmpty else {
            appState.audioNotesStatus = .error("The recording was empty.")
            return
        }
        let duration = Double(pcm.count) / Double(Self.bytesPerSecond)

        let language = languageProvider()
        let segments = Self.makeSegments(from: pcm)
        var pieces: [String] = []
        do {
            for (index, segment) in segments.enumerated() {
                appState.audioNotesProgressText = "Transcribing… \(index + 1)/\(segments.count)"
                let text = try await client.transcribeSegment(segment, language: language)
                if !text.isEmpty { pieces.append(text) }
            }
        } catch {
            // Persist whatever we managed to transcribe so the recording isn't lost.
            let transcript = pieces.joined(separator: " ")
            if !transcript.isEmpty {
                store.add(makeNote(transcript: transcript, notes: "", duration: duration))
            }
            appState.audioNotesStatus = .error(error.localizedDescription)
            return
        }

        let transcript = pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            appState.audioNotesStatus = .error("No speech was detected in the recording.")
            return
        }

        appState.audioNotesStatus = .generatingNotes
        appState.audioNotesProgressText = "Generating notes…"

        var notes = ""
        do {
            notes = try await client.generateNotes(transcript: transcript)
        } catch {
            // Notes are best-effort; still save the transcript.
            store.add(makeNote(transcript: transcript, notes: "", duration: duration))
            appState.audioNotesStatus = .error("Saved transcript, but notes failed: \(error.localizedDescription)")
            return
        }

        store.add(makeNote(transcript: transcript, notes: notes, duration: duration))
        appState.audioNotesProgressText = ""
        appState.audioNotesStatus = .idle
    }

    private func makeNote(transcript: String, notes: String, duration: Double) -> AudioNote {
        AudioNote(
            title: Self.deriveTitle(from: transcript),
            transcript: transcript,
            notes: notes,
            durationSeconds: duration
        )
    }

    /// Sums two PCM-16 mono tracks sample-for-sample with clipping. If either track is empty the
    /// other is returned unchanged. The result length matches the longer track (the shorter is
    /// treated as silence past its end).
    private static func mixPCM(_ a: Data, _ b: Data) -> Data {
        if a.isEmpty { return b }
        if b.isEmpty { return a }

        let countA = a.count / 2
        let countB = b.count / 2
        let n = max(countA, countB)
        var out = Data(count: n * 2)

        a.withUnsafeBytes { (aRaw: UnsafeRawBufferPointer) in
            b.withUnsafeBytes { (bRaw: UnsafeRawBufferPointer) in
                out.withUnsafeMutableBytes { (outRaw: UnsafeMutableRawBufferPointer) in
                    let aSamples = aRaw.bindMemory(to: Int16.self)
                    let bSamples = bRaw.bindMemory(to: Int16.self)
                    let outSamples = outRaw.bindMemory(to: Int16.self)
                    for i in 0..<n {
                        let av = i < countA ? Int32(aSamples[i]) : 0
                        let bv = i < countB ? Int32(bSamples[i]) : 0
                        let sum = max(Int32(Int16.min), min(Int32(Int16.max), av + bv))
                        outSamples[i] = Int16(sum)
                    }
                }
            }
        }
        return out
    }

    /// Splits the PCM buffer into segment-sized slices on even byte boundaries (Int16 frames).
    private static func makeSegments(from pcm: Data) -> [Data] {
        var segments: [Data] = []
        var offset = 0
        let total = pcm.count
        while offset < total {
            let end = min(offset + segmentBytes, total)
            // Keep the slice on an even byte boundary so we never split an Int16 sample.
            let alignedEnd = end - (end - offset) % 2
            segments.append(pcm.subdata(in: offset..<max(alignedEnd, offset + 2)))
            offset = alignedEnd
        }
        return segments.isEmpty ? [pcm] : segments
    }

    private static func deriveTitle(from transcript: String) -> String {
        let words = transcript.split(whereSeparator: { $0.isWhitespace }).prefix(8)
        let candidate = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? "System Audio Recording" : candidate
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - self.recordingStartedAt
                self.appState.audioNotesRecordingSeconds = Int(elapsed)
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}

// MARK: - AudioFileWriter

/// Appends audio bytes to a file from the Core Audio IO thread. `@unchecked Sendable` because the
/// capture callback hands it data off the main actor; all file access is serialized on `queue`.
private final class AudioFileWriter: @unchecked Sendable {

    private let handle: FileHandle
    private let queue = DispatchQueue(label: "to.yumi.Macstral.audionotes.writer")
    private var byteCount = 0

    init?(url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        self.handle = handle
    }

    func write(_ data: Data) {
        queue.async {
            do {
                try self.handle.write(contentsOf: data)
                self.byteCount += data.count
            } catch {
                // Drop the chunk on write failure; recording continues best-effort.
            }
        }
    }

    /// Flushes, closes the file, and returns the total bytes written.
    func finishAndByteCount() -> Int {
        queue.sync {
            try? self.handle.synchronize()
            try? self.handle.close()
            return self.byteCount
        }
    }
}
