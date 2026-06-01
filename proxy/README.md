# Macstral Cloud Proxy

The Pro online-processing backend for Macstral. It speaks the **same WebSocket protocol** as the
on-device server (`Macstral/Resources/voxtral_server.py`) but forwards work to hosted vendor APIs
(Mistral by default) instead of running MLX locally.

This is what `MacstralCloudConfig.baseURL` in the app must point at. **Deploying and securing this
service is a manual step** — like filling the Lemon Squeezy IDs.

## What it does

- `GET /healthz` — liveness probe.
- `WS /v1/stream` — authenticates the connection by validating the caller's Lemon Squeezy license
  key (sent as `Authorization: Bearer <key>`, cached briefly), then:
  - `start_session` → binary PCM-16 mono 16 kHz frames → `commit` → transcribes via the Mistral
    transcription API and returns `{"type": "done", "text": …}`.
  - `generate_notes` → summarizes the transcript via a Mistral chat model and returns
    `{"type": "notes_done", "text": …}`.

## Run locally

```sh
cd proxy
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then edit .env
set -a; source .env; set +a
uvicorn server:app --host 0.0.0.0 --port 8080
```

Point the app at it for local testing by setting `MacstralCloudConfig.baseURL` to
`http://localhost:8080` (the app derives `ws://…/v1/stream`).

## Deploy

Run behind TLS (the app uses `wss://`). Any container host works (Fly.io, Render, Cloud Run, a VM
behind nginx). Provide the env vars from `.env.example` as secrets. Then set the real host in
`Macstral/Licensing/MacstralCloudConfig.swift` (replace `REPLACE_PROXY_HOST`).

## Security notes

- `MISTRAL_API_KEY` lives only on the server; it is never shipped in the app.
- Every WebSocket is gated on a valid license key. Consider adding rate limiting / per-key quotas
  before going to production.
- The license cache trusts a prior verdict if Lemon Squeezy is briefly unreachable; tune
  `MACSTRAL_LICENSE_CACHE_TTL` to taste.

## Swapping vendors

Change `TRANSCRIBE_MODEL` / `NOTES_MODEL` (env) or the upstream calls in `server.py`
(`transcribe`, `generate_notes`). The app is agnostic — it only sees the WS protocol.
```
