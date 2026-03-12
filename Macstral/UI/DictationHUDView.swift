import SwiftUI

struct DictationHUDView: View {

    var appState: AppState

    // Bar envelope shape: edges shorter, centre tallest.
    private let barScales: [Float] = [0.45, 0.75, 1.0, 0.75, 0.45]
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 28

    /// Drives idle breathing animation (0 → 1, repeating).
    @State private var breathPhase: Double = 0

    /// Blended audio level: real RMS when speaking, gentle sine when idle.
    private var effectiveLevel: Float {
        let live = appState.audioLevel
        // Threshold below which we blend into idle breathing
        if live > 0.12 { return live }
        let breathLevel = Float(0.04 + 0.07 * breathPhase)
        // Cross-fade: as live level rises toward threshold, blend out the breath
        let blend = live / 0.12
        return breathLevel * (1 - blend) + live * blend
    }

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
                            let level = CGFloat(effectiveLevel * barScales[index])
                            let barHeight = minBarHeight + (maxBarHeight - minBarHeight) * level
                            Capsule()
                                .fill(Color.white)
                                .frame(width: 3, height: barHeight)
                                .animation(.spring(response: 0.2, dampingFraction: 0.65),
                                           value: barHeight)
                        }
                    }

                    Text("Listening...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.4)
                        .repeatForever(autoreverses: true)
                    ) {
                        breathPhase = 1.0
                    }
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
