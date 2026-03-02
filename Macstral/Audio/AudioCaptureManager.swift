@preconcurrency import AVFAudio

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

    /// ~0.3 s worth of samples at 16 kHz.
    private let tapBufferSize: AVAudioFrameCount = 4_800

    // MARK: - Capture control

    /// Sets up the audio engine, installs a tap on the input node, and starts capturing.
    func startCapture() throws {
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let conv = AVAudioConverter(from: hardwareFormat, to: outputFormat) else {
            print("[AudioCaptureManager] Failed to create AVAudioConverter from \(hardwareFormat) to \(outputFormat).")
            return
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
}
