#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${LLMTOOLS_FASTMT_RUNTIME_DIR:-$HOME/Library/Application Support/llmTools/fastmt-runtime}"
VENV_DIR="$RUNTIME_DIR/venv"
MODEL_DIR="$RUNTIME_DIR/opus-mt-en-zh-ct2"
SOURCE_MODEL="${LLMTOOLS_FASTMT_CT2_SOURCE_MODEL:-Helsinki-NLP/opus-mt-en-zh}"
PYTHON_BIN="${LLMTOOLS_FASTMT_BOOTSTRAP_PYTHON:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -n "${LLMTOOLS_HF_ENDPOINT:-}" ]]; then
  export HF_ENDPOINT="$LLMTOOLS_HF_ENDPOINT"
elif [[ -z "${HF_ENDPOINT:-}" && "$SOURCE_MODEL" != /* ]]; then
  if curl -fsI --connect-timeout 8 --max-time 15 \
    "https://huggingface.co/$SOURCE_MODEL/resolve/main/config.json" >/dev/null 2>&1; then
    :
  elif curl -fsI --connect-timeout 8 --max-time 15 \
    "https://hf-mirror.com/$SOURCE_MODEL/resolve/main/config.json" >/dev/null 2>&1; then
    export HF_ENDPOINT="https://hf-mirror.com"
    echo "Using Hugging Face mirror: $HF_ENDPOINT"
  fi
fi

mkdir -p "$RUNTIME_DIR"

if [[ -z "$PYTHON_BIN" ]]; then
  for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      PYTHON_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [[ -z "$PYTHON_BIN" ]]; then
  echo "No Python 3 runtime was found." >&2
  exit 1
fi

"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade --timeout 120 --retries 5 pip
"$VENV_DIR/bin/python" -m pip install --timeout 120 --retries 5 \
  "ctranslate2>=4.4,<5" \
  "sentencepiece>=0.2,<0.3" \
  "transformers>=4.44,<5" \
  "huggingface_hub>=0.23,<1" \
  "protobuf>=4,<6" \
  "sacremoses==0.0.53"

if [[ ! -f "$MODEL_DIR/model.bin" ]]; then
  rm -rf "$MODEL_DIR"
  mkdir -p "$MODEL_DIR"
  "$VENV_DIR/bin/ct2-transformers-converter" \
    --model "$SOURCE_MODEL" \
    --output_dir "$MODEL_DIR" \
    --force \
    --copy_files source.spm target.spm tokenizer_config.json
fi

"$VENV_DIR/bin/python" "$SCRIPT_DIR/llmtools-fastmt-sidecar.py" \
  --engine ctranslate2 \
  --model "$MODEL_DIR" <<'JSON'
{"protocol":"llmtools.fastmt/v1","command":"translate","requestID":"smoke","sourceLanguage":"en","targetLanguage":"zh-Hans","segments":[{"id":"s1","text":"Hello world."}]}
{"protocol":"llmtools.fastmt/v1","command":"stop","requestID":"stop"}
JSON

cat <<MSG
llmTools CTranslate2 en->zh runtime is installed and smoke-tested.

Model directory expected by default:
  $MODEL_DIR

The app should discover this automatically. If it cannot, launch with:
  LLMTOOLS_FASTMT_PYTHON="$VENV_DIR/bin/python"
  LLMTOOLS_FASTMT_CT2_MODEL="$MODEL_DIR"
MSG
