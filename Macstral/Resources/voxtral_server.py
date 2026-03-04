#!/usr/bin/env python3
"""
Voxtral WebSocket inference server for Macstral (streaming edition).

Uses T0mSIlver/voxmlx StreamingSession for true realtime streaming STT.
Audio is transcribed incrementally as chunks arrive — text appears in the HUD
while the user is still speaking.

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
import re
import sys
import time

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
env_dir = os.environ.get("MACSTRAL_ENV_DIR", "")
if env_dir and env_dir not in sys.path:
    sys.path.insert(0, env_dir)

# ---------------------------------------------------------------------------
# Lazy-load heavy deps after sys.path is configured
# ---------------------------------------------------------------------------
import mlx.core as mx  # noqa: E402
import mlx.nn as nn  # noqa: E402
import numpy as np  # noqa: E402
import websockets  # noqa: E402

# ---------------------------------------------------------------------------
# Patch voxmlx to support the mlx-audio quantised config/weight format
# used by mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit.
# ---------------------------------------------------------------------------
import voxmlx.weights as _vw  # noqa: E402
from voxmlx.model import VoxtralRealtime  # noqa: E402

# mlx-audio weight names → voxmlx weight names
_MLX_AUDIO_REMAP = [
    # Decoder → language_model
    (r"decoder\.layers\.(\d+)\.attention\.wq\.(.*)", r"language_model.layers.\1.attention.q_proj.\2"),
    (r"decoder\.layers\.(\d+)\.attention\.wk\.(.*)", r"language_model.layers.\1.attention.k_proj.\2"),
    (r"decoder\.layers\.(\d+)\.attention\.wv\.(.*)", r"language_model.layers.\1.attention.v_proj.\2"),
    (r"decoder\.layers\.(\d+)\.attention\.wo\.(.*)", r"language_model.layers.\1.attention.o_proj.\2"),
    (r"decoder\.layers\.(\d+)\.attention_norm\.(.*)", r"language_model.layers.\1.attn_norm.\2"),
    (r"decoder\.layers\.(\d+)\.feed_forward_w1\.(.*)", r"language_model.layers.\1.mlp.gate_proj.\2"),
    (r"decoder\.layers\.(\d+)\.feed_forward_w2\.(.*)", r"language_model.layers.\1.mlp.down_proj.\2"),
    (r"decoder\.layers\.(\d+)\.feed_forward_w3\.(.*)", r"language_model.layers.\1.mlp.up_proj.\2"),
    (r"decoder\.layers\.(\d+)\.ffn_norm\.(.*)", r"language_model.layers.\1.ffn_norm.\2"),
    (r"decoder\.layers\.(\d+)\.ada_rms_norm_t_cond\.ada_down\.(.*)", r"language_model.layers.\1.ada_norm.linear_in.\2"),
    (r"decoder\.layers\.(\d+)\.ada_rms_norm_t_cond\.ada_up\.(.*)", r"language_model.layers.\1.ada_norm.linear_out.\2"),
    (r"decoder\.norm\.(.*)", r"language_model.norm.\1"),
    (r"decoder\.tok_embeddings\.(.*)", r"language_model.embed_tokens.\1"),
    # Encoder convs
    (r"encoder\.conv_layers_0_conv\.conv\.(.*)", r"encoder.conv1.\1"),
    (r"encoder\.conv_layers_1_conv\.conv\.(.*)", r"encoder.conv2.\1"),
    # Encoder transformer layers
    (r"encoder\.transformer_layers\.(\d+)\.attention\.wq\.(.*)", r"encoder.layers.\1.attention.q_proj.\2"),
    (r"encoder\.transformer_layers\.(\d+)\.attention\.wk\.(.*)", r"encoder.layers.\1.attention.k_proj.\2"),
    (r"encoder\.transformer_layers\.(\d+)\.attention\.wv\.(.*)", r"encoder.layers.\1.attention.v_proj.\2"),
    (r"encoder\.transformer_layers\.(\d+)\.attention\.wo\.(.*)", r"encoder.layers.\1.attention.o_proj.\2"),
    (r"encoder\.transformer_layers\.(\d+)\.attention_norm\.(.*)", r"encoder.layers.\1.attn_norm.\2"),
    (r"encoder\.transformer_layers\.(\d+)\.feed_forward_w1\.(.*)", r"encoder.layers.\1.mlp.gate_proj.\2"),
    (r"encoder\.transformer_layers\.(\d+)\.feed_forward_w2\.(.*)", r"encoder.layers.\1.mlp.down_proj.\2"),
    (r"encoder\.transformer_layers\.(\d+)\.feed_forward_w3\.(.*)", r"encoder.layers.\1.mlp.up_proj.\2"),
    (r"encoder\.transformer_layers\.(\d+)\.ffn_norm\.(.*)", r"encoder.layers.\1.ffn_norm.\2"),
    (r"encoder\.transformer_norm\.(.*)", r"encoder.norm.\1"),
    # Adapter
    (r"encoder\.audio_language_projection_0\.(.*)", r"adapter.w_in.\1"),
    (r"encoder\.audio_language_projection_2\.(.*)", r"adapter.w_out.\1"),
]


def _remap_mlx_audio_weight(name: str) -> str | None:
    for pattern, replacement in _MLX_AUDIO_REMAP:
        new_name, n = re.subn(f"^{pattern}$", replacement, name)
        if n > 0:
            return new_name
    return None


def _transform_mlx_audio_config(cfg: dict) -> dict:
    """Transform mlx-audio flat config to voxmlx nested format."""
    decoder = cfg["decoder"]
    encoder_args = cfg["encoder_args"].copy()
    downsample_factor = encoder_args.pop("downsample_factor", 4)
    return {
        "multimodal": {
            "whisper_model_args": {
                "encoder_args": encoder_args,
                "downsample_args": {"downsample_factor": downsample_factor},
            },
        },
        "dim": decoder["dim"],
        "n_layers": decoder["n_layers"],
        "n_heads": decoder["n_heads"],
        "n_kv_heads": decoder["n_kv_heads"],
        "head_dim": decoder["head_dim"],
        "hidden_dim": decoder["hidden_dim"],
        "vocab_size": decoder["vocab_size"],
        "rope_theta": decoder["rope_theta"],
        "ada_rms_norm_t_cond_dim": decoder.get("ada_rms_norm_t_cond_dim", 32),
        "quantization": cfg.get("quantization"),
    }


_original_load_converted = _vw._load_converted


def _patched_load_converted(model_path):
    """Drop-in replacement that also handles mlx-audio quantised format."""
    from pathlib import Path
    model_path = Path(model_path)

    with open(model_path / "config.json") as f:
        config = json.load(f)

    is_mlx_audio = "decoder" in config and "multimodal" not in config
    if not is_mlx_audio:
        return _original_load_converted(model_path)

    log("[server] Detected mlx-audio config format, transforming...", force=True)
    config = _transform_mlx_audio_config(config)
    model = VoxtralRealtime(config)

    # Load weights
    index_path = model_path / "model.safetensors.index.json"
    if index_path.exists():
        with open(index_path) as f:
            index = json.load(f)
        shard_files = sorted(set(index["weight_map"].values()))
        weights = {}
        for shard_file in shard_files:
            weights.update(mx.load(str(model_path / shard_file)))
    else:
        weights = mx.load(str(model_path / "model.safetensors"))

    # Remap weight names
    remapped = {}
    for name, tensor in weights.items():
        new_name = _remap_mlx_audio_weight(name)
        if new_name is not None:
            remapped[new_name] = tensor
    log(f"[server] Remapped {len(remapped)} weights from mlx-audio format", force=True)

    # Quantize only modules that have .scales/.biases in the weight file
    quant_config = config.get("quantization")
    if quant_config is not None:
        quantized_modules = {
            k.rsplit(".", 1)[0]
            for k in remapped
            if k.endswith(".scales") or k.endswith(".biases")
        }
        group_size = quant_config["group_size"]

        def predicate(path, module):
            if not hasattr(module, "to_quantized"):
                return False
            return path in quantized_modules

        nn.quantize(model, group_size=group_size, bits=quant_config["bits"], class_predicate=predicate)

    model.load_weights(list(remapped.items()))
    mx.eval(model.parameters())
    return model, config


# Apply the patch so converted-weight loading handles both formats.
_vw._load_converted = _patched_load_converted

import voxmlx  # noqa: E402
from voxmlx.server import StreamingSession  # noqa: E402

# ---------------------------------------------------------------------------
# Global model references (loaded once at startup)
# ---------------------------------------------------------------------------
model = None
sp = None
config = None
SAMPLE_RATE = 16_000

MODEL_ID = "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"
# If MACSTRAL_MODEL_DIR is set by the Swift launcher, use it as the Hugging Face
# cache directory so model files are stored inside Application Support rather than
# the default ~/.cache/huggingface location, keeping the app self-contained.
_model_dir = os.environ.get("MACSTRAL_MODEL_DIR", "")
if _model_dir:
    os.environ.setdefault("HF_HOME", _model_dir)
    os.environ.setdefault("HUGGINGFACE_HUB_CACHE", _model_dir)
DEBUG_TRANSCRIPTION = os.environ.get("MACSTRAL_DEBUG_TRANSCRIPTION", "").lower() in {"1", "true", "yes"}


def log(msg: str, *, force: bool = False):
    if not force and not DEBUG_TRANSCRIPTION:
        return
    print(msg, file=sys.stderr, flush=True)


def _set_mx_cache_limit(limit_bytes: int):
    set_cache_limit = getattr(mx, "set_cache_limit", None)
    if callable(set_cache_limit):
        set_cache_limit(limit_bytes)
        return
    metal = getattr(mx, "metal", None)
    if metal is None:
        return
    metal_set_cache_limit = getattr(metal, "set_cache_limit", None)
    if callable(metal_set_cache_limit):
        metal_set_cache_limit(limit_bytes)


def _load_model_compat(model_path: str):
    from pathlib import Path

    _set_mx_cache_limit(4 * 1024 * 1024 * 1024)
    resolved_model_path = Path(model_path)
    if not resolved_model_path.exists():
        resolved_model_path = _vw.download_model(model_path)
    model_value, model_config = _vw.load_model(resolved_model_path)
    tokenizer = voxmlx._load_tokenizer(resolved_model_path)
    return model_value, tokenizer, model_config


def load_voxtral():
    global model, sp, config
    model, sp, config = _load_model_compat(MODEL_ID)

    log("[server] Warming up model (1s silent audio, streaming pipeline)...", force=True)
    try:
        warmup_session = StreamingSession(model, sp, temperature=0.0)
        silence = np.zeros(SAMPLE_RATE, dtype=np.float32)
        warmup_session.feed_audio(silence)
        warmup_session.finalize()
        log("[server] Warm-up complete", force=True)
    except Exception as exc:
        log(f"[server] Warm-up failed (non-fatal): {exc}", force=True)


# ---------------------------------------------------------------------------
# WebSocket handler
# ---------------------------------------------------------------------------

def _create_session():
    """Create a new StreamingSession (may be called from a thread)."""
    return StreamingSession(model, sp, temperature=0.0)


# Batching thresholds: use a smaller batch for the first feed to minimise
# time-to-first-delta, then switch to a larger batch for steady-state
# efficiency (reduces thread-pool scheduling overhead).
FIRST_BATCH_THRESHOLD = 2_000   # ~125ms at 16 kHz — fast first delta
AUDIO_BATCH_THRESHOLD = 8_000   # ~500ms at 16 kHz — steady-state


async def _feed_buffered_audio(session, audio_buffer, first_chunk_received_at, first_delta_sent, websocket):
    """Feed accumulated audio buffer to the model and send deltas."""
    if len(audio_buffer) == 0:
        return audio_buffer, first_delta_sent
    t0 = time.perf_counter()
    try:
        tokens = await asyncio.to_thread(session.feed_audio, audio_buffer)
    except Exception as exc:
        log(f"[server] ERROR in feed_audio ({len(audio_buffer)} samples): {exc}", force=True)
        await websocket.send(json.dumps({"type": "error", "text": f"feed_audio failed: {exc}"}))
        return np.array([], dtype=np.float32), first_delta_sent
    t1 = time.perf_counter()

    if tokens:
        log(f"[server] feed_audio returned {len(tokens)} tokens in {t1-t0:.3f}s: \"{session.full_text[:80]}\"")
        delta_payload = {
            "type": "delta",
            "text": "".join(tokens),
            "is_incremental": True,
            "feed_audio_ms": (t1 - t0) * 1000.0,
        }
        if not first_delta_sent and first_chunk_received_at is not None:
            delta_payload["first_chunk_to_first_delta_ms"] = (t1 - first_chunk_received_at) * 1000.0
            first_delta_sent = True
        await websocket.send(json.dumps(delta_payload))

    return np.array([], dtype=np.float32), first_delta_sent


async def handle_client(websocket):
    log("[server] Client connected", force=True)
    session = None
    pre_allocated_session = None
    accumulated_eos_text = ""
    first_chunk_received_at = None
    first_delta_sent = False
    first_feed_done = False
    audio_buffer = np.array([], dtype=np.float32)

    async for message in websocket:
        if isinstance(message, bytes):
            if session is None:
                # Audio arrived before start_session; ignore.
                continue
            if len(message) % 2 != 0:
                await websocket.send(json.dumps({"type": "error", "text": "Invalid PCM frame size"}))
                continue
            now = time.perf_counter()
            if first_chunk_received_at is None:
                first_chunk_received_at = now
            audio_f32 = np.frombuffer(message, dtype=np.int16).astype(np.float32) / 32768.0
            audio_buffer = np.concatenate([audio_buffer, audio_f32])

            # Use a smaller threshold for the first batch (fast first delta),
            # then switch to the larger steady-state threshold.
            threshold = FIRST_BATCH_THRESHOLD if not first_feed_done else AUDIO_BATCH_THRESHOLD
            if len(audio_buffer) >= threshold:
                audio_buffer, first_delta_sent = await _feed_buffered_audio(
                    session, audio_buffer, first_chunk_received_at, first_delta_sent, websocket
                )
                first_feed_done = True

            if getattr(session, "eos_text", None) is not None:
                eos_text = session.eos_text
                log(f"[server] EOS detected during feed: \"{eos_text[:80]}\"", force=True)
                # Send the EOS text as a delta (not done) so the client can display it
                # while continuing the session. The client will send "commit" when the
                # user releases the hotkey, which triggers the actual "done" response.
                # Sending "done" here would desync: the client ignores it (status is
                # .listening) and the subsequent "commit" is silently dropped because
                # session would be None.
                await websocket.send(
                    json.dumps({"type": "delta", "text": eos_text, "is_incremental": False})
                )
                # Accumulate EOS text so it can be prepended to the final "done"
                # response when commit arrives (session.full_text only covers the
                # new session, so we'd silently drop any pre-rollover speech otherwise).
                accumulated_eos_text += eos_text
                # Start a fresh session so subsequent audio is still transcribed.
                if pre_allocated_session is not None:
                    session = pre_allocated_session
                    pre_allocated_session = None
                else:
                    session = await asyncio.to_thread(_create_session)
                audio_buffer = np.array([], dtype=np.float32)
                first_chunk_received_at = None
                first_delta_sent = False
                first_feed_done = False

        elif isinstance(message, str):
            cmd = message.strip().lower()
            if cmd == "start_session":
                log("[server] Received start_session, creating new session...", force=True)
                if pre_allocated_session is not None:
                    session = pre_allocated_session
                    pre_allocated_session = None
                    log("[server] Using pre-allocated session", force=True)
                else:
                    session = await asyncio.to_thread(_create_session)
                first_chunk_received_at = None
                first_delta_sent = False
                first_feed_done = False
                audio_buffer = np.array([], dtype=np.float32)

            elif cmd == "commit":
                if session is None:
                    log("[server] WARNING: commit received but session is None — sending empty done", force=True)
                    await websocket.send(json.dumps({"type": "done", "text": accumulated_eos_text}))
                    accumulated_eos_text = ""
                    continue
                # Flush any remaining buffered audio before finalizing.
                if len(audio_buffer) > 0:
                    audio_buffer, first_delta_sent = await _feed_buffered_audio(
                        session, audio_buffer, first_chunk_received_at, first_delta_sent, websocket
                    )
                log("[server] Received commit, finalizing session...", force=True)
                t0 = time.perf_counter()
                try:
                    await asyncio.to_thread(session.finalize)
                except Exception as exc:
                    log(f"[server] ERROR in finalize(): {exc}", force=True)
                    await websocket.send(json.dumps({"type": "done", "text": accumulated_eos_text + (session.full_text or "")}))
                    accumulated_eos_text = ""
                    session = None
                    continue
                t1 = time.perf_counter()
                # Prepend any EOS-detected text from earlier session rollovers so the
                # full dictation is preserved in the final response.
                final_text = accumulated_eos_text + (session.full_text or "")
                accumulated_eos_text = ""
                log(f"[server] finalize() took {t1-t0:.3f}s, result: \"{final_text[:80]}\"", force=True)
                await websocket.send(
                    json.dumps({"type": "done", "text": final_text, "finalize_ms": (t1 - t0) * 1000.0})
                )
                session = None
                first_chunk_received_at = None
                first_delta_sent = False
                first_feed_done = False
                audio_buffer = np.array([], dtype=np.float32)
                # Pre-allocate next session off the critical path.
                pre_allocated_session = await asyncio.to_thread(_create_session)

    log("[server] Client disconnected", force=True)


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
