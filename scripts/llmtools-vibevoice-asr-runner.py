#!/usr/bin/env python3
"""Run VibeVoice-ASR and normalize rich transcription for llmTools.

stdout is reserved for a single JSON envelope:
{"segments":[{"start":0.0,"end":1.2,"speakerID":"0","speakerLabel":"Speaker 1","text":"..."}]}
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="llmTools VibeVoice-ASR runner")
    parser.add_argument("--model", required=True, help="Local VibeVoice-ASR model directory")
    parser.add_argument("--audio", required=True, help="16 kHz mono WAV file")
    parser.add_argument("--language", default="auto", help="ASR language hint; VibeVoice normally auto-detects")
    parser.add_argument("--prompt", default=os.environ.get("LLMTOOLS_VIBEVOICE_ASR_PROMPT", ""))
    parser.add_argument(
        "--max-new-tokens",
        type=int,
        default=int(os.environ.get("LLMTOOLS_VIBEVOICE_ASR_MAX_NEW_TOKENS", "0") or "0"),
        help="Optional generation cap. 0 lets the model/runtime default decide.",
    )
    parser.add_argument(
        "--device",
        default=os.environ.get("LLMTOOLS_VIBEVOICE_ASR_DEVICE", "auto"),
        choices=["auto", "cuda", "mps", "cpu"],
    )
    parser.add_argument(
        "--attn-implementation",
        default=os.environ.get("LLMTOOLS_VIBEVOICE_ASR_ATTN", "sdpa"),
        help="Attention implementation passed to from_pretrained when supported.",
    )
    return parser.parse_args()


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def pick_device(requested: str) -> str:
    if requested != "auto":
        return requested
    import torch

    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) is not None and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def load_vibevoice(model_path: Path, device: str, attn_implementation: str) -> tuple[Any, Any, str]:
    import torch
    from vibevoice.modular.modeling_vibevoice_inference_asr import (
        VibeVoiceForConditionalGenerationInferenceASR,
    )
    from vibevoice.processor.vibevoice_processor import VibeVoiceASRProcessor

    dtype = torch.bfloat16 if device == "cuda" else torch.float32
    kwargs: dict[str, Any] = {
        "torch_dtype": dtype,
        "trust_remote_code": True,
    }
    if device == "cuda":
        kwargs["device_map"] = "auto"
    if attn_implementation:
        kwargs["attn_implementation"] = attn_implementation

    try:
        model = VibeVoiceForConditionalGenerationInferenceASR.from_pretrained(str(model_path), **kwargs)
    except TypeError:
        kwargs.pop("attn_implementation", None)
        model = VibeVoiceForConditionalGenerationInferenceASR.from_pretrained(str(model_path), **kwargs)
    if device in {"mps", "cpu"}:
        model = model.to(device)
    model.eval()

    processor = VibeVoiceASRProcessor.from_pretrained(str(model_path))
    return model, processor, device


def run_inference(args: argparse.Namespace) -> Any:
    import torch

    model_path = Path(args.model).expanduser().resolve()
    audio_path = Path(args.audio).expanduser().resolve()
    if not model_path.exists():
        raise FileNotFoundError(f"VibeVoice-ASR model directory not found: {model_path}")
    if not audio_path.is_file():
        raise FileNotFoundError(f"ASR audio file not found: {audio_path}")

    device = pick_device(args.device)
    log(f"Loading VibeVoice-ASR model from {model_path} on {device}")
    model, processor, _ = load_vibevoice(model_path, device, args.attn_implementation)

    request_kwargs: dict[str, Any] = {"audio_path": str(audio_path)}
    if args.prompt.strip():
        request_kwargs["prompt"] = args.prompt.strip()
    try:
        inputs = processor.apply_transcription_request(**request_kwargs)
    except TypeError:
        request_kwargs.pop("prompt", None)
        inputs = processor.apply_transcription_request(**request_kwargs)

    with contextlib.redirect_stdout(sys.stderr):
        if hasattr(inputs, "to"):
            target_device = getattr(model, "device", None)
            if target_device is None:
                try:
                    target_device = next(model.parameters()).device
                except StopIteration:
                    target_device = torch.device(device)
            inputs = inputs.to(target_device)

        generate_kwargs: dict[str, Any] = {}
        if args.max_new_tokens > 0:
            generate_kwargs["max_new_tokens"] = args.max_new_tokens
        with torch.no_grad():
            outputs = model.generate(**inputs, **generate_kwargs)

    input_ids = inputs.get("input_ids") if isinstance(inputs, dict) else getattr(inputs, "input_ids", None)
    if input_ids is not None and hasattr(outputs, "__getitem__"):
        try:
            outputs = outputs[:, input_ids.shape[1] :]
        except Exception:
            pass

    return processor.post_process_transcription(outputs, return_text=False)


def normalize_transcription(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        for key in ("segments", "sentence_info", "sentences"):
            if isinstance(raw.get(key), list):
                return {"segments": normalize_segments(raw[key])}
        if raw.get("text") or raw.get("transcript"):
            return {"segments": normalize_segments([raw])}
    if isinstance(raw, list):
        return {"segments": normalize_segments(raw)}
    if isinstance(raw, str):
        parsed = parse_embedded_json(raw)
        if parsed is not None:
            return normalize_transcription(parsed)
        return {"segments": normalize_segments([{"text": raw}])}
    return {"segments": []}


def parse_embedded_json(raw: str) -> Any | None:
    text = raw.strip()
    if not text:
        return None
    with contextlib.suppress(json.JSONDecodeError):
        return json.loads(text)
    match = re.search(r"(\[[\s\S]*\]|\{[\s\S]*\})", text)
    if match:
        with contextlib.suppress(json.JSONDecodeError):
            return json.loads(match.group(1))
    return None


def normalize_segments(raw_segments: list[Any]) -> list[dict[str, Any]]:
    segments: list[dict[str, Any]] = []
    speaker_labels: dict[str, str] = {}
    for index, item in enumerate(raw_segments):
        if not isinstance(item, dict):
            item = {"text": str(item)}
        text = first_string(item, ["text", "Content", "content", "transcript"])
        if not text:
            continue
        speaker_id = first_string(item, ["speaker_id", "speakerID", "speaker", "Speaker", "spk"])
        speaker_label = first_string(item, ["speaker_label", "speakerLabel", "label"])
        if speaker_id and not speaker_label:
            if speaker_id not in speaker_labels:
                speaker_labels[speaker_id] = speaker_label_for(speaker_id, len(speaker_labels) + 1)
            speaker_label = speaker_labels[speaker_id]
        segment: dict[str, Any] = {
            "index": first_int(item, ["index", "idx"], index),
            "start": first_time(item, ["start", "start_time", "startTime", "Start"]),
            "end": first_time(item, ["end", "end_time", "endTime", "End"]),
            "text": text,
            "isFinal": True,
        }
        if speaker_id:
            segment["speakerID"] = speaker_id
        if speaker_label:
            segment["speakerLabel"] = speaker_label
        language = first_string(item, ["language", "sourceLanguage", "source_language"])
        if language:
            segment["language"] = language
        segments.append(segment)
    return segments


def first_string(item: dict[str, Any], keys: list[str]) -> str | None:
    for key in keys:
        value = item.get(key)
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return None


def first_int(item: dict[str, Any], keys: list[str], default: int) -> int:
    for key in keys:
        value = item.get(key)
        if value is None:
            continue
        with contextlib.suppress(ValueError, TypeError):
            return int(value)
    return default


def first_time(item: dict[str, Any], keys: list[str]) -> float | None:
    for key in keys:
        value = item.get(key)
        parsed = parse_time(value)
        if parsed is not None:
            return parsed
    return None


def parse_time(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return max(0.0, float(value))
    text = str(value).strip()
    if not text:
        return None
    with contextlib.suppress(ValueError):
        return max(0.0, float(text))
    parts = text.split(":")
    if not 1 <= len(parts) <= 3:
        return None
    total = 0.0
    multiplier = 1.0
    for part in reversed(parts):
        with contextlib.suppress(ValueError):
            total += float(part) * multiplier
            multiplier *= 60.0
            continue
        return None
    return max(0.0, total)


def speaker_label_for(speaker_id: str, fallback_index: int) -> str:
    raw = speaker_id.strip()
    if not raw:
        return f"Speaker {fallback_index}"
    with contextlib.suppress(ValueError):
        return f"Speaker {int(raw) + 1}"
    normalized = raw.replace("_", " ").strip()
    if normalized.lower().startswith("speaker"):
        return normalized
    return f"Speaker {fallback_index}"


def main() -> int:
    args = parse_args()
    try:
        raw = run_inference(args)
        print(json.dumps(normalize_transcription(raw), ensure_ascii=False))
        return 0
    except Exception as exc:
        log(f"VibeVoice-ASR failed: {exc}")
        return 70


if __name__ == "__main__":
    raise SystemExit(main())
