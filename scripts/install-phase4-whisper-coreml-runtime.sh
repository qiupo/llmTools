#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASR_ROOT="${LLMTOOLS_ASR_RUNTIME_ROOT:-$HOME/Library/Application Support/llmTools/asr-runtime}"
WHISPER_ROOT="${LLMTOOLS_WHISPER_CPP_ROOT:-$ASR_ROOT/whisper-cpp}"
WHISPER_REPO="${LLMTOOLS_WHISPER_CPP_REPO:-$WHISPER_ROOT/whisper.cpp}"
COREML_VENV="${LLMTOOLS_WHISPER_COREML_VENV:-$WHISPER_ROOT/coreml-venv}"
MODEL_NAME="${LLMTOOLS_WHISPER_CPP_MODEL:-base}"
MODEL_ALIAS_DIR="$WHISPER_ROOT/models/whisper-$MODEL_NAME-coreml"
SOURCE_METHOD="${LLMTOOLS_WHISPER_CPP_SOURCE_METHOD:-archive}"
SOURCE_URL="${LLMTOOLS_WHISPER_CPP_SOURCE_URL:-https://sourceforge.net/projects/whisper-cpp.mirror/files/v1.9.1/v1.9.1%20source%20code.tar.gz/download}"
GGML_SOURCE="${LLMTOOLS_WHISPER_CPP_GGML_SOURCE:-openai}"
RUNNER_PATH="$SCRIPT_DIR/llmtools-whisper-coreml-runner.sh"

if [ ! -f "$RUNNER_PATH" ]; then
    RUNNER_PATH="$ROOT_DIR/scripts/llmtools-whisper-coreml-runner.sh"
fi

if ! command -v git >/dev/null 2>&1; then
    echo "error: git is required to install whisper.cpp." >&2
    exit 69
fi
if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required to prepare the Core ML generation Python environment." >&2
    exit 69
fi

mkdir -p "$WHISPER_ROOT"
if [ ! -x "$COREML_VENV/bin/python" ]; then
    uv venv "$COREML_VENV" --python "${LLMTOOLS_WHISPER_COREML_PYTHON:-python3.12}"
fi

CMAKE_BIN="$(command -v cmake || true)"
if [ -z "$CMAKE_BIN" ]; then
    uv pip install --python "$COREML_VENV/bin/python" -U cmake
    CMAKE_BIN="$COREML_VENV/bin/cmake"
fi
if [ ! -x "$CMAKE_BIN" ]; then
    echo "error: cmake is required to build whisper.cpp." >&2
    exit 69
fi

source_ready() {
    [ -f "$WHISPER_REPO/CMakeLists.txt" ] && [ -f "$WHISPER_REPO/models/download-ggml-model.sh" ]
}

install_source_archive() {
    local archive="$WHISPER_ROOT/whisper.cpp-source.tar.gz"
    local stage="$WHISPER_ROOT/.whisper.cpp-source"
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --retry 5 --retry-delay 2 --retry-all-errors -o "$archive" "$SOURCE_URL"
    else
        "$COREML_VENV/bin/python" - <<PY
import urllib.request
urllib.request.urlretrieve("$SOURCE_URL", "$archive")
PY
    fi
    rm -rf "$stage"
    mkdir -p "$stage"
    tar -xzf "$archive" -C "$stage" --strip-components=1
    rm -rf "$WHISPER_REPO"
    mv "$stage" "$WHISPER_REPO"
    printf '%s\n' "$SOURCE_URL" > "$WHISPER_REPO/.llmtools-source-url"
}

install_source_git() {
    if [ -d "$WHISPER_REPO/.git" ] && source_ready; then
        git -C "$WHISPER_REPO" pull --ff-only
    else
        rm -rf "$WHISPER_REPO"
        git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$WHISPER_REPO"
    fi
}

if ! source_ready; then
    if [ "$SOURCE_METHOD" = "git" ]; then
        install_source_git
    else
        install_source_archive
    fi
fi

uv pip install --python "$COREML_VENV/bin/python" -U ane_transformers openai-whisper coremltools

ensure_openai_checkpoint_cache() {
    local checkpoint_dir="$WHISPER_ROOT/checkpoints"
    local checkpoint="$checkpoint_dir/$MODEL_NAME.pt"
    local cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/whisper"
    mkdir -p "$checkpoint_dir" "$cache_root"
    if [ ! -f "$checkpoint" ]; then
        "$COREML_VENV/bin/python" - <<PY
import whisper
whisper.load_model("$MODEL_NAME", download_root="$checkpoint_dir")
PY
    fi
    ln -sf "$checkpoint" "$cache_root/$MODEL_NAME.pt"
}

download_openai_checkpoint_and_convert_ggml() {
    local checkpoint_dir="$WHISPER_ROOT/checkpoints"
    local checkpoint="$checkpoint_dir/$MODEL_NAME.pt"
    local converted_dir="$WHISPER_ROOT/.ggml-convert-$MODEL_NAME"
    ensure_openai_checkpoint_cache
    mkdir -p "$converted_dir"
    local whisper_assets_root
    whisper_assets_root="$("$COREML_VENV/bin/python" - <<'PY'
from pathlib import Path
import whisper
print(Path(whisper.__file__).resolve().parent.parent)
PY
)"
    rm -rf "$converted_dir"
    mkdir -p "$converted_dir"
    "$COREML_VENV/bin/python" models/convert-pt-to-ggml.py "$checkpoint" "$whisper_assets_root" "$converted_dir"
    mv -f "$converted_dir/ggml-model.bin" "models/ggml-$MODEL_NAME.bin"
    rm -rf "$converted_dir"
}

generate_coreml_encoder() {
    if xcrun -f coremlc >/dev/null 2>&1; then
        PATH="$COREML_VENV/bin:$PATH" ./models/generate-coreml-model.sh "$MODEL_NAME"
        return
    fi

    PATH="$COREML_VENV/bin:$PATH" "$COREML_VENV/bin/python" \
        models/convert-whisper-to-coreml.py \
        --model "$MODEL_NAME" \
        --encoder-only True \
        --optimize-ane True
    swift -e 'import Foundation; import CoreML; let input = URL(fileURLWithPath: CommandLine.arguments[1]); let output = URL(fileURLWithPath: CommandLine.arguments[2]); let compiled = try MLModel.compileModel(at: input); try? FileManager.default.removeItem(at: output); try FileManager.default.moveItem(at: compiled, to: output); print(output.path)' \
        "models/coreml-encoder-$MODEL_NAME.mlpackage" \
        "models/ggml-$MODEL_NAME-encoder.mlmodelc"
}

(
    cd "$WHISPER_REPO"
    if [ ! -f "models/ggml-$MODEL_NAME.bin" ]; then
        if [ "$GGML_SOURCE" = "openai" ]; then
            download_openai_checkpoint_and_convert_ggml
        else
            ./models/download-ggml-model.sh "$MODEL_NAME" || download_openai_checkpoint_and_convert_ggml
        fi
    fi
    if [ ! -d "models/ggml-$MODEL_NAME-encoder.mlmodelc" ]; then
        ensure_openai_checkpoint_cache
        generate_coreml_encoder
    fi
    "$CMAKE_BIN" -B build -DWHISPER_COREML=1 -DCMAKE_BUILD_TYPE=Release
    "$CMAKE_BIN" --build build -j --config Release
)

mkdir -p "$WHISPER_ROOT/bin" "$WHISPER_ROOT/models"
ln -sf "$WHISPER_REPO/build/bin/whisper-cli" "$WHISPER_ROOT/bin/whisper-cli"
rm -rf "$MODEL_ALIAS_DIR"
mkdir -p "$MODEL_ALIAS_DIR"
ln -sf "$WHISPER_REPO/models/ggml-$MODEL_NAME.bin" "$MODEL_ALIAS_DIR/ggml-$MODEL_NAME.bin"
ln -sf "$WHISPER_REPO/models/ggml-$MODEL_NAME-encoder.mlmodelc" "$MODEL_ALIAS_DIR/ggml-$MODEL_NAME-encoder.mlmodelc"
chmod +x "$RUNNER_PATH"

echo "Installed llmTools Phase 4 whisper.cpp Core ML runtime:"
echo "  root: $WHISPER_ROOT"
echo "  cli: $WHISPER_ROOT/bin/whisper-cli"
echo "  model: $MODEL_ALIAS_DIR"
echo "  runner: $RUNNER_PATH"
echo "  command template:"
echo "  LLMTOOLS_WHISPER_CPP_ROOT='$WHISPER_ROOT' '$RUNNER_PATH' --model {model} --audio {audio} --language {language}"
