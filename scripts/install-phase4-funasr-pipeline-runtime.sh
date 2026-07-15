#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASR_ROOT="${LLMTOOLS_ASR_RUNTIME_ROOT:-$HOME/Library/Application Support/llmTools/asr-runtime}"
RUNTIME_ROOT="${LLMTOOLS_FUNASR_PIPELINE_ROOT:-$ASR_ROOT/funasr-pipeline}"
VENV="$RUNTIME_ROOT/venv"
MODELS_ROOT="$RUNTIME_ROOT/models"
PYTHON_BIN="${PYTHON_BIN:-}"
FUNASR_VERSION="1.3.14"
MODELSCOPE_VERSION="1.38.1"
TORCH_VERSION="2.9.0"
TRANSFORMERS_VERSION="4.57.6"

if [ -f "$SCRIPT_DIR/llmtools-funasr-pipeline.py" ]; then
    SIDECAR="$SCRIPT_DIR/llmtools-funasr-pipeline.py"
else
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    SIDECAR="$ROOT_DIR/scripts/llmtools-funasr-pipeline.py"
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required to install the official FunASR pipeline runtime." >&2
    exit 69
fi
if [ -z "$PYTHON_BIN" ]; then
    if command -v python3.12 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.12)"
    elif command -v python3.11 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.11)"
    else
        echo "error: Python 3.11 or 3.12 is required for the official FunASR pipeline." >&2
        exit 69
    fi
fi

mkdir -p "$MODELS_ROOT"
if [ ! -x "$VENV/bin/python" ]; then
    uv venv --python "$PYTHON_BIN" "$VENV"
fi
if ! "$VENV/bin/python" - <<PY >/dev/null 2>&1
from importlib.metadata import version
import funasr, modelscope, torch
raise SystemExit(0 if version("funasr") == "$FUNASR_VERSION" and version("modelscope") == "$MODELSCOPE_VERSION" and version("torch") == "$TORCH_VERSION" else 1)
PY
then
    uv pip install --python "$VENV/bin/python" \
        "funasr==$FUNASR_VERSION" \
        "modelscope==$MODELSCOPE_VERSION" \
        "torch==$TORCH_VERSION" \
        "torchaudio==$TORCH_VERSION" \
        "transformers==$TRANSFORMERS_VERSION" \
        zhconv whisper_normalizer pyopenjtalk-plus
fi

RUNTIME_ROOT="$RUNTIME_ROOT" "$VENV/bin/python" <<'PY'
import hashlib
import json
import os
from importlib.metadata import version
from pathlib import Path

from modelscope import snapshot_download

root = Path(os.environ["RUNTIME_ROOT"])
models_root = root / "models"
models = {
    "funasr-nano": ("FunAudioLLM/Fun-ASR-Nano-2512", "model.pt"),
    "fsmn-vad": ("iic/speech_fsmn_vad_zh-cn-16k-common-pytorch", "model.pt"),
    "campp": ("iic/speech_campplus_sv_zh-cn_16k-common", "campplus_cn_common.bin"),
    "ct-punc": ("iic/punc_ct-transformer_cn-en-common-vocab471067-large", "model.pt"),
}
installed = {}
for name, (model_id, checkpoint_name) in models.items():
    target = models_root / name
    snapshot_download(model_id, revision="master", local_dir=str(target))
    checkpoint = target / checkpoint_name
    if not (target / "config.yaml").is_file() or not checkpoint.is_file():
        raise RuntimeError(f"Downloaded model is incomplete: {model_id}")
    digest = hashlib.sha256()
    with checkpoint.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    installed[name] = {
        "modelID": model_id,
        "checkpoint": str(checkpoint.relative_to(root)),
        "sha256": digest.hexdigest(),
    }

manifest = {
    "protocol": "llmtools.funasr-runtime/v1",
    "packages": {
        "funasr": version("funasr"),
        "modelscope": version("modelscope"),
        "torch": version("torch"),
        "transformers": version("transformers"),
    },
    "models": installed,
}
(root / "runtime-manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

MODEL_DIR="$MODELS_ROOT/funasr-nano"
LLMTOOLS_FUNASR_PIPELINE_ROOT="$RUNTIME_ROOT" \
    "$VENV/bin/python" "$SIDECAR" --check --model "$MODEL_DIR" >/dev/null

echo "Installed official llmTools FunASR composite pipeline:"
echo "  runtime: $RUNTIME_ROOT"
echo "  model: $MODEL_DIR"
echo "  pipeline: Fun-ASR-Nano + FSMN-VAD + CAM++ + CT-Punc"
