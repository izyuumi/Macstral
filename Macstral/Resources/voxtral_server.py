#!/usr/bin/env python3
"""
Granite Speech WebSocket inference server for Macstral.

Uses mlx_audio.stt for on-device speech-to-text transcription.
Audio is collected and transcribed in one shot after commit.

Protocol:
  - Client sends binary frames: raw PCM-16 LE mono 16 kHz audio chunks.
  - Client sends text frame "commit" to signal end of utterance.
  - Server sends JSON text frames:
      {"type": "done", "text": "final transcript..."}
"""

import asyncio
import json
import os
import sys
import tempfile
import wave

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
env_dir = os.environ.get("MACSTRAL_ENV_DIR", "")
if env_dir and env_dir not in sys.path:
    sys.path.insert(0, env_dir)

# ---------------------------------------------------------------------------
# Lazy-load heavy deps after sys.path is configured
# ---------------------------------------------------------------------------
import numpy as np  # noqa: E402
import websockets  # noqa: E402
from mlx_audio.stt.utils import load_model  # noqa: E402
from mlx_audio.stt.generate import generate_transcription  # noqa: E402

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
MODEL_ID = os.environ.get(
    "MACSTRAL_MODEL_ID",
    "mlx-community/granite-4.0-1b-speech-8bit",
)
_model_dir = os.environ.get("MACSTRAL_MODEL_DIR", "")
if _model_dir:
    os.environ.setdefault("HF_HOME", _model_dir)
    os.environ.setdefault("HUGGINGFACE_HUB_CACHE", _model_dir)

DEBUG_TRANSCRIPTION = os.environ.get("MACSTRAL_DEBUG_TRANSCRIPTION", "").lower() in {"1", "true", "yes"}

SAMPLE_RATE = 16_000

# ---------------------------------------------------------------------------
# Global model reference (loaded once at startup)
# ---------------------------------------------------------------------------
stt_model = None


def log(msg: str, *, force: bool = False):
    if not force and not DEBUG_TRANSCRIPTION:
        return
    print(msg, file=sys.stderr, flush=True)


def _write_wav(path: str, pcm_f32: np.ndarray) -> None:
    """Write float32 PCM to a 16-bit WAV file at SAMPLE_RATE."""
    pcm_i16 = (pcm_f32 * 32767.0).clip(-32768, 32767).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm_i16.tobytes())


def load_granite() -> None:
    global stt_model
    log("[server] Loading Granite speech model...", force=True)
    stt_model = load_model(MODEL_ID)
    log("[server] Warming up model (1s silent audio)...", force=True)
    try:
        silence = np.zeros(SAMPLE_RATE, dtype=np.float32)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            warmup_path = f.name
        _write_wav(warmup_path, silence)
        generate_transcription(model=stt_model, audio_path=warmup_path, format="txt", verbose=False)
        os.unlink(warmup_path)
        log("[server] Warm-up complete", force=True)
    except Exception as exc:
        log(f"[server] Warm-up failed (non-fatal): {exc}", force=True)


async def _transcribe(audio_buffer: np.ndarray) -> str:
    """Write buffer to a temp WAV, transcribe with Granite, and return text."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp_path = f.name
    _write_wav(tmp_path, audio_buffer)
    try:
        result = await asyncio.to_thread(
            generate_transcription,
            model=stt_model,
            audio_path=tmp_path,
            format="txt",
            verbose=False,
        )
        text = getattr(result, "text", str(result) if result else "")
        return (text or "").strip()
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# WebSocket handler
# ---------------------------------------------------------------------------

async def handle_client(websocket):
    log("[server] Client connected", force=True)
    audio_buffer = np.array([], dtype=np.float32)

    async for message in websocket:
        if isinstance(message, bytes):
            if len(message) % 2 != 0:
                await websocket.send(json.dumps({"type": "error", "text": "Invalid PCM frame size"}))
                continue
            audio_f32 = np.frombuffer(message, dtype=np.int16).astype(np.float32) / 32768.0
            audio_buffer = np.concatenate([audio_buffer, audio_f32])

        elif isinstance(message, str):
            cmd = message.strip().lower()
            start_json: dict | None = None
            if message.strip().startswith("{"):
                try:
                    start_json = json.loads(message)
                except json.JSONDecodeError:
                    pass
            is_start_session = (
                cmd == "start_session"
                or (start_json is not None and start_json.get("cmd") == "start_session")
            )

            if is_start_session:
                log("[server] Received start_session", force=True)
                audio_buffer = np.array([], dtype=np.float32)

            elif cmd == "commit":
                if len(audio_buffer) == 0:
                    await websocket.send(json.dumps({"type": "done", "text": ""}))
                    continue
                duration = len(audio_buffer) / SAMPLE_RATE
                log(f"[server] Received commit, transcribing {duration:.1f}s of audio...", force=True)
                text = await _transcribe(audio_buffer)
                log(f"[server] Transcription: \"{text[:80]}\"", force=True)
                await websocket.send(json.dumps({"type": "done", "text": text}))
                audio_buffer = np.array([], dtype=np.float32)

    log("[server] Client disconnected", force=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main():
    print("loading_model", flush=True)
    try:
        load_granite()
    except Exception as exc:
        print(f"startup_error:{exc}", file=sys.stderr, flush=True)
        raise

    server = await websockets.serve(handle_client, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    print(port, flush=True)
    await server.wait_closed()


if __name__ == "__main__":
    asyncio.run(main())
