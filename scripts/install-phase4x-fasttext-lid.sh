#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${LLMTOOLS_LID_RUNTIME_DIR:-$HOME/Library/Application Support/llmTools/lid-runtime}"
VENV_DIR="$RUNTIME_DIR/venv"
MODEL_VARIANT="${LLMTOOLS_LID_MODEL_VARIANT:-ftz}"
MODEL_URL_FTZ="${LLMTOOLS_LID_MODEL_URL_FTZ:-https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.ftz}"
MODEL_URL_BIN="${LLMTOOLS_LID_MODEL_URL_BIN:-https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$RUNTIME_DIR"

if command -v uv >/dev/null 2>&1; then
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    uv venv --seed "$VENV_DIR"
  fi
  uv pip install --python "$VENV_DIR/bin/python" "numpy>=1.23,<2" "fasttext-wheel>=0.9.2,<1" \
    || uv pip install --python "$VENV_DIR/bin/python" "numpy>=1.23,<2" "fasttext>=0.9.3,<1"
else
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
  fi
  "$VENV_DIR/bin/python" -m ensurepip --upgrade
  "$VENV_DIR/bin/python" -m pip install --upgrade --timeout 120 --retries 5 pip
  "$VENV_DIR/bin/python" -m pip install --timeout 120 --retries 5 "numpy>=1.23,<2" "fasttext-wheel>=0.9.2,<1" \
    || "$VENV_DIR/bin/python" -m pip install --timeout 120 --retries 5 "numpy>=1.23,<2" "fasttext>=0.9.3,<1"
fi

download_model() {
  local url="$1"
  local output="$2"
  if [ -f "$output" ]; then
    echo "Already present: $output"
    return
  fi
  echo "Downloading $url"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --connect-timeout 20 --max-time 300 "$url" -o "$output"
  else
    "$VENV_DIR/bin/python" - "$url" "$output" <<'PY'
import sys
import urllib.request
import socket

url, output = sys.argv[1], sys.argv[2]
socket.setdefaulttimeout(300)
urllib.request.urlretrieve(url, output)
PY
  fi
}

SMOKE_MODEL=""
case "$MODEL_VARIANT" in
  ftz)
    SMOKE_MODEL="$RUNTIME_DIR/lid.176.ftz"
    download_model "$MODEL_URL_FTZ" "$SMOKE_MODEL"
    ;;
  bin)
    SMOKE_MODEL="$RUNTIME_DIR/lid.176.bin"
    download_model "$MODEL_URL_BIN" "$SMOKE_MODEL"
    ;;
  both)
    download_model "$MODEL_URL_FTZ" "$RUNTIME_DIR/lid.176.ftz"
    download_model "$MODEL_URL_BIN" "$RUNTIME_DIR/lid.176.bin"
    SMOKE_MODEL="$RUNTIME_DIR/lid.176.ftz"
    ;;
  *)
    echo "error: unsupported LLMTOOLS_LID_MODEL_VARIANT: $MODEL_VARIANT" >&2
    exit 2
    ;;
esac

SMOKE_OUTPUT="$("$VENV_DIR/bin/python" "$SCRIPT_DIR/llmtools-lid-sidecar.py" --model "$SMOKE_MODEL" <<'JSON'
{"protocol":"llmtools.lid/v1","command":"detect","requestID":"smoke","text":"This is a language detection smoke test."}
{"protocol":"llmtools.lid/v1","command":"stop","requestID":"stop"}
JSON
)"
printf '%s\n' "$SMOKE_OUTPUT"
printf '%s\n' "$SMOKE_OUTPUT" | "$VENV_DIR/bin/python" -c 'import json, sys
events = [json.loads(line) for line in sys.stdin if line.strip()]
result = next((event for event in events if event.get("type") == "result" and event.get("requestID") == "smoke"), None)
if not result or result.get("language") != "en" or float(result.get("confidence") or 0) <= 0:
    raise SystemExit("fastText language ID smoke test failed.")
'

echo "fastText language ID runtime installed and smoke-tested in $RUNTIME_DIR"
