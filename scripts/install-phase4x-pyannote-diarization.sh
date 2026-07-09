#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${LLMTOOLS_DIARIZATION_RUNTIME_DIR:-$HOME/Library/Application Support/llmTools/diarization-runtime}"
VENV_DIR="$RUNTIME_DIR/venv"
PYANNOTE_PACKAGE_SPEC="${LLMTOOLS_PYANNOTE_PACKAGE_SPEC:-pyannote.audio==3.1.1}"

cat <<'TEXT'
pyannote speaker diarization setup

You must accept the Hugging Face terms for pyannote/speaker-diarization-3.1
and provide a token locally. llmTools does not upload audio; diarization runs
through this local Python runtime.
TEXT

mkdir -p "$RUNTIME_DIR"

if command -v uv >/dev/null 2>&1; then
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    uv venv --seed "$VENV_DIR"
  fi
  uv pip install --python "$VENV_DIR/bin/python" "numpy>=1.23,<2" "$PYANNOTE_PACKAGE_SPEC"
else
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
  fi
  "$VENV_DIR/bin/python" -m ensurepip --upgrade
  "$VENV_DIR/bin/python" -m pip install --upgrade --timeout 120 --retries 5 pip
  "$VENV_DIR/bin/python" -m pip install --timeout 120 --retries 5 "numpy>=1.23,<2" "$PYANNOTE_PACKAGE_SPEC"
fi

"$VENV_DIR/bin/python" - <<'PY'
from pyannote.audio import Pipeline
print("pyannote.audio import smoke test passed")
PY

echo "pyannote diarization runtime installed and import-tested in $RUNTIME_DIR"
echo "Set PYANNOTE_AUTH_TOKEN or save the token in llmTools Settings before running diarization."
