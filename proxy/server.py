#!/usr/bin/env python3
"""
Macstral cloud proxy — the Pro online-processing backend.

Speaks the SAME WebSocket JSON/binary protocol as the on-device server
(`Macstral/Resources/voxtral_server.py`), so the macOS app only has to point its existing
clients at this host and add an `Authorization: Bearer <license-key>` header:

  • Client → server JSON  {"cmd": "start_session", "language": "en"?}
  • Client → server binary frames                                       raw PCM-16 mono 16 kHz
  • Client → server text  "commit"                                      finalize → emit transcript
  • Client → server JSON  {"cmd": "generate_notes", "transcript": "…"}

  • Server → client JSON  {"type": "session_created"}
  • Server → client JSON  {"type": "done", "text": "…"}
  • Server → client JSON  {"type": "notes_done", "text": "…"}
  • Server → client JSON  {"type": "error", "text": "…"}

Difference from the local server: instead of running MLX locally, it forwards audio to the
Mistral transcription API (Voxtral) and transcripts to a Mistral chat model. The connecting
client is authenticated by validating its Lemon Squeezy license key (cached briefly).

This is a deploy-it-yourself scaffold. Secrets come from the environment only — never commit
them. See README.md.
"""
from __future__ import annotations

import io
import json
import os
import struct
import time
import wave

import httpx
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, status

# ---------------------------------------------------------------------------
# Configuration (environment only)
# ---------------------------------------------------------------------------

MISTRAL_API_KEY = os.environ.get("MISTRAL_API_KEY", "")
LEMONSQUEEZY_API_BASE = "https://api.lemonsqueezy.com/v1"
MISTRAL_API_BASE = "https://api.mistral.ai/v1"

# Default upstream models — swap here without touching the app.
TRANSCRIBE_MODEL = os.environ.get("MACSTRAL_TRANSCRIBE_MODEL", "voxtral-mini-latest")
NOTES_MODEL = os.environ.get("MACSTRAL_NOTES_MODEL", "mistral-small-latest")

# How long a validated license key is trusted before re-validating (seconds).
LICENSE_CACHE_TTL = int(os.environ.get("MACSTRAL_LICENSE_CACHE_TTL", "900"))

SAMPLE_RATE = 16_000

NOTES_SYSTEM_PROMPT = (
    "You are a helpful assistant that writes clear, concise meeting notes from a transcript. "
    "Summarize the key points, decisions, and action items as Markdown with short bullet points. "
    "Do not invent details that are not in the transcript."
)

app = FastAPI(title="Macstral Cloud Proxy")

# key -> (expiry_epoch, is_valid)
_license_cache: dict[str, tuple[float, bool]] = {}


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

async def validate_license(key: str) -> bool:
    """Validate a Lemon Squeezy license key, with a short-TTL in-memory cache."""
    now = time.monotonic()
    cached = _license_cache.get(key)
    if cached and cached[0] > now:
        return cached[1]

    valid = False
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                f"{LEMONSQUEEZY_API_BASE}/licenses/validate",
                headers={"Accept": "application/json"},
                data={"license_key": key},
            )
            if resp.status_code == 200:
                valid = bool(resp.json().get("valid", False))
    except httpx.HTTPError:
        # On a transient Lemon Squeezy outage, fall back to any prior cached verdict.
        if cached:
            return cached[1]
        valid = False

    _license_cache[key] = (now + LICENSE_CACHE_TTL, valid)
    return valid


def bearer_token(websocket: WebSocket) -> str | None:
    header = websocket.headers.get("authorization", "")
    if header.lower().startswith("bearer "):
        return header[7:].strip()
    return None


# ---------------------------------------------------------------------------
# Upstream calls (Mistral)
# ---------------------------------------------------------------------------

def pcm_to_wav(pcm: bytes) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)  # PCM-16
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm)
    return buf.getvalue()


async def transcribe(pcm: bytes, language: str | None) -> str:
    if not pcm:
        return ""
    wav_bytes = pcm_to_wav(pcm)
    data = {"model": TRANSCRIBE_MODEL}
    if language and language != "auto":
        data["language"] = language
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(
            f"{MISTRAL_API_BASE}/audio/transcriptions",
            headers={"Authorization": f"Bearer {MISTRAL_API_KEY}"},
            data=data,
            files={"file": ("audio.wav", wav_bytes, "audio/wav")},
        )
        resp.raise_for_status()
        return (resp.json().get("text") or "").strip()


async def generate_notes(transcript: str) -> str:
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(
            f"{MISTRAL_API_BASE}/chat/completions",
            headers={"Authorization": f"Bearer {MISTRAL_API_KEY}"},
            json={
                "model": NOTES_MODEL,
                "temperature": 0.2,
                "messages": [
                    {"role": "system", "content": NOTES_SYSTEM_PROMPT},
                    {"role": "user", "content": f"Transcript:\n\n{transcript}\n\nWrite the notes."},
                ],
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/healthz")
async def healthz():
    return {"ok": True}


@app.websocket("/v1/stream")
async def stream(websocket: WebSocket):
    token = bearer_token(websocket)
    if not token or not await validate_license(token):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await websocket.accept()

    language: str | None = None
    audio = bytearray()
    in_session = False

    try:
        while True:
            message = await websocket.receive()

            if message.get("bytes") is not None:
                if in_session:
                    audio.extend(message["bytes"])
                continue

            text = message.get("text")
            if text is None:
                continue

            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                payload = {"cmd": "commit"} if text == "commit" else {}

            cmd = payload.get("cmd")
            if cmd == "start_session":
                language = payload.get("language")
                audio.clear()
                in_session = True
                await websocket.send_text(json.dumps({"type": "session_created"}))

            elif cmd == "commit":
                if not in_session:
                    await websocket.send_text(json.dumps({"type": "error", "text": "no active session"}))
                    continue
                try:
                    result = await transcribe(bytes(audio), language)
                    await websocket.send_text(json.dumps({"type": "done", "text": result}))
                except httpx.HTTPError as exc:
                    await websocket.send_text(json.dumps({"type": "error", "text": str(exc)}))
                audio.clear()
                in_session = False

            elif cmd == "generate_notes":
                try:
                    notes = await generate_notes(payload.get("transcript", ""))
                    await websocket.send_text(json.dumps({"type": "notes_done", "text": notes}))
                except (httpx.HTTPError, KeyError, IndexError) as exc:
                    await websocket.send_text(json.dumps({"type": "error", "text": str(exc)}))

            else:
                await websocket.send_text(json.dumps({"type": "error", "text": f"unknown cmd: {cmd}"}))

    except WebSocketDisconnect:
        return


# Silence unused-import lint for struct (kept for future framed-protocol use).
_ = struct
