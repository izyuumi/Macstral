import AVFAudio
import ApplicationServices
import Speech

enum PermissionChecker {

    static func checkMicrophonePermission() -> Bool {
        return AVAudioApplication.shared.recordPermission == .granted
    }

    static func requestMicrophonePermission() async -> Bool {
        return await AVAudioApplication.requestRecordPermission()
    }

    static func checkSpeechPermission() -> Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
