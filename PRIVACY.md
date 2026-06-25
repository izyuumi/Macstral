# Macstral — Privacy Policy

_Last updated: 2026-06-17_

This Privacy Policy explains what data **Macstral** handles, why, and your rights.
Our guiding principle is simple: **by default, your audio never leaves your Mac.**

## Data Controller

**Yumi Izumi** (sole proprietor), Japan — the maker of Macstral.
Contact: **mail@yumi.to** ·
[github.com/izyuumi/Macstral](https://github.com/izyuumi/Macstral)

## 1. On-Device Speech Processing (Default / Free)

By default, Macstral's speech recognition runs **on-device** using local models
on your Apple Silicon Mac:

- Audio is captured, transcribed, and (for local notes) summarized locally.
- **No audio is uploaded.** No transcripts or notes are sent to us.
- Transcript history is stored **locally on your Mac** and can be deleted by you
  at any time.

In on-device speech mode we do not collect, transmit, or store your audio,
transcripts, or notes.

**Model download.** On first run, Macstral downloads its speech-model weights from
**Hugging Face** (`huggingface.co`). This is an anonymous file download; no audio
or personal data is sent. After download, the models run offline.

## 2. AI Writing Providers (User-Configurable)

Macstral can run a writing pass after transcription to polish dictated text or
edit selected text. The AI Writing preference lets you choose:

- **OpenAI** (default setting) using your own API key stored in Keychain.
- **OpenAI-compatible** using your configured endpoint and API key.
- **Local LLM**, which keeps the writing pass on your Mac.
- **Formatting only**, which uses deterministic punctuation and capitalization.

Online AI writing is active only when you save an API key and choose an online
provider. In that mode, Macstral sends the raw transcript, the focused app name,
and relevant selected/surrounding text context to your chosen provider solely to
return the rewritten text. Audio is not sent to AI writing providers. We do not
receive, proxy, or store your BYO API key or AI writing requests.

If an online writing request fails and local fallback is enabled, Macstral falls
back to the local/offline writing path.

## 3. Pro Cloud Processing (Opt-In)

**Macstral Pro** offers an **optional** cloud processing mode that you must
explicitly enable. When, and only when, you turn it on:

- The audio and related text needed for transcription or note generation are sent
  over an encrypted connection to our **hosted proxy** and forwarded to our
  processing provider (**Mistral AI**) solely to return your result.
- Your Pro **license key** is sent as an authentication token to authorize the
  request.
- We do **not** use your audio, transcripts, or notes to train models, and we do
  not sell them. Content is processed to return your result and is not retained by
  us beyond what is needed to complete the request. Mistral AI processes the data
  under its own terms.

If cloud processing is unavailable, Macstral automatically falls back to
on-device processing.

## 4. Purchases and License Validation

- Payments are processed by **Lemon Squeezy**, our **merchant of record**. Lemon
  Squeezy collects the billing information needed to complete your purchase (such
  as name, email, and payment details) under
  [its own privacy policy](https://www.lemonsqueezy.com/privacy). We do not
  receive or store your full payment-card details.
- To activate and validate Pro, your **license key** is exchanged with Lemon
  Squeezy's licensing service. We receive order and license metadata (such as
  order number, email, and activation status) to support and manage your license.

## 5. Sub-Processors

We use the minimum set of third parties needed to operate Macstral. Cloud
providers are engaged **only** when you configure or opt into the relevant
feature.

| Provider | Purpose | Data involved | Location | When |
|----------|---------|---------------|----------|------|
| **Lemon Squeezy** | Payments (merchant of record) + license validation | Name, email, payment details, order/license metadata | USA | On purchase / activation |
| **OpenAI** | Optional AI writing with your own API key | Raw transcript, focused app metadata, selected/surrounding text context | See OpenAI's terms | Only when OpenAI AI Writing is selected and an API key is saved |
| **User-configured OpenAI-compatible provider** | Optional AI writing with your own endpoint | Raw transcript, focused app metadata, selected/surrounding text context | Depends on your provider | Only when configured by you |
| **Mistral AI** | Pro cloud processing — transcription & note generation | Audio and transcript text sent during the request | France (EU) | Only in opt-in cloud mode |
| **Hugging Face** | One-time speech-model download | None (anonymous file download) | USA | First run only |
| **Our hosted proxy** | Routes Pro cloud requests to Mistral AI | Audio/text in transit, license key as token | Operated by us | Only in opt-in cloud mode |

## 6. AI-Generated Output

Transcriptions, auto-punctuation, and AI notes are produced by machine-learning
models and may contain errors. They are provided as productivity aids, not as a
certified or legally authoritative record. You are responsible for reviewing
output before relying on it.

## 7. Analytics and Telemetry

The Macstral app contains **no hidden analytics or telemetry** — we do not embed
third-party tracking SDKs. If our marketing website uses privacy-friendly,
aggregate analytics, that is disclosed on the website itself. If you contact
support, we process the information you choose to send us (such as your email and
message) to respond.

## 8. Data Retention

- **Local data** (audio buffers, transcripts, history) lives only on your Mac for
  as long as you keep it; delete it any time in the app.
- **AI writing API keys** are stored locally in Keychain until you remove them in
  Preferences.
- **Online AI writing content** is sent directly to your chosen provider and is
  governed by that provider's terms and retention practices.
- **Cloud-processing content** is held only transiently to complete your request
  and is not retained by us afterward.
- **License and order records** are retained while your license is active and as
  required for tax, accounting, and legal purposes.

## 9. Your Rights

Depending on where you live (including under the EU/UK **GDPR** and California
**CCPA/CPRA**), you may have the right to access, correct, delete, restrict, or
port your personal data, to object to processing, and to lodge a complaint with a
supervisory authority. We do not sell your personal data. To exercise any right,
contact **mail@yumi.to**; we aim to respond within **30 days**.

## 10. Children

Macstral is not directed to children under 13, and we do not knowingly collect
data from them.

## 11. Changes

We may update this policy as the app evolves. Material changes are reflected by
the "Last updated" date above.

## 12. Contact

**mail@yumi.to** · [github.com/izyuumi/Macstral](https://github.com/izyuumi/Macstral)
