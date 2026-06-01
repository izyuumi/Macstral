# Macstral — Privacy Policy

_Last updated: 2026-06-01_

This Privacy Policy explains what data **Macstral** handles, why, and your rights.
Our guiding principle is simple: **by default, your audio never leaves your Mac.**

## Data Controller

**Yumi Izumi** (sole proprietor), Japan — the maker of Macstral.
Contact: **mail@yumi.to** ·
[github.com/izyuumi/Macstral](https://github.com/izyuumi/Macstral)

## 1. On-Device Processing (Default / Free)

By default, Macstral runs **entirely on-device** using local models on your Apple
Silicon Mac:

- Audio is captured, transcribed, and (for notes) summarized locally.
- **No audio is uploaded.** No transcripts or notes are sent to us.
- Transcript history is stored **locally on your Mac** and can be deleted by you
  at any time.

In on-device mode we do not collect, transmit, or store your audio, transcripts,
or notes.

**Model download.** On first run, Macstral downloads its speech-model weights from
**Hugging Face** (`huggingface.co`). This is an anonymous file download; no audio
or personal data is sent. After download, the models run fully offline.

## 2. Pro Cloud Processing (Opt-In)

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

## 3. Purchases and License Validation

- Payments are processed by **Lemon Squeezy**, our **merchant of record**. Lemon
  Squeezy collects the billing information needed to complete your purchase (such
  as name, email, and payment details) under
  [its own privacy policy](https://www.lemonsqueezy.com/privacy). We do not
  receive or store your full payment-card details.
- To activate and validate Pro, your **license key** is exchanged with Lemon
  Squeezy's licensing service. We receive order and license metadata (such as
  order number, email, and activation status) to support and manage your license.

## 4. Sub-Processors

We use the minimum set of third parties needed to operate Macstral. Cloud
providers are engaged **only** when you opt into the relevant feature.

| Provider | Purpose | Data involved | Location | When |
|----------|---------|---------------|----------|------|
| **Lemon Squeezy** | Payments (merchant of record) + license validation | Name, email, payment details, order/license metadata | USA | On purchase / activation |
| **Mistral AI** | Pro cloud processing — transcription & note generation | Audio and transcript text sent during the request | France (EU) | Only in opt-in cloud mode |
| **Hugging Face** | One-time speech-model download | None (anonymous file download) | USA | First run only |
| **Our hosted proxy** | Routes Pro cloud requests to Mistral AI | Audio/text in transit, license key as token | Operated by us | Only in opt-in cloud mode |

## 5. AI-Generated Output

Transcriptions, auto-punctuation, and AI notes are produced by machine-learning
models and may contain errors. They are provided as productivity aids, not as a
certified or legally authoritative record. You are responsible for reviewing
output before relying on it.

## 6. Analytics and Telemetry

The Macstral app contains **no hidden analytics or telemetry** — we do not embed
third-party tracking SDKs. If our marketing website uses privacy-friendly,
aggregate analytics, that is disclosed on the website itself. If you contact
support, we process the information you choose to send us (such as your email and
message) to respond.

## 7. Data Retention

- **Local data** (audio buffers, transcripts, history) lives only on your Mac for
  as long as you keep it; delete it any time in the app.
- **Cloud-processing content** is held only transiently to complete your request
  and is not retained by us afterward.
- **License and order records** are retained while your license is active and as
  required for tax, accounting, and legal purposes.

## 8. Your Rights

Depending on where you live (including under the EU/UK **GDPR** and California
**CCPA/CPRA**), you may have the right to access, correct, delete, restrict, or
port your personal data, to object to processing, and to lodge a complaint with a
supervisory authority. We do not sell your personal data. To exercise any right,
contact **mail@yumi.to**; we aim to respond within **30 days**.

## 9. Children

Macstral is not directed to children under 13, and we do not knowingly collect
data from them.

## 10. Changes

We may update this policy as the app evolves. Material changes are reflected by
the "Last updated" date above.

## 11. Contact

**mail@yumi.to** · [github.com/izyuumi/Macstral](https://github.com/izyuumi/Macstral)
