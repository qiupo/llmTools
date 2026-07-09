#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${LLMTOOLS_FASTMT_RUNTIME_DIR:-$HOME/Library/Application Support/llmTools/fastmt-runtime}"
VENV_DIR="$RUNTIME_DIR/venv"
PYTHON_BIN="${LLMTOOLS_FASTMT_BOOTSTRAP_PYTHON:-}"

if [[ -z "$PYTHON_BIN" ]]; then
  for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" -c 'import lzma' >/dev/null 2>&1; then
      PYTHON_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [[ -z "$PYTHON_BIN" ]]; then
  echo "No Python 3 runtime was found." >&2
  exit 1
fi

PYTHON_VERSION="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PYTHON_MINOR="$("$PYTHON_BIN" -c 'import sys; print(sys.version_info.minor)')"
if [[ "$PYTHON_VERSION" == 3.* && "$PYTHON_MINOR" -lt 10 ]]; then
  ARGOS_PACKAGE_SPEC="argostranslate==1.9.6"
else
  ARGOS_PACKAGE_SPEC="argostranslate>=1.9,<2"
fi

mkdir -p "$RUNTIME_DIR"
if [[ -x "$VENV_DIR/bin/python" ]]; then
  current_version="$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  if [[ "$current_version" != "$PYTHON_VERSION" ]]; then
    rm -rf "$VENV_DIR"
  fi
fi

"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade --timeout 120 --retries 5 pip
"$VENV_DIR/bin/python" -m pip install --timeout 120 --retries 5 "$ARGOS_PACKAGE_SPEC"
"$VENV_DIR/bin/python" - <<'PY'
import sys
import socket

import argostranslate.package
import argostranslate.translate

socket.setdefaulttimeout(120)
desired_pairs = [("en", "zh"), ("en", "zt")]
installed = argostranslate.translate.get_installed_languages()
installed_pairs = {
    (source.code, target.code)
    for source in installed
    for target in installed
    if source.code != target.code and source.get_translation(target) is not None
}
if any(pair in installed_pairs for pair in desired_pairs):
    print("Argos en->zh language package is already installed.")
    sys.exit(0)

argostranslate.package.update_package_index()
available = argostranslate.package.get_available_packages()
for source_code, target_code in desired_pairs:
    package = next(
        (
            item for item in available
            if item.from_code == source_code and item.to_code == target_code
        ),
        None,
    )
    if package is None:
        continue
    download_path = package.download()
    argostranslate.package.install_from_path(download_path)
    print(f"Installed Argos language package: {source_code}->{target_code}")
    sys.exit(0)

raise SystemExit("No Argos en->zh language package was found in the package index.")
PY

cat <<MSG
llmTools Argos Translate runtime and en->zh language package are installed.

Set this when launching llmTools if the app cannot discover the venv:
  LLMTOOLS_FASTMT_PYTHON="$VENV_DIR/bin/python"
MSG
