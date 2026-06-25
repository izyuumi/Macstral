# Macstral

> Hold a key. Speak. Release. Text appears wherever your cursor is.

Macstral is a macOS menu bar app for hotkey-driven dictation and AI writing. Speech recognition runs locally on your Mac using [Voxtral MLX](https://github.com/T0mSIlver/voxmlx) — Mistral's open (Apache-2.0) voice model running via Apple's MLX framework. For the writing pass, you can use your own OpenAI/OpenAI-compatible API key for higher quality, or keep everything offline with the local LLM / formatting-only options.

**Current version: 0.3.0** · Requires Apple Silicon

---

## Install

```bash
brew tap izyuumi/tap
brew install --cask macstral
```

Or download `Macstral.zip` directly from [GitHub Releases](https://github.com/izyuumi/Macstral/releases).

---

## How it works

1. Launch Macstral — it sits in your menu bar
2. Complete first-run onboarding (microphone + accessibility permissions)
3. Hold your hotkey (default: `fn`), speak, release
4. Macstral rewrites the rough transcript into finished text and types it at your cursor position in any app

---

## Features

### Core dictation
- **Hold-to-dictate** — hold the hotkey while speaking, release to commit
- **Streaming transcription** — live preview of your words as you speak
- **AI writing pass** — convert rough speech into polished text using OpenAI, an OpenAI-compatible endpoint, the local LLM, or deterministic formatting
- **Speak-to-edit** — select text in another app and say things like "make this shorter" or "write a reply"; Macstral replaces only the selected text
- **Paste last transcription** — re-insert the most recent result from the menu bar

### New in v0.3.0
- **Multi-language transcription** — transcribe in Japanese, French, Spanish, and more — pick your language in Preferences
- **Transcript history** — session log with one-click copy per entry — never lose what you said
- **Export to .txt** — save any session to a text file via standard macOS save dialog
- **Live waveform HUD** — real-time audio feedback — see your voice as waveform bars during dictation
- **Model quality selector** — choose Fast / Balanced / Accurate based on your Mac's capability and preferred speed/accuracy tradeoff

---

## Supported languages

Language quality is based on the Voxtral Mini FLEURS benchmark at 480 ms streaming delay. Tier 1 languages are production-ready; Tier 2 are labelled Beta in the UI.

| Language | Code | Quality tier |
|---|---|---|
| English | `en` | Tier 1 |
| Italian | `it` | Tier 1 |
| Spanish | `es` | Tier 1 |
| Portuguese | `pt` | Tier 1 |
| German | `de` | Tier 1 |
| French | `fr` | Tier 1 |
| Japanese | `ja` | Tier 2 — Beta |
| Chinese (Mandarin) | `zh` | Tier 2 — Beta |
| Auto-detect | — | Model chooses per chunk |

Auto-detect is the default and works well for monolingual use. Select a specific language if you speak with an accent or want consistent output in one language.

---

## Model quality tiers

| Tier | Model | Size | Notes |
|---|---|---|---|
| Fast (default) | `Voxtral-Mini-4B-Realtime-2602-4bit` | ~2.4 GB | Downloaded on first launch |
| Balanced | `Voxtral-Mini-4B-Realtime-6bit` | ~3.6 GB | Downloaded on first selection |
| Accurate | `Voxtral-Mini-4B-Realtime-2602-fp16` | ~8.4 GB | Downloaded on first selection |

Model weights are stored in `~/Library/Application Support/Macstral/models/`. All models run fully on-device.

---

## Requirements

- **Apple Silicon Mac** (M1 or later) — x86 is not supported
- **macOS 15.0** or later
- ~3 GB free disk space for the default Fast model (more for Balanced/Accurate)
- No Python, Xcode, or other dependencies — bundled inside the app

---

## Privacy

Macstral does not connect to any server for local transcription. Audio is processed on your Mac unless you explicitly enable Macstral Pro cloud processing. The AI writing layer defaults to an online provider for quality when you save your own API key; in that mode, raw transcripts plus selected-text context are sent to your chosen provider. Choose **Local LLM** or **Formatting only** in Preferences to keep the writing pass offline.

The first-run model download comes from [Hugging Face](https://huggingface.co/mlx-community). No audio is sent as part of that download.

---

## Configuration

Open **Preferences** from the menu bar icon to configure:

- **Hotkey** — any key combination (default: `fn`)
- **Language** — Auto-detect or a specific language
- **Model quality** — Fast / Balanced / Accurate
- **AI Writing** — OpenAI, OpenAI-compatible, Local LLM, or Formatting only; API keys are stored in Keychain

---

## Building from source

```bash
git clone https://github.com/izyuumi/Macstral.git
cd Macstral
open Macstral.xcodeproj
```

Xcode 16+ required. The project uses Swift Package Manager for the [HotKey](https://github.com/soffes/HotKey) dependency.

---

## License

Macstral is proprietary software. © Yumi Izumi. All rights reserved.

The source is published for transparency, but it is **not** licensed for
redistribution, resale, or competing use. Use of the compiled app is governed by
the [End User License Agreement](EULA.md).

Versions released under git tags up to and including **v0.3.0** remain available
under the MIT License.
