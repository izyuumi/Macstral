import AVFoundation
import SwiftUI

struct OnboardingView: View {

    var appState: AppState
    var onPermissionStateChanged: (() -> Void)?
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {

            // App header
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)

                Text("Macstral")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("On-device voice dictation.\nGrant the permissions below to get started.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Permission rows
            VStack(spacing: 16) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to capture your voice.",
                    isGranted: appState.hasMicPermission,
                    actionLabel: "Grant",
                    action: requestMicrophonePermission
                )

                PermissionRow(
                    icon: "waveform.badge.mic",
                    title: "Speech Recognition",
                    description: "Required to transcribe your voice on-device.",
                    isGranted: appState.hasSpeechPermission,
                    actionLabel: "Grant",
                    action: requestSpeechPermission
                )

                ModelPreparationRow(
                    status: appState.modelPreparationStatus,
                    hasSpeechPermission: appState.hasSpeechPermission
                )

                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Required to type text into other apps.",
                    isGranted: appState.hasAccessibilityPermission,
                    actionLabel: "Open Settings",
                    action: openAccessibilitySettings
                )
            }

            Divider()

            // Get Started button
            Button(action: { onComplete?() }) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!(appState.hasMicPermission && appState.hasSpeechPermission && appState.hasAccessibilityPermission && appState.isModelReadyForUse))

            if case .unavailable(let message) = appState.modelPreparationStatus {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(width: 450, height: 470)
    }

    // MARK: - Actions

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                appState.hasMicPermission = granted
                onPermissionStateChanged?()
            }
        }
    }

    private func requestSpeechPermission() {
        Task { @MainActor in
            appState.hasSpeechPermission = await PermissionChecker.requestSpeechPermission()
            onPermissionStateChanged?()
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        onPermissionStateChanged?()
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {

    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
            } else {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct ModelPreparationRow: View {
    let status: ModelPreparationStatus
    let hasSpeechPermission: Bool

    private var title: String {
        "On-device Model"
    }

    private var detail: String {
        if !hasSpeechPermission {
            return "Grant Speech Recognition permission to check model availability."
        }
        switch status {
        case .unknown:
            return "Waiting to check model availability."
        case .checking:
            return "Checking model availability..."
        case .preparing:
            return "Preparing model..."
        case .ready:
            return "Model is ready."
        case .unavailable:
            return "Model unavailable."
        }
    }

    private var iconName: String {
        switch status {
        case .ready:
            return "checkmark.circle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        default:
            return "arrow.trianglehead.2.clockwise"
        }
    }

    private var iconColor: Color {
        switch status {
        case .ready:
            return .green
        case .unavailable:
            return .red
        default:
            return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 22))
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if status == .checking || status == .preparing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 20))
            }
        }
        .padding(.horizontal, 4)
    }
}
