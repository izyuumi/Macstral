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
    private let client = AudioNotesBackendClient()
    private let portProvider: () -> Int?
    private let languageProvider: () -> String?

    // MARK: - Constants

    /// 15 s of PCM-16 mono 16 kHz = 16000 × 2 × 15 bytes. Short segments keep the model's
    /// end-of-utterance detection aligned with our explicit per-segment commit.
    private static let segmentBytes = 16_000 * 2 * 15
    private static let bytesPerSecond = 16_000 * 2

    // MARK: - State

    private var writer: AudioFileWriter?
    private var recordingURL: URL?
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
        languageProvider: @escaping () -> String?
    ) {
        self.appState = appState
        self.store = store
        self.portProvider = portProvider
        self.languageProvider = languageProvider
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

        recordingStartedAt = ProcessInfo.processInfo.systemUptime
        appState.audioNotesRecordingSeconds = 0
        appState.audioNotesProgressText = ""
        appState.audioNotesStatus = .recording
        startTimer()
    }

    /// Stops capture and kicks off transcription + notes generation.
    func stopRecording() {
        guard case .recording = appState.audioNotesStatus else { return }
        capture.stopCapture()
        capture.onAudioChunk = nil
        stopTimer()

        let byteCount = writer?.finishAndByteCount() ?? 0
        writer = nil
        guard let url = recordingURL else {
            appState.audioNotesStatus = .idle
            return
        }
        recordingURL = nil

        let duration = Double(byteCount) / Double(Self.bytesPerSecond)
        appState.audioNotesStatus = .transcribing
        appState.audioNotesProgressText = "Preparing transcription…"

        processingTask = Task { [weak self] in
            await self?.process(recordingURL: url, duration: duration)
        }
    }

    // MARK: - Notes regeneration

    /// Re-runs notes generation for an existing note (e.g. after editing or a failed first pass).
    func regenerateNotes(for note: AudioNote) {
        guard case .idle = appState.audioNotesStatus else { return }
        guard let port = portProvider() else {
            appState.audioNotesStatus = .error("Transcription engine isn't ready yet.")
            return
        }
        appState.audioNotesStatus = .generatingNotes
        appState.audioNotesProgressText = "Generating notes…"

        processingTask = Task { [weak self] in
            guard let self else { return }
            self.client.connect(port: port)
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

    private func process(recordingURL url: URL, duration: Double) async {
        defer { try? FileManager.default.removeItem(at: url) }

        guard let port = portProvider() else {
            appState.audioNotesStatus = .error("Transcription engine isn't ready yet.")
            return
        }
        client.connect(port: port)

        guard let pcm = try? Data(contentsOf: url), !pcm.isEmpty else {
            appState.audioNotesStatus = .error("The recording was empty.")
            return
        }

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
