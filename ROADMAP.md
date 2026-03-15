# Macstral Roadmap

_Last updated: 2026-03-05 · Owner: @cto_

---

## 0.3.0 — Shipped ✅

> Theme: Make Macstral a tool you'd use every day, not just once

| # | Feature | Status |
|---|---|---|
| 1 | Multi-language transcription (JP, FR, ES, DE, IT, PT, ZH) | ✅ Shipped |
| 2 | Transcript history panel with one-click copy | ✅ Shipped |
| 3 | Export session to .txt | ✅ Shipped |
| 4 | Live waveform in dictation HUD | ✅ Shipped |
| 5 | Model quality selector (Fast / Balanced / Accurate) | ✅ Shipped |

---

## 0.4.0 — Planned

> Theme: Polish the output and lower the barrier to entry

**Target audience signal:** Post-launch feedback from Show HN / r/MacApps will refine this. Priorities are set based on competitive gap analysis (see `projects/research/competitive-analysis-2026-03.md`) and known rough edges from 0.3.0.

---

### Priority 1 — Auto-punctuation and smart formatting

**What:** Post-process each final transcript to capitalize the first word, add a period if the sentence lacks terminal punctuation, and strip leading/trailing whitespace. Exposed as a toggle in Preferences (on by default).

**Why it matters:** Macstral currently outputs raw streaming text — no capitals, no periods. Every competitor (Superwhisper, MacWhisper) either does this automatically or via LLM post-processing. Users copying text for emails, documents, or chat look unprofessional if they don't manually fix it. This is the highest-ROI UX improvement with zero cloud dependency.

**Implementation path:** Apply a Swift post-processor on the `done` event (not during streaming to avoid cursor jumps). Phase 1: heuristic rules (capitalize first letter, ensure terminal period). Phase 2 (0.4.x or later): evaluate an on-device tiny LLM for smarter reformatting.

**Effort:** S  
**Risk:** Low — pure Swift, no model changes, no new permissions

---

### Priority 2 — First-run onboarding flow

**What:** A proper guided first-launch experience. After permissions are granted, walk the user through: (1) hotkey selection, (2) language picker, (3) model quality choice with disk-space indication. Currently the app drops users into a blank menu bar icon after permissions. 

**Why it matters:** Macstral's Show HN and community launch are imminent. The first-run experience is the conversion moment — users who don't discover the language picker or model selector within 60 seconds will close the app and never return. Every competitor has an onboarding flow; Macstral has a permission gate and silence.

**Implementation path:** Extend `OnboardingWindow` with a post-permission step sequence in SwiftUI. Reuse `PreferencesView` components for hotkey and language controls. 3–4 screens maximum, skippable.

**Effort:** S  
**Risk:** Low — UI only, no new permissions or backend changes

---

### Priority 3 — Transcript search (Cmd+F in history)

**What:** A search bar at the top of the transcript history panel, filtered in real time as the user types. Matches are highlighted. Pressing Cmd+F when the history panel is visible focuses the search field.

**Why it matters:** History shipped in 0.3.0 is a flat list. A user who dictated 30 items over a session and wants to find a specific phrase has no way to do so except scrolling. Search is the natural next step after persistence. MacWhisper and Superwhisper both have search. Effort is low relative to the value for power users.

**Implementation path:** `@State` filter string in the history view; `.searchable()` modifier or a custom `TextField` with `.filter` on the `entries` array. No backend changes.

**Effort:** S  
**Risk:** Low — pure SwiftUI

---

### Priority 4 — Accessibility baseline (VoiceOver + reduce motion)

**What:** Add VoiceOver accessibility labels to all interactive controls (menu bar button, history entries, copy buttons, preference pickers). Respect `@Environment(\.accessibilityReduceMotion)` in the waveform and HUD animations. Support Dynamic Type where applicable.

**Why it matters:** Macstral's waveform HUD and animated breathing effect are invisible to VoiceOver. Any Mac user who relies on assistive technology cannot use the app at all today. Accessibility is also a reputational issue — Show HN commenters notice and call it out. Competitors on the App Store must pass accessibility review; Macstral should match parity even as a direct-distribution app.

**Implementation path:** Audit all `Image`, `Button`, and custom views for `.accessibilityLabel`. Replace hardcoded animation durations with `withAnimation(reduceMotion ? .none : ...)`. Systematic, no architecture changes.

**Effort:** M  
**Risk:** Low — purely additive, no existing behaviour changes

---

### Deferred from 0.4.0

| Feature | Reason for deferral |
|---|---|
| **Custom vocabulary / domain wordlist** | Voxtral's API does not expose vocabulary bias weighting. Significant research required into prompt injection; no clear path without patching voxmlx internals. Revisit in 0.5.0 after evaluating mlx-lm vocabulary bias support. |
| **iCloud sync for transcript history** | Conflicts with local-first constraint. History is stored per-device by design. Flagged TBD — revisit if user feedback shows multi-Mac use is common. Requires iCloud entitlements (adds App Store complication). |
| **System-wide dictation shortcut / IME registration** | Macstral's hotkey is already global (registered via HotKey library); text injection via Accessibility API already targets the focused app. The described friction ("click into Macstral first") does not apply to the current implementation. Revisit if user reports show real friction. |
| **Menu bar quick-type mode** | Covered by the existing hold-to-dictate flow. Overlap with onboarding improvements. No user signal yet that the current HUD is a problem. Revisit post-launch. |
| **App Store distribution** | Ruled out near-term by two independent hard blockers: (1) bundled Python backend triggers Guideline 2.5.2 auto-rejection; (2) Accessibility API text injection is incompatible with Mac App Store sandbox. See `projects/research/macstral-distribution-2026-03.md` for full analysis. |

---

### 0.4.0 success criteria

- [ ] Auto-punctuation is on by default and produces grammatically correct capitalization + terminal punctuation for ≥95% of common English dictation outputs
- [ ] First-run onboarding completes without user confusion (validated via at least 3 informal user tests)
- [ ] Transcript search returns correct results; Cmd+F shortcut works from any point when history is visible
- [ ] All interactive UI elements have VoiceOver labels; waveform animation respects `reduceMotion`
- [ ] CI build + test green; no regressions in existing test suite
- [ ] Homebrew tap updated to v0.4.0 on release day

---

## Future / unscheduled

- **AI post-processing via local LLM** — Reformat/summarize transcripts on-device (e.g. mlx-lm small model). Natural follow-on to auto-punctuation. Effort: L. No cloud dependency if using bundled MLX model.
- **Custom vocabulary** — Once Voxtral API surface is better understood or a voxmlx fork exposes vocabulary control.
- **Macstral Lite (App Store)** — File transcription only, no live injection, Swift/whisper.cpp backend. A parallel product, not a replacement. Requires full Python → native rewrite. Long-term option if App Store discovery becomes a strategic priority.
- **Language forcing** — Wire the language picker to actually inject a language token into the Voxtral prompt prefix (currently picker controls UI only; model still auto-detects). See `projects/research/voxtral-multilingual-2026-03.md` Part 3 for the implementation path.
