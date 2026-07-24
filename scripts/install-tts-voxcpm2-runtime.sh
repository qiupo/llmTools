#!/usr/bin/env bash
set -euo pipefail

TTS_ROOT="${LLMTOOLS_TTS_RUNTIME_ROOT:-$HOME/Library/Application Support/llmTools/tts-runtime}"
VENV="${LLMTOOLS_TTS_VENV:-$TTS_ROOT/venv}"
VARIANT="${LLMTOOLS_TTS_VARIANT:-bf16}"
PYTHON_BIN="${PYTHON_BIN:-}"
DOWNLOAD_MODEL="${LLMTOOLS_TTS_DOWNLOAD_MODEL:-1}"

case "$VARIANT" in
    bf16) REPO_ID="mlx-community/VoxCPM2-bf16"; DIRECTORY_NAME="VoxCPM2-bf16" ;;
    4bit) REPO_ID="mlx-community/VoxCPM2-4bit"; DIRECTORY_NAME="VoxCPM2-4bit" ;;
    8bit) REPO_ID="mlx-community/VoxCPM2-8bit"; DIRECTORY_NAME="VoxCPM2-8bit" ;;
    *) echo "error: LLMTOOLS_TTS_VARIANT must be bf16, 4bit, or 8bit." >&2; exit 64 ;;
esac

if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required to install the isolated TTS runtime." >&2
    exit 69
fi
if [ -z "$PYTHON_BIN" ]; then
    if command -v python3.12 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.12)"
    elif command -v python3.11 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.11)"
    else
        echo "error: python3.12 or python3.11 is required." >&2
        exit 69
    fi
fi

mkdir -p "$TTS_ROOT/models"
chmod 700 "$TTS_ROOT" "$TTS_ROOT/models"
if [ ! -x "$VENV/bin/python" ]; then
    uv venv --clear --python "$PYTHON_BIN" "$VENV"
fi
if "$VENV/bin/python" <<'PY' >/dev/null 2>&1
from importlib.metadata import version
import mlx_audio.tts.models.voxcpm2  # noqa: F401
raise SystemExit(0 if version("mlx-audio") == "0.4.5" else 1)
PY
then
    echo "mlx-audio==0.4.5 is already installed."
else
    uv pip install --python "$VENV/bin/python" --prerelease allow 'mlx-audio==0.4.5'
fi

model_complete() {
    local directory="$1"
    MODEL_DIRECTORY="$directory" "$VENV/bin/python" <<'PY' >/dev/null 2>&1
import json
import os
from pathlib import Path
root = Path(os.environ["MODEL_DIRECTORY"])
if not (root / "config.json").is_file():
    raise SystemExit(1)
index = root / "model.safetensors.index.json"
if index.is_file():
    weight_map = json.loads(index.read_text()).get("weight_map", {})
    files = set(weight_map.values())
    raise SystemExit(0 if files and all((root / name).is_file() for name in files) else 1)
raise SystemExit(0 if (root / "model.safetensors").is_file() else 1)
PY
}

MODEL_DIR="$TTS_ROOT/models/$DIRECTORY_NAME"
EXTERNAL_MODEL_DIR="$HOME/code/models/mlx-community/$DIRECTORY_NAME"
if model_complete "$EXTERNAL_MODEL_DIR"; then
    MODEL_DIR="$EXTERNAL_MODEL_DIR"
elif ! model_complete "$MODEL_DIR"; then
    if [ "$DOWNLOAD_MODEL" != "1" ]; then
        echo "Runtime installed; model download skipped for $REPO_ID."
        exit 0
    fi
    echo "Downloading $REPO_ID to $MODEL_DIR"
    MODEL_DIR="$MODEL_DIR" REPO_ID="$REPO_ID" "$VENV/bin/python" <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download(repo_id=os.environ["REPO_ID"], local_dir=os.environ["MODEL_DIR"])
PY
fi

if ! model_complete "$MODEL_DIR"; then
    echo "error: model download is incomplete at $MODEL_DIR" >&2
    exit 69
fi
chmod -R u+rwX,go-rwx "$TTS_ROOT"
echo "Installed llmTools local TTS runtime:"
echo "  venv: $VENV"
echo "  model: $MODEL_DIR"
