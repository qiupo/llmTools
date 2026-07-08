#!/usr/bin/env bash
set -euo pipefail

model=""
audio=""
language="${LLMTOOLS_ASR_LANGUAGE:-auto}"
max_tokens="${LLMTOOLS_ASR_MAX_TOKENS:-512}"
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

model_type="$(sed -n 's/.*"model_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$model/config.json" 2>/dev/null | head -n 1)"
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
