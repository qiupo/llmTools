#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
DEFAULT_OMLX_METALLIB="/Applications/oMLX.app/Contents/Python/framework-mlx-framework/lib/python3.11/site-packages/mlx/lib/mlx.metallib"

cd "$ROOT_DIR"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

MLX_METALLIB_SOURCE="${MLX_METALLIB_PATH:-}"
if [ -z "$MLX_METALLIB_SOURCE" ] && [ -f "$DEFAULT_OMLX_METALLIB" ]; then
    MLX_METALLIB_SOURCE="$DEFAULT_OMLX_METALLIB"
fi

if [ -z "$MLX_METALLIB_SOURCE" ] || [ ! -f "$MLX_METALLIB_SOURCE" ]; then
    echo "error: mlx.metallib not found. Set MLX_METALLIB_PATH=/path/to/mlx.metallib." >&2
    exit 1
fi

cp "$MLX_METALLIB_SOURCE" "$BIN_DIR/mlx.metallib"
echo "Copied mlx.metallib to $BIN_DIR/mlx.metallib"
