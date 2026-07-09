#!/usr/bin/env python3
"""Normalize pyannote speaker diarization output for llmTools."""

from __future__ import annotations

import argparse
import inspect
import json
import os
import sys
import time
from pathlib import Path
from typing import Any


def patch_huggingface_hub_auth_keyword() -> None:
    """Keep pyannote.audio 3.1.x working with huggingface_hub 1.x."""
    try:
        import pyannote.audio.core.pipeline as pipeline_module
    except Exception:
        return

    original = pipeline_module.hf_hub_download
    parameters = inspect.signature(original).parameters

    def hf_hub_download_compat(*args: Any, use_auth_token: Any = None, token: Any = None, **kwargs: Any) -> Any:
        resolved_token = token if token is not None else use_auth_token
        if "token" in parameters:
            kwargs["token"] = resolved_token
        elif "use_auth_token" in parameters:
            kwargs["use_auth_token"] = resolved_token
        return original(*args, **kwargs)

    pipeline_module.hf_hub_download = hf_hub_download_compat


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="llmTools pyannote diarization sidecar")
    parser.add_argument("--audio", required=True, help="16 kHz mono WAV audio")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--model", default="pyannote/speaker-diarization-3.1")
    parser.add_argument("--hf-token", default=os.environ.get("PYANNOTE_AUTH_TOKEN") or os.environ.get("HF_TOKEN") or "")
    return parser.parse_args()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def main() -> int:
    args = parse_args()
    audio_path = Path(args.audio).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    if not audio_path.is_file():
        raise FileNotFoundError(f"Audio file not found: {audio_path}")
    if not args.hf_token:
        raise RuntimeError("Hugging Face token missing. Accept pyannote/speaker-diarization-3.1 terms and set PYANNOTE_AUTH_TOKEN.")

    started = time.perf_counter()
    from pyannote.audio import Pipeline
    patch_huggingface_hub_auth_keyword()

    pipeline = Pipeline.from_pretrained(args.model, use_auth_token=args.hf_token)
    if pipeline is None:
        raise RuntimeError(
            f"Could not load {args.model}. Accept the model terms with the same Hugging Face account "
            "used by this token, then run health check again."
        )
    diarization = pipeline(str(audio_path))
    speaker_labels: dict[str, str] = {}
    turns: list[dict[str, Any]] = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        if speaker not in speaker_labels:
            speaker_labels[speaker] = f"Speaker {len(speaker_labels) + 1}"
        turns.append({
            "start": float(turn.start),
            "end": float(turn.end),
            "speakerID": str(speaker),
            "speakerLabel": speaker_labels[speaker],
        })
    write_json(output_path, {
        "protocol": "llmtools.diarization/v1",
        "model": args.model,
        "turns": turns,
        "latencyMilliseconds": int((time.perf_counter() - started) * 1000),
    })
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - command runner surfaces stderr.
        print(str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
