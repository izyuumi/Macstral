# Changelog

## [0.2.0](https://github.com/izyuumi/Macstral/compare/v0.1.0...v0.2.0) (2026-03-05)

### Features

* add configurable hotkey via preferences window
* add paste last transcription menu item ([#13](https://github.com/izyuumi/Macstral/issues/13))
* enhance WebSocket disconnection handling and improve Python backend setup
* improve normal dictation flow and latency ([#12](https://github.com/izyuumi/Macstral/issues/12))
* integrate voxmlx StreamingSession for true realtime streaming STT
* live waveform in dictation HUD with idle breathing ([#22](https://github.com/izyuumi/Macstral/issues/22))
* multi-language transcription ([#24](https://github.com/izyuumi/Macstral/issues/24))
* model quality selector — Fast / Balanced / Accurate ([#25](https://github.com/izyuumi/Macstral/issues/25))
* **onboarding:** show model preparation status
* replace SFSpeechRecognizer with Voxtral MLX via bundled Python

### Bug Fixes

* address CodeRabbit and Copilot review feedback
* change default hotkey to fn key
* guard didFinishDownloadingTo against stale callbacks
* handle WebSocket pre-handshake failures
* lower deployment target to 15.0 for CI compatibility
* pin HuggingFace model URLs to commit hash, add arch check, verify non-zero file size
* pin voxmlx install to immutable commit hash
* report downloadingModel step accurately

### Performance Improvements

* adaptive batch threshold for faster first delta ([#11](https://github.com/izyuumi/Macstral/issues/11))
* improve end-to-end dictation speed
* reduce startup transcription lag

## 0.1.0 (2026-03-02)

### Features

* **app:** establish app shell and shared state
* **dictation:** add local audio transcription pipeline
* **onboarding:** add permission-gated first-run flow
* **ui:** add hotkey-driven dictation interaction

### Miscellaneous Chores

* **release:** update version to 0.1.0 in release manifest
