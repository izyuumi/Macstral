import SwiftUI

struct DictationHUDView: View {

    var appState: AppState

    private let barScales: [Float] = [0.5, 0.75, 1.0, 0.75, 0.5]
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 28

    var body: some View {
        VStack(spacing: 6) {
            if appState.dictationStatus == .processing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)

                    Text("Processing...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    // Waveform bars
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { index in
                            let level = CGFloat(appState.audioLevel * barScales[index])
                            let barHeight = minBarHeight + (maxBarHeight - minBarHeight) * level
                            Capsule()
                                .fill(Color.white)
                                .frame(width: 3, height: barHeight)
                                .animation(.spring(duration: 0.15), value: appState.audioLevel)
                        }
                    }

                    Text("Listening...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            if !appState.liveTranscript.isEmpty {
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
    }
}
