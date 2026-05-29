import Foundation

// MARK: - FeatureGate

/// Central policy for which features are available on the Free tier vs. Pro.
///
/// All gate decisions take `isPro` explicitly (rather than reaching into a global) so they
/// are pure and unit-testable, and so enforcement points can clamp values that may have been
/// left over in UserDefaults from a previous Pro session (PLAN.md §4.2).
enum FeatureGate {

    // MARK: Language

    /// Languages usable without Pro.
    static let freeLanguages: Set<TranscriptionLanguage> = [.auto, .en]

    static func isLanguageUnlocked(_ language: TranscriptionLanguage, isPro: Bool) -> Bool {
        isPro || freeLanguages.contains(language)
    }

    /// Clamps a requested language to what the current tier allows. Free users fall back to
    /// auto-detect for any Pro-only language.
    static func effectiveLanguage(_ language: TranscriptionLanguage, isPro: Bool) -> TranscriptionLanguage {
        isLanguageUnlocked(language, isPro: isPro) ? language : .auto
    }

    // MARK: Model quality

    static func isModelQualityUnlocked(_ quality: ModelQuality, isPro: Bool) -> Bool {
        isPro || quality == .fast
    }

    /// Clamps a requested model quality to what the current tier allows. Free users are
    /// pinned to the Fast tier.
    static func effectiveModelQuality(_ quality: ModelQuality, isPro: Bool) -> ModelQuality {
        isModelQualityUnlocked(quality, isPro: isPro) ? quality : .fast
    }

    // MARK: History

    /// Whether transcript history is viewable. History is still persisted when free
    /// (PLAN.md §4.2 decision: gate access, keep persistence) so upgrading reveals back-history.
    static func isHistoryUnlocked(isPro: Bool) -> Bool { isPro }

    // MARK: Auto-punctuation

    static func isAutoPunctuationEnabled(isPro: Bool) -> Bool { isPro }
}
