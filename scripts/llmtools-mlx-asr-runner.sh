#!/usr/bin/env bash
set -euo pipefail

model=""
audio=""
language="${LLMTOOLS_ASR_LANGUAGE:-auto}"
max_tokens="${LLMTOOLS_ASR_MAX_TOKENS:-512}"
chunk_duration="${LLMTOOLS_ASR_CHUNK_DURATION:-30}"
asr_root="${LLMTOOLS_ASR_RUNTIME_ROOT:-$HOME/Library/Application Support/llmTools/asr-runtime}"

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
        --max-tokens)
            max_tokens="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 64
            ;;
    esac
done

if [ -z "$model" ] || [ -z "$audio" ]; then
    echo "Usage: llmtools-mlx-asr-runner.sh --model <model-dir> --audio <wav-file> [--language <code>]" >&2
    exit 64
fi

if [ ! -d "$model" ]; then
    echo "ASR model directory not found: $model" >&2
    exit 66
fi

if [ ! -f "$audio" ]; then
    echo "ASR audio file not found: $audio" >&2
    exit 66
fi

model_type=""
if command -v plutil >/dev/null 2>&1; then
    model_type="$(plutil -extract model_type raw -o - "$model/config.json" 2>/dev/null || true)"
fi
if [ -z "$model_type" ] && command -v python3 >/dev/null 2>&1; then
    model_type="$(python3 - "$model/config.json" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle).get("model_type", "")
print(value if isinstance(value, str) else "")
PY
)"
fi
if [ -z "$model_type" ]; then
    model_type="$(sed -n 's/^[[:space:]]*"model_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$model/config.json" 2>/dev/null | head -n 1)"
fi
case "$model_type" in
    funasr)
        venv="${LLMTOOLS_FUN_ASR_VENV:-$asr_root/funasr-venv}"
        ;;
    fun_asr_nano|funasr_nano)
        venv="${LLMTOOLS_FUN_ASR_NANO_VENV:-$asr_root/funasr-nano-venv}"
        ;;
    sensevoice)
        venv="${LLMTOOLS_SENSEVOICE_ASR_VENV:-$asr_root/sensevoice-venv}"
        ;;
    *)
        venv="${LLMTOOLS_ASR_VENV:-$asr_root/venv}"
        ;;
esac

if [ "$model_type" = "vibevoice_asr" ] && [ -z "${LLMTOOLS_ASR_MAX_TOKENS:-}" ]; then
    max_tokens="8192"
fi

if ! [[ "$chunk_duration" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "LLMTOOLS_ASR_CHUNK_DURATION must be a positive number of seconds." >&2
    exit 64
fi

has_vibevoice_tokenizer() {
    local candidate="$1"
    [ -n "$candidate" ] \
        && [ -f "$candidate/tokenizer_config.json" ] \
        && { [ -f "$candidate/tokenizer.json" ] || [ -f "$candidate/vocab.json" ]; }
}

resolve_vibevoice_tokenizer_dir() {
    local candidates=()
    if [ -n "${LLMTOOLS_VIBEVOICE_TOKENIZER_DIR:-}" ]; then
        candidates+=("$LLMTOOLS_VIBEVOICE_TOKENIZER_DIR")
    fi
    candidates+=(
        "$asr_root/qwen2.5-tokenizer"
        "$HOME/code/models/lmstudio-community/Qwen2.5-0.5B-Instruct-MLX-4bit"
        "$HOME/code/models/mlx-community/Qwen3-ASR-0.6B-4bit"
        "$HOME/code/models/mlx-community/Qwen3-ASR-0.6B-bf16"
        "$HOME/code/models/mlx-community/Qwen3-ASR-1.7B-bf16"
    )
    for candidate in "${candidates[@]}"; do
        if has_vibevoice_tokenizer "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

asr_bin="$venv/bin/mlx_audio.stt.generate"
if [ ! -x "$asr_bin" ]; then
    if [ "$model_type" = "funasr" ]; then
        echo "Fun-ASR mlx-audio-plus runtime not found at $asr_bin. Install it with scripts/install-phase4-funasr-mlx-runtime.sh or set LLMTOOLS_FUN_ASR_VENV." >&2
    elif [ "$model_type" = "fun_asr_nano" ] || [ "$model_type" = "funasr_nano" ]; then
        echo "Fun-ASR-Nano mlx-audio runtime not found at $asr_bin. Install it with scripts/install-phase4-funasr-nano-mlx-runtime.sh or set LLMTOOLS_FUN_ASR_NANO_VENV." >&2
    elif [ "$model_type" = "sensevoice" ]; then
        echo "SenseVoice mlx-audio runtime not found at $asr_bin. Install it with scripts/install-phase4-sensevoice-mlx-runtime.sh or set LLMTOOLS_SENSEVOICE_ASR_VENV." >&2
    else
        echo "mlx-audio runtime not found at $asr_bin. Install it with scripts/install-phase4-mlx-asr-runtime.sh or set LLMTOOLS_ASR_VENV." >&2
    fi
    exit 69
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/llmtools-mlx-asr.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
out_base="$tmp_dir/transcript"
format="json"
log_file="$tmp_dir/mlx-audio.log"
model_arg="$model"

if [ "$model_type" = "funasr" ]; then
    ln -s "$model" "$tmp_dir/funasr"
    model_arg="$tmp_dir/funasr"
fi

if [ "$model_type" = "vibevoice_asr" ] && ! has_vibevoice_tokenizer "$model"; then
    tokenizer_dir="$(resolve_vibevoice_tokenizer_dir || true)"
    if [ -z "$tokenizer_dir" ]; then
        echo "VibeVoice-ASR MLX tokenizer files are missing. Run scripts/install-phase4-mlx-asr-runtime.sh or Settings > Media Subtitle > Repair runtime to install the Qwen2.5 tokenizer sidecar, or set LLMTOOLS_VIBEVOICE_TOKENIZER_DIR." >&2
        exit 69
    fi
    wrapped_model="$tmp_dir/vibevoice-model"
    mkdir -p "$wrapped_model"
    find "$model" -mindepth 1 -maxdepth 1 -exec ln -s {} "$wrapped_model/" \;
    for tokenizer_file in tokenizer_config.json tokenizer.json vocab.json merges.txt special_tokens_map.json added_tokens.json tokenizer.model; do
        if [ -f "$tokenizer_dir/$tokenizer_file" ] && [ ! -e "$wrapped_model/$tokenizer_file" ]; then
            ln -s "$tokenizer_dir/$tokenizer_file" "$wrapped_model/$tokenizer_file"
        fi
    done
    model_arg="$wrapped_model"
fi

if [ "$model_type" = "sensevoice" ]; then
    format="txt"
fi
out_file="$out_base.$format"
help_output="$("$asr_bin" --help 2>&1 || true)"

args=(
    --model "$model_arg"
    --audio "$audio"
)

if printf '%s' "$help_output" | grep -q -- "--output-path"; then
    args+=(--output-path "$out_base")
else
    args+=(--output "$out_file")
fi

if printf '%s' "$help_output" | grep -q -- "--max-tokens"; then
    args+=(--max-tokens "$max_tokens")
elif printf '%s' "$help_output" | grep -q -- "--max_tokens"; then
    args+=(--max_tokens "$max_tokens")
fi

if printf '%s' "$help_output" | grep -q -- "--chunk-duration"; then
    args+=(--chunk-duration "$chunk_duration")
fi

args+=(--format "$format")

if [ -n "$language" ] && printf '%s' "$help_output" | grep -q -- "--language"; then
    args+=(--language "$language")
fi

if ! "$asr_bin" "${args[@]}" >"$log_file" 2>&1; then
    cat "$log_file" >&2
    exit 70
fi

for candidate in "$out_base.$format" "$out_file" "$out_file.txt" "$out_base.txt" "$out_base.json" "$out_base.json.txt"; do
    if [ -s "$candidate" ]; then
        cat "$candidate"
        exit 0
    fi
done

cat "$log_file" >&2
echo "mlx-audio did not produce a transcript file." >&2
exit 70
