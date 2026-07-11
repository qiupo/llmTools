#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/llmtools-vibevoice-asr-runner.py" ]; then
    RUNNER_PATH="$SCRIPT_DIR/llmtools-vibevoice-asr-runner.py"
else
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    RUNNER_PATH="$ROOT_DIR/scripts/llmtools-vibevoice-asr-runner.py"
fi

ASR_ROOT="${LLMTOOLS_ASR_RUNTIME_ROOT:-$HOME/Library/Application Support/llmTools/asr-runtime}"
VENV="${LLMTOOLS_VIBEVOICE_ASR_VENV:-$ASR_ROOT/vibevoice-venv}"
PYTHON_BIN="${PYTHON_BIN:-}"
VIBEVOICE_REPO="${LLMTOOLS_VIBEVOICE_REPO:-https://github.com/microsoft/VibeVoice.git}"

if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required to install the isolated VibeVoice-ASR runtime." >&2
    echo "Install uv first or set LLMTOOLS_VIBEVOICE_ASR_COMMAND to an existing local VibeVoice-ASR command." >&2
    exit 69
fi

if [ -z "$PYTHON_BIN" ]; then
    if command -v python3.12 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.12)"
    elif command -v python3.11 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.11)"
    else
        echo "error: python3.12 or python3.11 is required for the VibeVoice-ASR runtime." >&2
        exit 69
    fi
fi

mkdir -p "$ASR_ROOT"
if [ -x "$VENV/bin/python" ]; then
    echo "Reusing existing VibeVoice-ASR virtual environment: $VENV"
else
    uv venv --clear --python "$PYTHON_BIN" "$VENV"
fi

# VibeVoice-ASR is heavy. This installs the runtime code only; users still provide a
# local model directory in llmTools. Keep the command template explicit and local.
uv pip install --python "$VENV/bin/python" --prerelease allow -U \
    "torch" \
    "torchaudio" \
    "transformers" \
    "accelerate" \
    "soundfile" \
    "librosa" \
    "git+$VIBEVOICE_REPO"

"$VENV/bin/python" - <<'PY'
from vibevoice.processor.vibevoice_processor import VibeVoiceASRProcessor
from vibevoice.modular.modeling_vibevoice_inference_asr import VibeVoiceForConditionalGenerationInferenceASR
print("VibeVoice-ASR runtime import check passed")
PY

echo "Installed llmTools Phase 4 VibeVoice-ASR runtime:"
echo "  venv: $VENV"
echo "  runner: $RUNNER_PATH"
echo
echo "Example command template:"
echo "  '$VENV/bin/python' '$RUNNER_PATH' --model {model} --audio {audio} --language {language}"
