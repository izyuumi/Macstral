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
            symbol: "globe",
            title: "All languages",
            detail: "Japanese, French, German, Spanish, Italian, Portuguese, Chinese — beyond English & auto-detect."
        ),
        ProFeature(
            symbol: "wand.and.stars",
            title: "Auto-punctuation",
            detail: "Capitalization, sentence punctuation, and tidy spacing applied automatically."
        ),
        ProFeature(
            symbol: "clock.arrow.circlepath",
            title: "Transcript history",
            detail: "Searchable local log of every dictation, with export."
        ),
        ProFeature(
            symbol: "dial.high",
            title: "Balanced & Accurate models",
            detail: "Higher-accuracy Voxtral model tiers in addition to Fast."
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
                Text("A one-time \(LemonSqueezyConfig.proPriceDisplay) unlock. No subscription. Still 100% on-device.")
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
