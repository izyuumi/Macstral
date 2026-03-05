# Changelog

## [0.3.0](https://github.com/izyuumi/Macstral/compare/v0.2.0...v0.3.0) (2026-03-05)

### Features

* model quality selector — Fast / Balanced / Accurate ([#25](https://github.com/izyuumi/Macstral/issues/25)) ([7049c9b](https://github.com/izyuumi/Macstral/commit/7049c9b3ba0b709647e846732e393ac8b88e1b1a))
* multi-language transcription ([#24](https://github.com/izyuumi/Macstral/issues/24)) ([cbd0bb4](https://github.com/izyuumi/Macstral/commit/cbd0bb473d3b92ad663735c4cfcfee4e0b51e753))
* live waveform in dictation HUD with idle breathing ([#22](https://github.com/izyuumi/Macstral/issues/22)) ([d2d0eb8](https://github.com/izyuumi/Macstral/commit/d2d0eb8f16bf1821a493ed7c2e8c90db24e8b751))
* transcript history panel with one-click copy per entry
* export transcript to .txt via NSSavePanel

## [0.2.0](https://github.com/izyuumi/Macstral/compare/v0.1.0...v0.2.0) (2026-03-05)

### Features

* add configurable hotkey via preferences window ([f5d582e](https://github.com/izyuumi/Macstral/commit/f5d582e8c22e148b60fa9c1c9bc3b7b53d33cb61))
* add paste last transcription menu item ([#13](https://github.com/izyuumi/Macstral/issues/13)) ([344c6ef](https://github.com/izyuumi/Macstral/commit/344c6ef2714ca0a94cbb4cd27f294cffabcbfa87))
* enhance WebSocket disconnection handling and improve Python backend setup ([b861bb7](https://github.com/izyuumi/Macstral/commit/b861bb711a67c08ad1a567a7f3fdf9e3d7652e8f))
* improve normal dictation flow and latency ([#12](https://github.com/izyuumi/Macstral/issues/12)) ([c384a21](https://github.com/izyuumi/Macstral/commit/c384a2104ef29b54196cbac222270761f156ec65))
* integrate voxmlx StreamingSession for true realtime streaming STT ([ddfe008](https://github.com/izyuumi/Macstral/commit/ddfe00825fec4933b1643e588bbf8a2026c6ec60))
* **onboarding:** show model preparation status ([f373089](https://github.com/izyuumi/Macstral/commit/f373089dd13b27342607d1414e3adf979bc4f0f2))
* replace SFSpeechRecognizer with Voxtral MLX via bundled Python ([99daff4](https://github.com/izyuumi/Macstral/commit/99daff42b31ddf074836177e6abf1bc6b19ea758))

### Bug Fixes

* change default hotkey to fn key ([c65509c](https://github.com/izyuumi/Macstral/commit/c65509c798a0833a0a0bc8f1d02077296e85a534))
* pin HuggingFace model URLs to commit hash, add arch check, verify non-zero file size ([9887725](https://github.com/izyuumi/Macstral/commit/9887725885ea1ee6fc32405924fe659e9574b51d))
* handle WebSocket pre-handshake failures via urlSession (_:task:didCompleteWithError:) ([4a9bf5f](https://github.com/izyuumi/Macstral/commit/4a9bf5f917b1636afcbb23dc5603cac57244146e))

### Performance Improvements

* adaptive batch threshold for faster first delta ([#11](https://github.com/izyuumi/Macstral/issues/11)) ([95c00c2](https://github.com/izyuumi/Macstral/commit/95c00c2fb18322228f7c7893264357723cafc70f))
* improve end-to-end dictation speed ([f0e72a0](https://github.com/izyuumi/Macstral/commit/f0e72a00c6d5340c909bd2f693f746e41dd91340))

## 0.1.0 (2026-03-02)

### Features

* **app:** establish app shell and shared state ([e42cee0](https://github.com/izyuumi/Macstral/commit/e42cee0e38632a80c30525f1578905f27a481aa3))
* **dictation:** add local audio transcription pipeline ([871a292](https://github.com/izyuumi/Macstral/commit/871a2927586809e4769bcc845eef35b632d198c8))
* **onboarding:** add permission-gated first-run flow ([9127d1f](https://github.com/izyuumi/Macstral/commit/9127d1f08eea67038ee484828e9d0e3bcdcefd93))
* **ui:** add hotkey-driven dictation interaction ([9926dd2](https://github.com/izyuumi/Macstral/commit/9926dd288cf4d6e52dedc314eb6ee5d09b567b94))
