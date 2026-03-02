#!/usr/bin/env python3
"""
Voxtral WebSocket inference server for Macstral.

Loads the Voxtral Mini 4B model via mlx-audio and serves a WebSocket endpoint
that accepts PCM-16 mono 16 kHz audio chunks and returns JSON transcription messages.

Protocol:
  - Client sends binary frames: raw PCM-16 LE mono 16 kHz audio chunks.
  - Client sends text frame "commit" to signal end of utterance.
  - Server sends JSON text frames:
      {"type": "delta", "text": "partial transcript..."}
      {"type": "done",  "text": "final transcript..."}
"""

import asyncio
import json
import os
import struct
import sys
import tempfile
import wave

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
env_dir = os.environ.get("MACSTRAL_ENV_DIR", "")
if env_dir and env_dir not in sys.path:
    sys.path.insert(0, env_dir)

model_dir = os.environ.get(
    "MACSTRAL_MODEL_DIR",
    os.path.expanduser(
        "~/Library/Application Support/Macstral/models/voxtral-4bit"
    ),
)

# ---------------------------------------------------------------------------
# Lazy-load heavy deps after sys.path is configured
# ---------------------------------------------------------------------------
import websockets  # noqa: E402
from mlx_audio.stt.utils import load as load_model  # noqa: E402

# ---------------------------------------------------------------------------
# Global model reference (loaded once at startup)
# ---------------------------------------------------------------------------
model = None
SAMPLE_RATE = 16_000
SAMPLE_WIDTH = 2  # 16-bit PCM


def load_voxtral():
    global model
    model = load_model(model_dir)


# ---------------------------------------------------------------------------
# Audio helpers
# ---------------------------------------------------------------------------

def pcm_bytes_to_wav(pcm_data: bytes) -> str:
    """Write raw PCM-16 mono 16 kHz bytes to a temporary WAV file and return its path."""
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    try:
        with wave.open(tmp.name, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(SAMPLE_WIDTH)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(pcm_data)
    except Exception:
        os.unlink(tmp.name)
        raise
    return tmp.name


# ---------------------------------------------------------------------------
# WebSocket handler
# ---------------------------------------------------------------------------

async def handle_client(websocket):
    """Handle a single WebSocket client session."""
    audio_buffer = bytearray()

    async for message in websocket:
        if isinstance(message, bytes):
            # Accumulate PCM-16 audio data
            audio_buffer.extend(message)
        elif isinstance(message, str):
            if message.strip().lower() == "commit":
                if not audio_buffer:
                    await websocket.send(
                        json.dumps({"type": "done", "text": ""})
                    )
                    continue

                # Write accumulated audio to a temp WAV file
                wav_path = pcm_bytes_to_wav(bytes(audio_buffer))
                audio_buffer.clear()

                try:
                    # Stream transcription
                    full_text = ""
                    for chunk in model.generate(
                        wav_path,
                        stream=True,
                        transcription_delay_ms=480,
                    ):
                        text = chunk if isinstance(chunk, str) else str(chunk)
                        full_text += text
                        await websocket.send(
                            json.dumps({"type": "delta", "text": full_text})
                        )
                    # Send final result
                    await websocket.send(
                        json.dumps({"type": "done", "text": full_text})
                    )
                except Exception as exc:
                    await websocket.send(
                        json.dumps(
                            {"type": "error", "text": f"Transcription error: {exc}"}
                        )
                    )
                finally:
                    try:
                        os.unlink(wav_path)
                    except OSError:
                        pass


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main():
    # Load model before accepting connections
    print("loading_model", flush=True)
    load_voxtral()

    # Bind to a random available port on localhost
    server = await websockets.serve(handle_client, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]

    # Print port number so the Swift host can read it from stdout
    print(port, flush=True)

    await server.wait_closed()


if __name__ == "__main__":
    asyncio.run(main())
