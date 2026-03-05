# Macstral

**Hold-to-dictate for your Mac — powered by Voxtral MLX, running entirely on your device.**

Macstral is a macOS menu bar app that transcribes your voice and types the result wherever your cursor is. No cloud. No subscription. No audio ever leaving your machine.

It uses [Voxtral](https://mistral.ai/news/voxtral/) — Mistral's open speech model — accelerated locally via [MLX](https://github.com/ml-explore/mlx) on Apple Silicon.

---

## Features

- **Hold to dictate** — press and hold your hotkey, speak, release. Text is inserted at the cursor.
- **Real-time streaming** — live transcript appears as you speak, not just at the end.
- **Configurable hotkey** — set any key combination (or the fn key) in Preferences.
- **Paste last transcription** — re-insert the most recent result from the menu bar at any time.
- **Works everywhere** — inserts text via the Accessibility API; falls back to paste in apps that don't support it (Electron, etc.).
- **Guided setup** — first-run onboarding walks through permissions and downloads the model automatically.

---

## Requirements

- **Apple Silicon Mac** (M1 or later) — MLX is ARM-only
- **macOS 15 Sequoia** or later

---

## Installation

**Homebrew (recommended):**

```bash
brew tap izyuumi/tap
brew install --cask macstral
```

**Direct download:**

Grab `Macstral.zip` from the [latest release](https://github.com/izyuumi/Macstral/releases/latest), unzip, and move `Macstral.app` to `/Applications`.

---

## First run

On first launch, Macstral will:

1. Ask for **Microphone** and **Accessibility** permissions
2. Download the Voxtral model (~2.4 GB, one time)
3. Start a bundled Python environment in the background

No manual setup required — the Python runtime and model are managed entirely by the app.

---

## Privacy

**Your audio never leaves your device.**

Transcription runs locally using Voxtral MLX. Macstral does not send audio, text, or any usage data to external servers. The bundled Python backend communicates only over a local WebSocket on `localhost`.

---

## License

MIT
