#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="llmTools"
BUNDLE_ID="local.llmtools.app"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DEFAULT_OMLX_METALLIB="/Applications/oMLX.app/Contents/Python/framework-mlx-framework/lib/python3.11/site-packages/mlx/lib/mlx.metallib"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/llmTools"
NATIVE_HOST_PATH="$BIN_DIR/LLMToolsNativeHost"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp "$NATIVE_HOST_PATH" "$MACOS_DIR/LLMToolsNativeHost"
if [ -d "$BIN_DIR/llama.framework" ]; then
    cp -R "$BIN_DIR/llama.framework" "$MACOS_DIR/llama.framework"
fi
if [ -d "$ROOT_DIR/browser-extension" ]; then
    cp -R "$ROOT_DIR/browser-extension" "$RESOURCES_DIR/browser-extension"
fi

MLX_METALLIB_SOURCE="${MLX_METALLIB_PATH:-}"
if [ -z "$MLX_METALLIB_SOURCE" ] && [ -f "$DEFAULT_OMLX_METALLIB" ]; then
    MLX_METALLIB_SOURCE="$DEFAULT_OMLX_METALLIB"
fi
if [ -n "$MLX_METALLIB_SOURCE" ] && [ -f "$MLX_METALLIB_SOURCE" ]; then
    cp "$MLX_METALLIB_SOURCE" "$MACOS_DIR/mlx.metallib"
else
    echo "warning: mlx.metallib not found; MLX models will fail until MLX_METALLIB_PATH points to mlx.metallib."
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>llmTools</string>
    <key>CFBundleIdentifier</key>
    <string>local.llmtools.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>llmTools</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Packaged $APP_DIR"
