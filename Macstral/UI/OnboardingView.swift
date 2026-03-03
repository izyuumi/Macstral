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

                VoxtralSetupRow(
                    step: appState.setupStep,
                    progress: appState.setupProgress,
                    statusText: appState.setupStatusText
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
            .disabled(!(appState.hasMicPermission && appState.hasAccessibilityPermission && appState.isVoxtralReady))

            if case .error(let message) = appState.setupStep {
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

// MARK: - VoxtralSetupRow

private struct VoxtralSetupRow: View {
    let step: SetupStep
    let progress: Double
    let statusText: String

    private var title: String {
        "Voxtral Model"
    }

    private var detail: String {
        if statusText.isEmpty {
            switch step {
            case .idle:
                return "Waiting to set up Voxtral..."
            case .ready:
                return "Model is ready."
            case .error(let msg):
                return msg
            default:
                return "Setting up..."
            }
        }
        return statusText
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 22))
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isInProgress {
                    if progress > 0 {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Spacer()

            if case .ready = step {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
            } else if case .error = step {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 20))
            }
        }
        .padding(.horizontal, 4)
    }

    private var isInProgress: Bool {
        switch step {
        case .downloadingPython, .installingDeps, .downloadingModel, .launching:
            return true
        default:
            return false
        }
    }
}
