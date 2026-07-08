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
uv venv --python "$PYTHON_BIN" "$VENV"
uv pip install --python "$VENV/bin/python" --prerelease allow -U 'mlx-audio==0.4.0'

echo "Installed llmTools Phase 4 mlx-audio runtime:"
echo "  venv: $VENV"
echo "  runner: $RUNNER_PATH"
echo
echo "Example command template:"
echo "  LLMTOOLS_ASR_VENV='$VENV' '$RUNNER_PATH' --model {model} --audio {audio} --language {language}"
