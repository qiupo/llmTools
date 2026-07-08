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
VENV="${LLMTOOLS_SENSEVOICE_ASR_VENV:-$ASR_ROOT/sensevoice-venv}"
PYTHON_BIN="${PYTHON_BIN:-}"

if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required to install the isolated SenseVoice mlx-audio runtime." >&2
    echo "Install uv first or set LLMTOOLS_SENSEVOICE_ASR_VENV to an existing venv with mlx_audio.stt.generate and mlx_audio.stt.models.sensevoice." >&2
    exit 69
fi

if [ -z "$PYTHON_BIN" ]; then
    if command -v python3.12 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.12)"
    elif command -v python3.11 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3.11)"
    else
        echo "error: python3.12 or python3.11 is required for the SenseVoice mlx-audio runtime." >&2
        exit 69
    fi
fi

mkdir -p "$ASR_ROOT"
uv venv --python "$PYTHON_BIN" "$VENV"
uv pip install --python "$VENV/bin/python" --prerelease allow -U 'mlx-audio==0.4.4'

MODELS_INIT="$("$VENV/bin/python" - <<'PY'
import pathlib
import mlx_audio

print(pathlib.Path(mlx_audio.__file__).parent / "stt" / "models" / "__init__.py")
PY
)"
printf '%s\n' '# patched by llmTools to avoid eager optional model imports in mlx-audio 0.4.4' > "$MODELS_INIT"

echo "Installed llmTools Phase 4 SenseVoice mlx-audio runtime:"
echo "  venv: $VENV"
echo "  runner: $RUNNER_PATH"
echo
echo "Example command template:"
echo "  LLMTOOLS_SENSEVOICE_ASR_VENV='$VENV' '$RUNNER_PATH' --model {model} --audio {audio} --language {language}"
