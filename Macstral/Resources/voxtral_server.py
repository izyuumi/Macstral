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


# Apply the patch so voxmlx.load_model() handles both formats.
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
DEBUG_TRANSCRIPTION = os.environ.get("MACSTRAL_DEBUG_TRANSCRIPTION", "").lower() in {"1", "true", "yes"}


def log(msg: str, *, force: bool = False):
    if not force and not DEBUG_TRANSCRIPTION:
        return
    print(msg, file=sys.stderr, flush=True)


def load_voxtral():
    global model, sp, config
    model, sp, config = voxmlx.load_model(MODEL_ID)

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

async def handle_client(websocket):
    log("[server] Client connected", force=True)
    session = StreamingSession(model, sp, temperature=0.0)
    first_chunk_received_at = None
    first_delta_sent = False

    async for message in websocket:
        if isinstance(message, bytes):
            now = time.perf_counter()
            if first_chunk_received_at is None:
                first_chunk_received_at = now
            audio_f32 = np.frombuffer(message, dtype=np.int16).astype(np.float32) / 32768.0
            t0 = time.perf_counter()
            tokens = session.feed_audio(audio_f32)
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

            if session.eos_text is not None:
                log(f"[server] EOS detected during feed: \"{session.eos_text[:80]}\"")
                await websocket.send(
                    json.dumps({"type": "done", "text": session.eos_text})
                )
                session = StreamingSession(model, sp, temperature=0.0)
                first_chunk_received_at = None
                first_delta_sent = False

        elif isinstance(message, str):
            if message.strip().lower() == "commit":
                log("[server] Received commit, finalizing session...", force=True)
                t0 = time.perf_counter()
                session.finalize()
                t1 = time.perf_counter()
                final_text = session.full_text
                log(f"[server] finalize() took {t1-t0:.3f}s, result: \"{final_text[:80]}\"", force=True)
                await websocket.send(
                    json.dumps({"type": "done", "text": final_text, "finalize_ms": (t1 - t0) * 1000.0})
                )
                session = StreamingSession(model, sp, temperature=0.0)
                first_chunk_received_at = None
                first_delta_sent = False

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
