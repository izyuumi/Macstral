# Changelog

## [0.2.0](https://github.com/izyuumi/Macstral/compare/v0.1.0...v0.2.0) (2026-03-05)


### Features

* add configurable hotkey via preferences window ([f5d582e](https://github.com/izyuumi/Macstral/commit/f5d582e8c22e148b60fa9c1c9bc3b7b53d33cb61))
* add configurable hotkey via preferences window ([870befe](https://github.com/izyuumi/Macstral/commit/870befe4794bd38dee1cfa77a932c3882f392a57))
* add paste last transcription menu item ([#13](https://github.com/izyuumi/Macstral/issues/13)) ([344c6ef](https://github.com/izyuumi/Macstral/commit/344c6ef2714ca0a94cbb4cd27f294cffabcbfa87))
* enhance WebSocket disconnection handling and improve Python backend setup ([b861bb7](https://github.com/izyuumi/Macstral/commit/b861bb711a67c08ad1a567a7f3fdf9e3d7652e8f))
* improve normal dictation flow and latency ([#12](https://github.com/izyuumi/Macstral/issues/12)) ([c384a21](https://github.com/izyuumi/Macstral/commit/c384a2104ef29b54196cbac222270761f156ec65))
* integrate voxmlx StreamingSession for true realtime streaming STT ([ddfe008](https://github.com/izyuumi/Macstral/commit/ddfe00825fec4933b1643e588bbf8a2026c6ec60))
* live waveform in dictation HUD with idle breathing (0.3.0) ([#22](https://github.com/izyuumi/Macstral/issues/22)) ([d2d0eb8](https://github.com/izyuumi/Macstral/commit/d2d0eb8f16bf1821a493ed7c2e8c90db24e8b751))
* multi-language transcription (0.3.0) ([#24](https://github.com/izyuumi/Macstral/issues/24)) ([cbd0bb4](https://github.com/izyuumi/Macstral/commit/cbd0bb473d3b92ad663735c4cfcfee4e0b51e753))
* **onboarding:** show model preparation status ([f373089](https://github.com/izyuumi/Macstral/commit/f373089dd13b27342607d1414e3adf979bc4f0f2))
* replace SFSpeechRecognizer with Voxtral MLX via bundled Python ([99daff4](https://github.com/izyuumi/Macstral/commit/99daff42b31ddf074836177e6abf1bc6b19ea758))
* replace SFSpeechRecognizer with Voxtral MLX via bundled Python ([501f6c4](https://github.com/izyuumi/Macstral/commit/501f6c4336f2858bc61a8adebb41c7bce2fd8ebc))


### Bug Fixes

* address CodeRabbit and Copilot review feedback ([c050ef1](https://github.com/izyuumi/Macstral/commit/c050ef16e187c6d947daefc27f45db1f794215eb))
* address CodeRabbit review feedback (buffer limit, connection guard, checksum, cancellation, late handshake) ([98a4ebe](https://github.com/izyuumi/Macstral/commit/98a4ebed3a5128061c4874f60527f875b09863d9))
* address Copilot review feedback ([bfa9ffa](https://github.com/izyuumi/Macstral/commit/bfa9ffa11ea66fa224be86ae7c29f62b740770b6))
* address Copilot review feedback on HotkeyManager ([e40362e](https://github.com/izyuumi/Macstral/commit/e40362ebe0ade42cd60faafb516ec046bbab7ecc))
* address port detection, startup termination, key-up, and buffered speech issues ([7706982](https://github.com/izyuumi/Macstral/commit/7706982471bc6d51430d1c28cbcab0e35d5f1382))
* change default hotkey to fn key ([c65509c](https://github.com/izyuumi/Macstral/commit/c65509c798a0833a0a0bc8f1d02077296e85a534))
* change default hotkey to fn key ([b7d1cfc](https://github.com/izyuumi/Macstral/commit/b7d1cfc96302f1b1fdddca795e7c45bd43d2b8a1))
* correct tapBufferSize comment from ~0.3 s to ~0.064 s at 16 kHz ([71cfedb](https://github.com/izyuumi/Macstral/commit/71cfedb07df492b820bd611d9c7faea36f34f502))
* guard didFinishDownloadingTo against stale callbacks from cancelled/superseded tasks ([68b8f9a](https://github.com/izyuumi/Macstral/commit/68b8f9a1c6b9a106ce3b65474fd985f366ea4377))
* handle WebSocket pre-handshake failures via urlSession(_:task:didCompleteWithError:) ([4a9bf5f](https://github.com/izyuumi/Macstral/commit/4a9bf5f917b1636afcbb23dc5603cac57244146e))
* lower deployment target to 15.0 for CI compatibility ([b6076be](https://github.com/izyuumi/Macstral/commit/b6076be9121d36f41ce2d3a3d1c023805866d18d))
* pin HuggingFace model URLs to commit hash, add arch check, verify non-zero file size ([9887725](https://github.com/izyuumi/Macstral/commit/9887725885ea1ee6fc32405924fe659e9574b51d))
* pin voxmlx install to immutable commit hash 48bfdec9 ([6c26c10](https://github.com/izyuumi/Macstral/commit/6c26c100b0bc0389a7b57bd1f8cde7d422e23425))
* report downloadingModel step accurately; mark complete only after voxmlx loads model ([2dc6e90](https://github.com/izyuumi/Macstral/commit/2dc6e90cdfcba0cbd00ae6858b8934ffbe22a62f))
* resolve release-please config conflict and add missing version.txt ([#8](https://github.com/izyuumi/Macstral/issues/8)) ([b253d9a](https://github.com/izyuumi/Macstral/commit/b253d9a713f55a15e8428611c5744264d83cee57))
* stabilize realtime dictation commit flow ([768bd9d](https://github.com/izyuumi/Macstral/commit/768bd9d96cf0a29b3923f78c427181d25ef6c1ae))
* trim leading newline from live transcript deltas ([3830b2a](https://github.com/izyuumi/Macstral/commit/3830b2a2557fb31f9a14521152a445617958bd61))
* unwrap optional Double before XCTAssertEqual with accuracy ([40f654e](https://github.com/izyuumi/Macstral/commit/40f654ef0906ecba3e889940b7661742e51de088))


### Performance Improvements

* adaptive batch threshold for faster first delta ([#11](https://github.com/izyuumi/Macstral/issues/11)) ([95c00c2](https://github.com/izyuumi/Macstral/commit/95c00c2fb18322228f7c7893264357723cafc70f))
* improve end-to-end dictation speed ([f0e72a0](https://github.com/izyuumi/Macstral/commit/f0e72a00c6d5340c909bd2f693f746e41dd91340))
* reduce startup transcription lag ([2c9f326](https://github.com/izyuumi/Macstral/commit/2c9f3268194e9f8ede17cb78b0a53a53bcb4e3fd))

## 0.1.0 (2026-03-02)


### Features

* **app:** establish app shell and shared state ([e42cee0](https://github.com/izyuumi/Macstral/commit/e42cee0e38632a80c30525f1578905f27a481aa3))
* **dictation:** add local audio transcription pipeline ([871a292](https://github.com/izyuumi/Macstral/commit/871a2927586809e4769bcc845eef35b632d198c8))
* **onboarding:** add permission-gated first-run flow ([9127d1f](https://github.com/izyuumi/Macstral/commit/9127d1f08eea67038ee484828e9d0e3bcdcefd93))
* **ui:** add hotkey-driven dictation interaction ([9926dd2](https://github.com/izyuumi/Macstral/commit/9926dd288cf4d6e52dedc314eb6ee5d09b567b94))


### Miscellaneous Chores

* **release:** update version to 0.1.0 in release manifest ([97fcfba](https://github.com/izyuumi/Macstral/commit/97fcfba75f515b79c08e0c1a7d3f7d6ba4fdf869))
