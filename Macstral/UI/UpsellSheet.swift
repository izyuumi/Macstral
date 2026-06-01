import SwiftUI

// MARK: - ProFeature

/// One row in the Pro feature comparison, reused by the upsell sheet and the License tab.
struct ProFeature: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String

    static let all: [ProFeature] = [
        ProFeature(
            symbol: "bolt.horizontal.circle",
            title: "Cloud transcription",
            detail: "Offload dictation to Macstral's servers — often faster than on-device, and frees up your Mac."
        ),
        ProFeature(
            symbol: "sparkles",
            title: "Cloud AI notes",
            detail: "Generate meeting notes with a larger hosted model for sharper summaries."
        ),
        ProFeature(
            symbol: "gauge.with.dots.needle.67percent",
            title: "Consistent speed on any Mac",
            detail: "Heavy models run in the cloud, so older or memory-limited Macs stay fast."
        ),
        ProFeature(
            symbol: "lock.open",
            title: "Everything else stays Free",
            detail: "All on-device features — every language, model tier, history, auto-punctuation — are free for everyone."
        ),
    ]
}

// MARK: - UpsellSheet

/// Reusable upgrade sheet shown when a Free user taps a locked feature. One component,
/// called from each gate point (language picker, model picker, history window).
struct UpsellSheet: View {
    let licenseManager: LicenseManager
    /// Highlighted feature title, e.g. "All languages", to draw attention to the relevant row.
    var highlight: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upgrade to Macstral Pro")
                    .font(.title2).bold()
                Text("A one-time \(LemonSqueezyConfig.proPriceDisplay) unlock. No subscription. Adds optional cloud speed — on-device stays free.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ProFeature.all) { feature in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: feature.symbol)
                            .frame(width: 22)
                            .foregroundStyle(feature.title == highlight ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .fontWeight(feature.title == highlight ? .semibold : .regular)
                            Text(feature.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Button("Maybe later") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Upgrade — \(LemonSqueezyConfig.proPriceDisplay)") {
                    openURL(LemonSqueezyConfig.checkoutURL)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }

            Text("Already bought? Open Preferences → License to enter your key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
