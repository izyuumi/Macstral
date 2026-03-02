import SwiftUI

struct DictationHUDView: View {

    var appState: AppState

    @State private var isPulsing: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 1.0 : 0.6)
                    .animation(
                        appState.dictationStatus == .listening
                            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )

                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                if showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }

            if shouldShowTranscript {
                Text(appState.liveTranscript)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 300, height: 80)
        .onChange(of: appState.dictationStatus) { _, newStatus in
            isPulsing = newStatus == .listening
        }
        .onAppear {
            isPulsing = appState.dictationStatus == .listening
        }
    }

    private var statusIcon: String {
        switch appState.dictationStatus {
        case .idle, .listening:
            return "mic.fill"
        case .processing:
            return "waveform"
        case .inserting:
            return "text.cursor"
        }
    }

    private var statusText: String {
        switch appState.dictationStatus {
        case .idle, .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .inserting:
            return "Inserting..."
        }
    }

    private var showsSpinner: Bool {
        switch appState.dictationStatus {
        case .processing, .inserting:
            return true
        default:
            return false
        }
    }

    private var shouldShowTranscript: Bool {
        !appState.liveTranscript.isEmpty
            && appState.dictationStatus != .inserting
    }
}
