@preconcurrency import AVFAudio
import AudioToolbox
import CoreAudio

// MARK: - SystemAudioCaptureManager

/// Captures the Mac's **system audio output** (everything currently playing) using a
/// Core Audio process tap (macOS 14.4+), converts it to PCM-16 mono 16 kHz, and emits raw
/// `Data` chunks — the same format `AudioCaptureManager` produces for the microphone, so the
/// rest of the transcription pipeline is unchanged.
///
/// The first capture triggers the system's audio-recording consent prompt (TCC). If the tap
/// cannot be created (consent denied, no output device, unsupported OS) `startCapture()` throws.
final class SystemAudioCaptureManager {

    // MARK: - Public

    /// Called on a Core Audio IO thread with each chunk of raw PCM-16 mono 16 kHz audio data.
    /// The closure must be thread-safe; it is *not* invoked on the main actor.
    var onAudioChunk: ((Data) -> Void)?

    // MARK: - Private Core Audio state

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var processor: TapStreamProcessor?
    private var isRunning = false

    // MARK: - Capture control

    /// Creates a global system-audio tap, wraps it in a private aggregate device, installs an
    /// IO proc, and starts capture. Throws `SystemAudioCaptureError` on any failure.
    func startCapture() throws {
        guard !isRunning else { return }

        // 1. Describe a tap over all system output (exclude no processes = capture everything).
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "Macstral System Audio Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted // keep audio audible while capturing

        // 2. Create the process tap.
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else {
            throw SystemAudioCaptureError.tapCreationFailed(status)
        }
        tapID = tap

        // 3. Build a private aggregate device that contains the tap, clocked by the default
        //    output device.
        guard let outputUID = Self.defaultOutputDeviceUID() else {
            cleanup()
            throw SystemAudioCaptureError.noOutputDevice
        }
        let aggregateUID = UUID().uuidString
        let tapUUID = tapDescription.uuid.uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Macstral System Audio",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate)
        guard status == noErr, aggregate != kAudioObjectUnknown else {
            cleanup()
            throw SystemAudioCaptureError.aggregateCreationFailed(status)
        }
        aggregateID = aggregate

        // 4. Read the tap's stream format and build a matching input AVAudioFormat.
        guard let inputFormat = Self.tapStreamFormat(tapID), inputFormat.sampleRate > 0 else {
            cleanup()
            throw SystemAudioCaptureError.formatUnavailable
        }
        print("[SystemAudioCaptureManager] Tap format: \(inputFormat)")

        guard let processor = TapStreamProcessor(inputFormat: inputFormat, onChunk: { [weak self] data in
            self?.onAudioChunk?(data)
        }) else {
            cleanup()
            throw SystemAudioCaptureError.formatUnavailable
        }
        self.processor = processor

        // 5. Install the IO proc. The block runs on a Core Audio thread and only touches the
        //    Sendable `processor`, never the main actor.
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, inInputData, _, _, _ in
            processor.process(inInputData)
        }
        guard status == noErr, let procID else {
            cleanup()
            throw SystemAudioCaptureError.ioProcCreationFailed(status)
        }
        ioProcID = procID

        // 6. Start.
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            cleanup()
            throw SystemAudioCaptureError.startFailed(status)
        }

        isRunning = true
        print("[SystemAudioCaptureManager] System audio capture started.")
    }

    /// Stops capture and tears down all Core Audio objects.
    func stopCapture() {
        guard isRunning || tapID != kAudioObjectUnknown else { return }
        cleanup()
        print("[SystemAudioCaptureManager] System audio capture stopped.")
    }

    private func cleanup() {
        if let procID = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        processor = nil
        isRunning = false
    }

    // MARK: - Core Audio property helpers

    /// The UID string of the current default output device, or nil if none exists.
    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, $0)
        }
        guard uidStatus == noErr else { return nil }
        return uid as String
    }

    /// Reads the tap's output stream format.
    private static func tapStreamFormat(_ tap: AudioObjectID) -> AVAudioFormat? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        guard status == noErr else { return nil }
        return AVAudioFormat(streamDescription: &asbd)
    }
}

// MARK: - TapStreamProcessor

/// Converts tap audio buffers (typically float32 stereo at the device sample rate) to PCM-16
/// mono 16 kHz on the Core Audio IO thread. `@unchecked Sendable` because the IO block needs to
/// call it off the main actor; all access is confined to that single serial IO thread.
private final class TapStreamProcessor: @unchecked Sendable {

    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let onChunk: (Data) -> Void

    init?(inputFormat: AVAudioFormat, onChunk: @escaping (Data) -> Void) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
        self.onChunk = onChunk
    }

    func process(_ bufferList: UnsafePointer<AudioBufferList>) {
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: bufferList),
              inputBuffer.frameLength > 0 else { return }

        let inputFrameCount = inputBuffer.frameLength
        let outputFrameCapacity = AVAudioFrameCount(
            ceil(Double(inputFrameCount) * outputFormat.sampleRate / inputFormat.sampleRate)
        )
        guard outputFrameCapacity > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity)
        else { return }

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

        if conversionError != nil { return }
        guard status != .error, outputBuffer.frameLength > 0,
              let int16Data = outputBuffer.int16ChannelData else { return }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        onChunk(Data(bytes: int16Data[0], count: byteCount))
    }
}

// MARK: - Errors

enum SystemAudioCaptureError: LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case startFailed(OSStatus)
    case noOutputDevice
    case formatUnavailable

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let status):
            return "Couldn't start system-audio capture (tap error \(status)). Grant Macstral permission to record system audio in System Settings ▸ Privacy & Security."
        case .aggregateCreationFailed(let status):
            return "Couldn't create the system-audio device (error \(status))."
        case .ioProcCreationFailed(let status):
            return "Couldn't attach to the system-audio device (error \(status))."
        case .startFailed(let status):
            return "Couldn't start the system-audio device (error \(status))."
        case .noOutputDevice:
            return "No audio output device is available to capture."
        case .formatUnavailable:
            return "Couldn't determine the system-audio format."
        }
    }
}
