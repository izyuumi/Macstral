import Foundation

// MARK: - FeatureGate

/// Central policy for which features are available on the Free tier vs. Pro.
///
/// Macstral's model: **everything that runs on-device is Free, with no restrictions.** The Free
/// tier is a complete, unrestricted product — every language, every model-quality tier, transcript
/// history, auto-punctuation, and Audio Notes all run locally at no charge. Pro unlocks the single
/// optional thing that is *not* on-device: the **online (Macstral-hosted) processing path**, which
/// can be faster or more accurate than local inference depending on the Mac.
///
/// All gate decisions take `isPro` explicitly (rather than reaching into a global) so they are pure
/// and unit-testable. The on-device gates keep their `isPro` parameter for call-site stability even
/// though they now always return `true`.
enum FeatureGate {

    // MARK: On-device features (always Free)

    /// Every transcription language runs on-device via Voxtral/MLX, so all are Free.
    static func isLanguageUnlocked(_ language: TranscriptionLanguage, isPro: Bool) -> Bool { true }

    /// Language is never clamped — all languages are available on the Free tier.
    static func effectiveLanguage(_ language: TranscriptionLanguage, isPro: Bool) -> TranscriptionLanguage {
        language
    }

    /// Every model-quality tier runs on-device via MLX, so all are Free.
    static func isModelQualityUnlocked(_ quality: ModelQuality, isPro: Bool) -> Bool { true }

    /// Model quality is never clamped — all tiers are available on the Free tier.
    static func effectiveModelQuality(_ quality: ModelQuality, isPro: Bool) -> ModelQuality {
        quality
    }

    /// Transcript history is stored and viewed entirely on-device, so it is always Free.
    static func isHistoryUnlocked(isPro: Bool) -> Bool { true }

    /// Auto-punctuation runs on-device (`TranscriptFormatter`, no network), so it is always Free.
    static func isAutoPunctuationEnabled(isPro: Bool) -> Bool { true }

    // MARK: Online processing (Pro)

    /// The optional online (Macstral-hosted proxy) transcription + notes path. This is the one
    /// capability Pro unlocks: audio and transcripts are sent to Macstral's servers for faster or
    /// more accurate processing. Free stays fully functional and 100% on-device.
    static func isCloudProcessingUnlocked(isPro: Bool) -> Bool { isPro }
}
