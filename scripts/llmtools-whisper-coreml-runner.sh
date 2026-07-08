#!/usr/bin/env bash
set -euo pipefail

model=""
audio=""
language="${LLMTOOLS_ASR_LANGUAGE:-auto}"
runtime_root="${LLMTOOLS_WHISPER_CPP_ROOT:-$HOME/Library/Application Support/llmTools/asr-runtime/whisper-cpp}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --model)
            model="${2:-}"
            shift 2
            ;;
        --audio)
            audio="${2:-}"
            shift 2
            ;;
        --language)
            language="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 64
            ;;
    esac
done

if [ -z "$model" ] || [ -z "$audio" ]; then
    echo "Usage: llmtools-whisper-coreml-runner.sh --model <ggml-bin-or-dir> --audio <wav-file> [--language <code>]" >&2
    exit 64
fi

if [ ! -e "$model" ]; then
    echo "Whisper model path not found: $model" >&2
    exit 66
fi
if [ ! -f "$audio" ]; then
    echo "Whisper audio file not found: $audio" >&2
    exit 66
fi

if [ -n "${LLMTOOLS_WHISPER_CPP_CLI:-}" ]; then
    whisper_cli="$LLMTOOLS_WHISPER_CPP_CLI"
elif [ -x "$runtime_root/bin/whisper-cli" ]; then
    whisper_cli="$runtime_root/bin/whisper-cli"
elif [ -x "$runtime_root/whisper.cpp/build/bin/whisper-cli" ]; then
    whisper_cli="$runtime_root/whisper.cpp/build/bin/whisper-cli"
else
    echo "whisper-cli not found. Install with scripts/install-phase4-whisper-coreml-runtime.sh or set LLMTOOLS_WHISPER_CPP_ROOT." >&2
    exit 69
fi

if [ -d "$model" ]; then
    model_bin="$(find "$model" -maxdepth 1 \( -type f -o -type l \) -name 'ggml-*.bin' | sort | head -n 1)"
else
    model_bin="$model"
fi
if [ -z "$model_bin" ] || [ ! -f "$model_bin" ]; then
    echo "No whisper.cpp ggml model file found in: $model" >&2
    exit 66
fi

model_base="$(basename "$model_bin" .bin)"
coreml_dir="$(dirname "$model_bin")/$model_base-encoder.mlmodelc"
if [ ! -d "$coreml_dir" ]; then
    echo "Core ML encoder is missing: $coreml_dir" >&2
    echo "Run scripts/install-phase4-whisper-coreml-runtime.sh to generate it." >&2
    exit 69
fi

case "$language" in
    auto|"")
        whisper_language="auto"
        ;;
    yue)
        whisper_language="zh"
        ;;
    fil)
        whisper_language="tl"
        ;;
    *)
        whisper_language="$language"
        ;;
esac

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/llmtools-whisper-coreml.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
out_base="$tmp_dir/transcript"
log_file="$tmp_dir/whisper.log"

if ! "$whisper_cli" -m "$model_bin" -f "$audio" -l "$whisper_language" -oj -of "$out_base" >"$log_file" 2>&1; then
    cat "$log_file" >&2
    exit 70
fi

json_file="$out_base.json"
if [ ! -s "$json_file" ]; then
    cat "$log_file" >&2
    echo "whisper.cpp did not produce JSON output." >&2
    exit 70
fi

python3 - "$json_file" "$language" <<'PY'
import json
import re
import sys

path, language = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

def parse_time(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value) / 1000.0 if float(value) > 1000 else float(value)
    if isinstance(value, str):
        match = re.match(r"(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)", value.strip())
        if match:
            hours = int(match.group(1) or 0)
            minutes = int(match.group(2))
            seconds = float(match.group(3))
            return hours * 3600 + minutes * 60 + seconds
    return None

segments = []
raw_segments = payload.get("transcription") or payload.get("segments") or []
for index, item in enumerate(raw_segments):
    text = str(item.get("text", "")).strip()
    if not text:
        continue
    offsets = item.get("offsets") if isinstance(item.get("offsets"), dict) else {}
    start = parse_time(item.get("start")) if "start" in item else parse_time(offsets.get("from"))
    end = parse_time(item.get("end")) if "end" in item else parse_time(offsets.get("to"))
    segments.append(
        {
            "index": index,
            "start": start,
            "end": end,
            "text": text,
            "language": None if language == "auto" else language,
            "isFinal": True,
        }
    )

if not segments:
    text = str(payload.get("text", "")).strip()
    if not text and isinstance(raw_segments, list):
        text = " ".join(str(item.get("text", "")).strip() for item in raw_segments).strip()
    if not text:
        raise SystemExit("whisper.cpp returned an empty transcript.")
    segments = [{"index": 0, "start": 0, "end": None, "text": text, "language": None if language == "auto" else language, "isFinal": True}]

print(json.dumps({"segments": segments}, ensure_ascii=False))
PY
