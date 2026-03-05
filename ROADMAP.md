# Macstral Roadmap — 0.3.0

> **Status:** Draft — pending review against competitive analysis brief (in progress).
> **Constraint:** Local-first. No cloud dependencies. No GPU server.
> **Team size:** 2 engineers.
> **0.2.0 baseline:** Voxtral MLX streaming STT, configurable hotkey, paste-last-transcription, adaptive latency, streaming desync fix.

---

## Proposed Features

### 1. Transcription History Panel · `S`

**What:** A Macstral menu or window showing the last 20–50 transcriptions from the current session, with one-click copy to clipboard for any entry.

**Why it matters:** Users frequently lose dictations they didn't paste in time — a typo, a missed click, switching apps. The current `latestTranscript` field already exists in `AppState`; this is a collection of the last N final transcripts stored in memory and surfaced in a History menu item (similar to clipboard managers). Zero Python changes required.

**Effort estimate:** S
- `AppState`: add `transcriptHistory: [String]`, cap at 50 entries
- Status bar menu: add a "History" submenu listing entries
- Each entry: single-click to copy to clipboard
- Clear history action

**Dependencies/risks:**
- None. Pure Swift, no new permissions, no persistence needed (session-scoped is fine for v1).
- If users want cross-session persistence, that's a follow-up (UserDefaults is trivial).

---

### 2. Live Waveform in HUD · `S`

**What:** Replace the pulsing mic icon in the HUD with a real-time audio waveform bar graph driven by the audio buffer already captured by `AudioCaptureManager`.

**Why it matters:** The current pulsing animation gives no signal about whether the microphone is actually picking up audio — users can't tell if they're too far from the mic or if a background noise is dominating. A live waveform provides immediate, calibrated visual feedback and makes the HUD feel responsive.

**Effort estimate:** S
- `AudioCaptureManager`: publish RMS amplitude values alongside PCM chunks (already computes chunks, just need a running average)
- `DictationHUDView`: replace the mic icon animation with a 5–7 bar waveform that scales to RMS; animate with `withAnimation`
- No Python changes

**Dependencies/risks:**
- Minor: need to thread amplitude values from `AudioCaptureManager` to the SwiftUI HUD efficiently (Observable or a publisher). Existing architecture makes this straightforward.
- Design risk: waveform needs to look good at the HUD's 300×80pt size. Prototype early.

---

### 3. Multi-Language Transcription · `M`

**What:** Let users choose an input language (e.g. Japanese, French, Spanish, German) in Preferences. The server passes a `language` hint to Voxtral's `StreamingSession`, unlocking transcription in languages other than English.

**Why it matters:** Voxtral-Mini-4B-Realtime is a multilingual model. Many of our most motivated early users are in Japan (the app was built by a Japanese developer). Enabling Japanese dictation — even as a beta toggle — is a meaningful differentiator against English-only local STT tools. No model download required; it's already in the 4-bit weight file.

**Effort estimate:** M
- `PreferencesView`: add a language picker (dropdown, ~8 languages to start)
- `HotkeySettings`/settings store: persist `preferredLanguage`
- `WebSocketClient` protocol extension: include `language` field in the initial handshake or stream header
- `voxtral_server.py`: pass `language` param to `StreamingSession` constructor (check voxmlx API; may be a single parameter)
- Test accuracy: Voxtral-Mini's multilingual quality varies — document known limitations

**Dependencies/risks:**
- Blocked on voxmlx API surface: need to verify `StreamingSession` accepts a `language` kwarg. If not, may need to set it via environment or model config. Low risk — the underlying Voxtral model is multilingual by design.
- Accuracy on smaller quantized model may disappoint for some languages. Offer as "beta" to set expectations.
- No new model download; same weight file.

---

### 4. Model Quality Selector · `M`

**What:** Add a "Model quality" preference toggle (Fast / Balanced / Accurate) that downloads and switches between Voxtral quantization levels (e.g. 4-bit → 8-bit → bf16 slices), allowing users to trade transcription speed for accuracy based on their hardware.

**Why it matters:** On M-series Macs with 32–64 GB unified memory, users can run a higher-fidelity model. On M1 8 GB machines, the 4-bit model is the only viable option. Surfacing this choice respects user hardware and lets power users unlock better accuracy without Macstral making the call for them.

**Effort estimate:** M
- `PreferencesView`: "Model quality" segmented control (Fast · Balanced · Accurate)
- Settings store: persist selection
- `PythonBackendManager`: pass model identifier to the server process env
- `voxtral_server.py`: accept `MACSTRAL_MODEL_ID` env var, use it in model load; currently hardcoded to `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit`
- `OnboardingView`/setup flow: download the selected model during onboarding (or lazily on first switch)
- Size estimates per model tier need to be documented in UI (e.g. "4-bit: 2.4 GB · 8-bit: 4.8 GB")

**Dependencies/risks:**
- Depends on mlx-community publishing usable Voxtral weight variants at multiple quantization levels. Currently only the 4-bit variant is validated in the codebase.
- Model switching at runtime requires restarting the Python backend process — handle gracefully (show "Loading model…" state).
- Storage: users with 256 GB SSDs may not want multiple model files. Offer download-on-demand, not pre-bundling.

---

### 5. Transcript Export · `S`

**What:** A "Save transcript…" menu item that writes the current session's transcription history to a plain `.txt` file chosen by the user via `NSSavePanel`.

**Why it matters:** Macstral is already used for meeting notes, lecture capture, and ad-hoc voice memos. Right now, users must manually copy each transcription. Export-to-file closes the loop for longer sessions and unlocks workflows (e.g. pipe to another tool, review later).

**Effort estimate:** S
- Depends on **Feature 1** (History panel) providing `transcriptHistory: [String]`
- `StatusBarController` or menu: add "Save transcript…" item, enabled when history is non-empty
- Present `NSSavePanel` with default filename `macstral-transcript-YYYY-MM-DD.txt`
- Write joined history entries separated by `\n\n`; no external dependencies

**Dependencies/risks:**
- Soft dependency on Feature 1. Can ship standalone (just exports `latestTranscript`) but is much more useful with the full history.
- No new permissions needed; `NSSavePanel` is user-initiated file access, no sandboxing issues.

---

## Candidate Backlog (post-0.3.0)

Items that came up during planning but were deferred for scope or dependency reasons:

| Item | Reason deferred |
|------|----------------|
| VoiceOver / accessibility audit | L effort, no engineering constraint blocking it — schedule for 0.4.0 |
| Word-level confidence highlights | Requires voxmlx to expose per-token confidence; API not yet public |
| Keyboard-only hotkey management | Preferences already keyboard-navigable; full audit is polish, not urgent |
| Background dictation (no HUD focus required) | Security/UX risk — deferred pending user research |
| Custom vocabulary / phrase boosting | Not yet exposed by Voxtral; revisit when model API matures |

---

## Release Criteria for 0.3.0

- [ ] All 5 features above merged to main with tests where applicable
- [ ] Updated against competitive analysis brief (pending research-analyst output)
- [ ] No new cloud dependencies introduced
- [ ] `brew upgrade macstral` delivers the release (automated via existing release pipeline)
- [ ] Release notes drafted

---

*Last updated: 2026-03-05. Author: @cto. To be reviewed with @ceo and research-analyst brief.*
