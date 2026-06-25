@preconcurrency import AVFAudio
import CoreAudio

@MainActor
final class AudioCaptureManager {

    // MARK: - Public

    /// Called on a background thread with each chunk of raw PCM-16 mono 16 kHz audio data.
    var onAudioChunk: ((Data) -> Void)?

    // MARK: - Private

    private let engine = AVAudioEngine()

    /// Target output format: 16-bit signed integer, mono, 16 kHz.
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    private var converter: AVAudioConverter?
#if DEBUG
    private var debugAudioTask: Task<Void, Never>?
#endif

    /// ~0.032 s worth of samples at 16 kHz (512 frames ÷ 16 000 Hz).
    /// Smaller buffers reduce audio delivery granularity, getting data to the
    /// server sooner at the cost of slightly more frequent WebSocket sends.
    private let tapBufferSize: AVAudioFrameCount = 512

    // MARK: - Capture control

    /// Sets up the audio engine, installs a tap on the input node, and starts capturing.
    func startCapture() throws {
#if DEBUG
        if let debugAudioPath = UserDefaults.standard.string(forKey: "debugAudioInputFile"),
           !debugAudioPath.isEmpty {
            try startDebugFileCapture(path: debugAudioPath)
            return
        }
#endif

        guard Self.hasDefaultInputDevice() else {
            throw AudioCaptureError.noInputDevice
        }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidInputFormat
        }

        guard let conv = AVAudioConverter(from: hardwareFormat, to: outputFormat) else {
            print("[AudioCaptureManager] Failed to create AVAudioConverter from \(hardwareFormat) to \(outputFormat).")
            throw AudioCaptureError.converterUnavailable
        }
        converter = conv

        print("[AudioCaptureManager] Hardware format: \(hardwareFormat)")
        print("[AudioCaptureManager] Output format:   \(outputFormat)")

        inputNode.installTap(
            onBus: 0,
            bufferSize: tapBufferSize,
            format: hardwareFormat
        ) { [weak self] buffer, _ in
            self?.handleTapBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        print("[AudioCaptureManager] Engine started.")
    }

    /// Removes the tap and stops the audio engine.
    func stopCapture() {
#if DEBUG
        if let debugAudioTask {
            debugAudioTask.cancel()
            self.debugAudioTask = nil
            print("[AudioCaptureManager] Debug audio file stopped.")
            return
        }
#endif

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        print("[AudioCaptureManager] Engine stopped.")
    }

    // MARK: - Conversion

    private func handleTapBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else { return }

        // Calculate the expected output frame count after sample-rate conversion.
        let inputFrameCount = inputBuffer.frameLength
        let inputSampleRate = inputBuffer.format.sampleRate
        let outputSampleRate = outputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(
            ceil(Double(inputFrameCount) * outputSampleRate / inputSampleRate)
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            print("[AudioCaptureManager] Failed to allocate output PCM buffer.")
            return
        }

        var conversionError: NSError?
        var inputConsumed = false

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return inputBuffer
        }

        if let error = conversionError {
            print("[AudioCaptureManager] Conversion error: \(error)")
            return
        }

        guard status != .error, outputBuffer.frameLength > 0 else {
            print("[AudioCaptureManager] Conversion produced no frames (status=\(status.rawValue)).")
            return
        }

        // Extract raw bytes from the Int16 interleaved buffer.
        guard let int16ChannelData = outputBuffer.int16ChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let byteCount = frameLength * MemoryLayout<Int16>.size
        let data = Data(bytes: int16ChannelData[0], count: byteCount)

        onAudioChunk?(data)
    }

    private static func hasDefaultInputDevice() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown
    }

#if DEBUG
    private func startDebugFileCapture(path: String) throws {
        debugAudioTask?.cancel()

        let url = URL(fileURLWithPath: path)
        let audioData: Data
        do {
            audioData = try Data(contentsOf: url)
        } catch {
            throw AudioCaptureError.debugAudioFileUnavailable(path)
        }
        guard !audioData.isEmpty else {
            throw AudioCaptureError.debugAudioFileUnavailable(path)
        }

        let chunkByteCount = Int(tapBufferSize) * MemoryLayout<Int16>.size
        debugAudioTask = Task { [weak self] in
            guard let self else { return }
            var offset = 0
            while offset < audioData.count, !Task.isCancelled {
                let end = min(offset + chunkByteCount, audioData.count)
                self.onAudioChunk?(audioData.subdata(in: offset..<end))
                offset = end
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
        }
        print("[AudioCaptureManager] Debug audio file started: \(path)")
    }
#endif
}

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case invalidInputFormat
    case converterUnavailable
    case debugAudioFileUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone or audio input device is available."
        case .invalidInputFormat:
            return "The microphone input format is unavailable."
        case .converterUnavailable:
            return "Couldn't create the microphone audio converter."
        case .debugAudioFileUnavailable(let path):
            return "The debug audio input file is unavailable: \(path)"
        }
    }
}
