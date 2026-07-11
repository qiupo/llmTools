#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/llmtools-mlx-asr-runner.sh" ]; then
    RUNNER_PATH="$SCRIPT_DIR/llmtools-mlx-asr-runner.sh"
else
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    RUNNER_PATH="$ROOT_DIR/scripts/llmtools-mlx-asr-runner.sh"
fi
ASR_ROOT="${LLMTOOLS_ASR_RUNTIME_ROOT:-$HOME/Library/Application Support/llmTools/asr-runtime}"
VENV="${LLMTOOLS_ASR_VENV:-$ASR_ROOT/venv}"
VIBEVOICE_TOKENIZER_DIR="${LLMTOOLS_VIBEVOICE_TOKENIZER_DIR:-$ASR_ROOT/qwen2.5-tokenizer}"
PYTHON_BIN="${PYTHON_BIN:-}"

if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required to install the isolated mlx-audio runtime." >&2
    echo "Install uv first or set LLMTOOLS_ASR_VENV to an existing venv with mlx_audio.stt.generate." >&2
    exit 69
fi

if [ -z "$PYTHON_BIN" ]; then
    if command -v python3.12 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.12)"
    elif command -v python3.11 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.11)"
    else
        echo "error: python3.12 or python3.11 is required for the mlx-audio runtime." >&2
        exit 69
    fi
fi

mkdir -p "$ASR_ROOT"
if [ -x "$VENV/bin/python" ]; then
    echo "Reusing existing mlx-audio virtual environment: $VENV"
else
    uv venv --clear --python "$PYTHON_BIN" "$VENV"
fi
if "$VENV/bin/python" <<'PY' >/dev/null 2>&1
from importlib.metadata import version

import mlx_audio.stt.models.vibevoice_asr  # noqa: F401

raise SystemExit(0 if version("mlx-audio") == "0.4.0" else 1)
PY
then
    echo "mlx-audio==0.4.0 is already installed."
else
    uv pip install --python "$VENV/bin/python" --prerelease allow 'mlx-audio==0.4.0'
fi

has_vibevoice_tokenizer() {
    local candidate="$1"
    [ -n "$candidate" ] \
        && [ -f "$candidate/tokenizer_config.json" ] \
        && { [ -f "$candidate/tokenizer.json" ] || [ -f "$candidate/vocab.json" ]; }
}

copy_vibevoice_tokenizer_from() {
    local source_dir="$1"
    mkdir -p "$VIBEVOICE_TOKENIZER_DIR"
    for tokenizer_file in tokenizer_config.json tokenizer.json vocab.json merges.txt special_tokens_map.json added_tokens.json tokenizer.model; do
        if [ -f "$source_dir/$tokenizer_file" ]; then
            cp -f "$source_dir/$tokenizer_file" "$VIBEVOICE_TOKENIZER_DIR/$tokenizer_file"
        fi
    done
}

download_vibevoice_tokenizer() {
    TOKENIZER_DIR="$VIBEVOICE_TOKENIZER_DIR" "$VENV/bin/python" <<'PY'
import os
from pathlib import Path

from huggingface_hub import snapshot_download

repo_id = os.environ.get("LLMTOOLS_VIBEVOICE_TOKENIZER_REPO", "Qwen/Qwen2.5-7B")
tokenizer_dir = Path(os.environ["TOKENIZER_DIR"])
tokenizer_dir.mkdir(parents=True, exist_ok=True)
snapshot_download(
    repo_id=repo_id,
    local_dir=str(tokenizer_dir),
    allow_patterns=[
        "tokenizer.json",
        "tokenizer_config.json",
        "vocab.json",
        "merges.txt",
        "special_tokens_map.json",
        "added_tokens.json",
        "tokenizer.model",
    ],
)
if not (tokenizer_dir / "tokenizer_config.json").exists():
    raise SystemExit(f"tokenizer_config.json was not downloaded to {tokenizer_dir}")
if not ((tokenizer_dir / "tokenizer.json").exists() or (tokenizer_dir / "vocab.json").exists()):
    raise SystemExit(f"tokenizer files were not downloaded to {tokenizer_dir}")
PY
}

if has_vibevoice_tokenizer "$VIBEVOICE_TOKENIZER_DIR"; then
    echo "Reusing VibeVoice-ASR MLX tokenizer sidecar: $VIBEVOICE_TOKENIZER_DIR"
else
    for candidate in \
        "$HOME/code/models/lmstudio-community/Qwen2.5-0.5B-Instruct-MLX-4bit" \
        "$HOME/code/models/mlx-community/Qwen3-ASR-0.6B-4bit" \
        "$HOME/code/models/mlx-community/Qwen3-ASR-0.6B-bf16" \
        "$HOME/code/models/mlx-community/Qwen3-ASR-1.7B-bf16"; do
        if has_vibevoice_tokenizer "$candidate"; then
            copy_vibevoice_tokenizer_from "$candidate"
            echo "Installed VibeVoice-ASR MLX tokenizer sidecar from local tokenizer: $candidate"
            break
        fi
    done
fi

if ! has_vibevoice_tokenizer "$VIBEVOICE_TOKENIZER_DIR"; then
    echo "Installing VibeVoice-ASR MLX tokenizer sidecar from Qwen/Qwen2.5-7B..."
    if ! download_vibevoice_tokenizer; then
        if [ -z "${HF_ENDPOINT:-}" ]; then
            echo "Direct Hugging Face tokenizer download failed; retrying with HF_ENDPOINT=https://hf-mirror.com" >&2
            HF_ENDPOINT="https://hf-mirror.com" download_vibevoice_tokenizer
        else
            exit 69
        fi
    fi
fi

echo "Installed llmTools Phase 4 mlx-audio runtime:"
echo "  venv: $VENV"
echo "  runner: $RUNNER_PATH"
echo "  VibeVoice-ASR tokenizer: $VIBEVOICE_TOKENIZER_DIR"
echo
echo "Example command template:"
echo "  LLMTOOLS_ASR_VENV='$VENV' '$RUNNER_PATH' --model {model} --audio {audio} --language {language}"
