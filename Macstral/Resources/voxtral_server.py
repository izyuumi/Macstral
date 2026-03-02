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
import inspect
import json
import os
import sys
import tempfile
import threading
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
try:
    from mlx_audio.stt.utils import load_model  # noqa: E402
except ImportError:
    from mlx_audio.stt.utils import load as load_model  # noqa: E402

# ---------------------------------------------------------------------------
# Global model reference (loaded once at startup)
# ---------------------------------------------------------------------------
model = None
SAMPLE_RATE = 16_000
SAMPLE_WIDTH = 2  # 16-bit PCM

# Maximum audio buffer size: ~26 minutes of PCM-16 mono 16 kHz (50 MB).
# Recordings that exceed this limit are discarded to prevent runaway memory growth.
MAX_AUDIO_BUFFER_BYTES = 50 * 1024 * 1024  # 50 MB
MIN_COMMIT_AUDIO_BYTES = 1_600


def ensure_processor_files():
    config_path = os.path.join(model_dir, "config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                config = json.load(f)
            if config.get("model_type") == "voxtral_realtime":
                config["model_type"] = "voxtral"
                with open(config_path, "w", encoding="utf-8") as f:
                    json.dump(config, f, indent=4)
        except Exception:
            pass

    preprocessor_path = os.path.join(model_dir, "preprocessor_config.json")
    if not os.path.exists(preprocessor_path):
        preprocessor_config = {
            "chunk_length": 30,
            "dither": 0.0,
            "feature_extractor_type": "WhisperFeatureExtractor",
            "feature_size": 128,
            "hop_length": 160,
            "n_fft": 400,
            "n_samples": 480000,
            "nb_max_frames": 3000,
            "padding_side": "right",
            "padding_value": 0.0,
            "processor_class": "VoxtralProcessor",
            "return_attention_mask": False,
            "sampling_rate": 16000,
        }
        with open(preprocessor_path, "w", encoding="utf-8") as f:
            json.dump(preprocessor_config, f, indent=2)

    processor_path = os.path.join(model_dir, "processor_config.json")
    if os.path.exists(processor_path):
        try:
            with open(processor_path, "r", encoding="utf-8") as f:
                processor_config = json.load(f)
            if processor_config.get("processor_class") == "VoxtralRealtimeProcessor":
                os.unlink(processor_path)
        except Exception:
            pass


def patch_transformers_config_get():
    try:
        from transformers.configuration_utils import PreTrainedConfig
    except Exception:
        return
    if hasattr(PreTrainedConfig, "get"):
        return

    def _config_get(self, key, default=None):
        return getattr(self, key, default)

    setattr(PreTrainedConfig, "get", _config_get)


def patch_transformers_processor_repr():
    try:
        from transformers.processing_utils import ProcessorMixin
    except Exception:
        return

    def _safe_processor_repr(self):
        return f"{self.__class__.__name__}()"

    setattr(ProcessorMixin, "__repr__", _safe_processor_repr)


def patch_transcription_request_streaming_default():
    try:
        from mistral_common.protocol.transcription.request import StreamingMode
        from mistral_common.protocol.transcription.request import TranscriptionRequest
    except Exception:
        return

    original_from_openai = TranscriptionRequest.from_openai.__func__

    def _from_openai_with_streaming(cls, openai_request, strict=False):
        request = original_from_openai(cls, openai_request, strict=strict)
        if getattr(request, "streaming", None) == StreamingMode.DISABLED:
            request.streaming = StreamingMode.OFFLINE
            if getattr(request, "target_streaming_delay_ms", None) is None:
                request.target_streaming_delay_ms = 480
        return request

    TranscriptionRequest.from_openai = classmethod(_from_openai_with_streaming)


def load_voxtral():
    global model
    patch_transformers_config_get()
    patch_transformers_processor_repr()
    patch_transcription_request_streaming_default()
    ensure_processor_files()
    model = load_model(model_dir, lazy=True)
    processor = getattr(model, "_processor", None)
    tokenizer = getattr(processor, "tokenizer", None)
    if tokenizer is not None:
        eos_token_ids = getattr(tokenizer, "eos_token_ids", None)
        eos_token_id = getattr(tokenizer, "eos_token_id", None)
        normalized_eos_ids = None
        if isinstance(eos_token_ids, int):
            normalized_eos_ids = [eos_token_ids]
        elif isinstance(eos_token_ids, (list, tuple)):
            normalized_eos_ids = [token_id for token_id in eos_token_ids if isinstance(token_id, int)]
        elif eos_token_ids is None and isinstance(eos_token_id, int):
            normalized_eos_ids = [eos_token_id]
        if normalized_eos_ids:
            try:
                object.__setattr__(tokenizer, "eos_token_ids", normalized_eos_ids)
            except Exception:
                pass


def transcribe_in_thread(wav_path: str, loop: asyncio.AbstractEventLoop, queue: asyncio.Queue):
    full_text = ""
    try:
        generate_sig = inspect.signature(model.generate)
        generate_kwargs = {}
        if "stream" in generate_sig.parameters:
            generate_kwargs["stream"] = True
        elif "generation_stream" in generate_sig.parameters:
            generate_kwargs["generation_stream"] = True
        if "transcription_delay_ms" in generate_sig.parameters:
            generate_kwargs["transcription_delay_ms"] = 480

        result = model.generate(wav_path, **generate_kwargs)

        if isinstance(result, str):
            full_text = result
            loop.call_soon_threadsafe(queue.put_nowait, ("done", full_text))
            return

        if hasattr(result, "text") and isinstance(result.text, str):
            full_text = result.text
            loop.call_soon_threadsafe(queue.put_nowait, ("done", full_text))
            return

        try:
            iterator = iter(result)
        except TypeError:
            full_text = str(result)
            loop.call_soon_threadsafe(queue.put_nowait, ("done", full_text))
            return

        for chunk in iterator:
            if isinstance(chunk, str):
                text = chunk
            elif hasattr(chunk, "text") and isinstance(chunk.text, str):
                text = chunk.text
            else:
                text = str(chunk)
            full_text += text
            loop.call_soon_threadsafe(queue.put_nowait, ("delta", full_text))
        loop.call_soon_threadsafe(queue.put_nowait, ("done", full_text))
    except Exception as exc:
        message = str(exc)
        if "broadcast_shapes" in message or "cannot be broadcast" in message:
            loop.call_soon_threadsafe(queue.put_nowait, ("done", full_text))
            return
        loop.call_soon_threadsafe(
            queue.put_nowait,
            ("error", f"Transcription error: {exc}"),
        )


# ---------------------------------------------------------------------------
# Audio helpers
# ---------------------------------------------------------------------------

def pcm_bytes_to_wav(pcm_data: bytes) -> str:
    """Write raw PCM-16 mono 16 kHz bytes to a temporary WAV file and return its path."""
    fd, tmp_path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        with wave.open(tmp_path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(SAMPLE_WIDTH)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(pcm_data)
    except Exception:
        os.unlink(tmp_path)
        raise
    return tmp_path


def normalize_commit_audio(pcm_data: bytes) -> bytes:
    remainder = len(pcm_data) % SAMPLE_WIDTH
    if remainder == 0:
        return pcm_data
    trimmed_length = len(pcm_data) - remainder
    if trimmed_length <= 0:
        return b""
    return pcm_data[:trimmed_length]


# ---------------------------------------------------------------------------
# WebSocket handler
# ---------------------------------------------------------------------------

async def handle_client(websocket):
    """Handle a single WebSocket client session."""
    audio_buffer = bytearray()

    async for message in websocket:
        if isinstance(message, bytes):
            # Accumulate PCM-16 audio data, enforcing the buffer size limit.
            if len(audio_buffer) + len(message) > MAX_AUDIO_BUFFER_BYTES:
                audio_buffer.clear()
                await websocket.send(
                    json.dumps(
                        {
                            "type": "error",
                            "text": "Audio buffer limit exceeded; recording discarded.",
                        }
                    )
                )
                continue
            audio_buffer.extend(message)
        elif isinstance(message, str):
            if message.strip().lower() == "commit":
                if not audio_buffer:
                    await websocket.send(
                        json.dumps({"type": "done", "text": ""})
                    )
                    continue

                normalized_audio = normalize_commit_audio(bytes(audio_buffer))
                if len(normalized_audio) < MIN_COMMIT_AUDIO_BYTES:
                    await websocket.send(
                        json.dumps({"type": "done", "text": ""})
                    )
                    continue

                wav_path = pcm_bytes_to_wav(normalized_audio)

                try:
                    loop = asyncio.get_running_loop()
                    queue: asyncio.Queue[tuple[str, str]] = asyncio.Queue()
                    thread = threading.Thread(
                        target=transcribe_in_thread,
                        args=(wav_path, loop, queue),
                        daemon=True,
                    )
                    thread.start()

                    while True:
                        message_type, text = await queue.get()
                        await websocket.send(
                            json.dumps({"type": message_type, "text": text})
                        )
                        if message_type in {"done", "error"}:
                            break
                finally:
                    try:
                        os.unlink(wav_path)
                    except OSError:
                        pass


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main():
    print("loading_model", flush=True)
    try:
        load_voxtral()
    except Exception as exc:
        print(f"startup_error:{exc}", file=sys.stderr, flush=True)
        raise

    server = await websockets.serve(handle_client, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]

    print(port, flush=True)

    await server.wait_closed()


if __name__ == "__main__":
    asyncio.run(main())
