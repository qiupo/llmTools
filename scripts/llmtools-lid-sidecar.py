#!/usr/bin/env python3
"""Long-lived fastText language ID sidecar for llmTools.

Protocol:
  stdin:  one JSON object per line
  stdout: one JSON object per line

All library logs must go to stderr so stdout remains valid NDJSON.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import re
import sys
import time
from pathlib import Path
from typing import Any

PROTOCOL = "llmtools.lid/v1"
PROTOCOL_STDOUT = sys.stdout


def emit(payload: dict[str, Any]) -> None:
    payload.setdefault("protocol", PROTOCOL)
    print(json.dumps(payload, ensure_ascii=False), file=PROTOCOL_STDOUT, flush=True)


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="llmTools fastText language ID sidecar")
    parser.add_argument("--model", required=True, help="Path to lid.176.ftz or lid.176.bin")
    parser.add_argument("--top-k", type=int, default=3)
    return parser.parse_args()


def clean_text(text: str) -> str:
    value = text or ""
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def normalize_fasttext_label(label: str | None) -> str | None:
    value = (label or "").strip()
    if value.startswith("__label__"):
        value = value[len("__label__") :]
    return value or None


class FastTextLIDSidecar:
    def __init__(self, args: argparse.Namespace) -> None:
        self.model_path = Path(args.model).expanduser().resolve()
        self.top_k = max(1, int(args.top_k or 1))
        if not self.model_path.is_file():
            raise FileNotFoundError(f"fastText language ID model not found: {self.model_path}")
        with contextlib.redirect_stdout(sys.stderr):
            import fasttext

            self.model = fasttext.load_model(str(self.model_path))

    def detect(self, text: str) -> tuple[str | None, float, list[dict[str, Any]]]:
        cleaned = clean_text(text)
        if not cleaned:
            return None, 0.0, []
        labels, confidences = self.model.predict(cleaned.replace("\n", " "), k=self.top_k)
        alternatives: list[dict[str, Any]] = []
        for label, confidence in zip(labels, confidences):
            language = normalize_fasttext_label(str(label))
            if language:
                alternatives.append({"language": language, "confidence": float(confidence)})
        if not alternatives:
            return None, 0.0, []
        top = alternatives[0]
        return str(top["language"]), float(top["confidence"]), alternatives

    def run(self) -> int:
        emit({
            "type": "ready",
            "engine": "fasttext",
            "model": str(self.model_path),
        })
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
            except json.JSONDecodeError as exc:
                emit({"type": "error", "code": "invalidJSON", "message": str(exc)})
                continue

            command = request.get("command")
            request_id = request.get("requestID")
            if command == "stop":
                emit({"type": "stopped", "requestID": request_id})
                return 0
            if command != "detect":
                emit({
                    "type": "error",
                    "requestID": request_id,
                    "code": "unknownCommand",
                    "message": f"Unknown command: {command}",
                })
                continue

            started = time.perf_counter()
            try:
                language, confidence, alternatives = self.detect(str(request.get("text") or ""))
                emit({
                    "type": "result",
                    "requestID": request_id,
                    "language": language,
                    "confidence": confidence,
                    "model": str(self.model_path),
                    "alternatives": alternatives,
                    "latencyMilliseconds": int((time.perf_counter() - started) * 1000),
                })
            except Exception as exc:  # noqa: BLE001 - sidecar must report structured runtime errors.
                emit({
                    "type": "error",
                    "requestID": request_id,
                    "code": "inferenceFailed",
                    "message": str(exc),
                })
        return 0


def main() -> int:
    try:
        sidecar = FastTextLIDSidecar(parse_args())
        return sidecar.run()
    except Exception as exc:  # noqa: BLE001 - startup errors are protocol-visible.
        emit({"type": "error", "code": "runtimeMissing", "message": str(exc)})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
