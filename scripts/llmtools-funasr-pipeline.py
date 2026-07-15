#!/usr/bin/env python3
"""Run the local FunASR Nano + VAD + CAM++ + punctuation pipeline."""

from __future__ import annotations

import argparse
import contextlib
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any


MODEL_DIRECTORIES = {
    "vad": "fsmn-vad",
    "speaker": "campp",
    "punctuation": "ct-punc",
}
MODEL_CHECKPOINTS = {
    "asr": "model.pt",
    "vad": "model.pt",
    "speaker": "campplus_cn_common.bin",
    "punctuation": "model.pt",
}


class NanoTimestampLogFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        # Nano 自带时间戳时 FunASR 会跳过独立标点推理，但 vad_segment 仍可正常完成 speaker 聚类。
        return record.getMessage() != "Missing punc_model, which is required by spk_model."


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="llmTools official FunASR composite pipeline")
    parser.add_argument("--model", help="Local Fun-ASR-Nano model directory")
    parser.add_argument("--audio", help="Local 16 kHz mono WAV file")
    parser.add_argument("--language", default="auto", help="ASR language hint")
    parser.add_argument("--check", action="store_true", help="Check imports and local model files without inference")
    parser.add_argument(
        "--runtime-root",
        default=os.environ.get("LLMTOOLS_FUNASR_PIPELINE_ROOT", ""),
        help="Official FunASR runtime root",
    )
    return parser.parse_args()


def runtime_root(args: argparse.Namespace) -> Path:
    if args.runtime_root.strip():
        return Path(args.runtime_root).expanduser().resolve()
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "llmTools"
        / "asr-runtime"
        / "funasr-pipeline"
    )


def require_model_directory(path: Path, label: str, checkpoint: str) -> Path:
    if not path.is_dir() or not (path / "config.yaml").is_file() or not (path / checkpoint).is_file():
        raise RuntimeError(f"{label} model is incomplete: {path}")
    return path


def local_models(args: argparse.Namespace) -> dict[str, Path]:
    root = runtime_root(args)
    if not args.model:
        raise RuntimeError("--model is required")
    models = {
        "asr": require_model_directory(
            Path(args.model).expanduser().resolve(),
            "Fun-ASR-Nano",
            MODEL_CHECKPOINTS["asr"],
        ),
    }
    for key, directory in MODEL_DIRECTORIES.items():
        models[key] = require_model_directory(
            root / "models" / directory,
            directory,
            MODEL_CHECKPOINTS[key],
        )
    return models


def configure_offline_runtime(root: Path) -> None:
    # 安装阶段负责联网；实际转写只允许读取固定的本地模型目录。
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["MODELSCOPE_OFFLINE"] = "1"
    os.environ.setdefault("MODELSCOPE_CACHE", str(root / "cache"))


def normalized_language(value: str) -> str:
    normalized = value.strip().lower().replace("_", "-")
    if normalized in {"zh", "zh-cn", "zh-hans", "yue"}:
        return "中文"
    if normalized in {"en", "en-us", "en-gb"}:
        return "英文"
    if normalized in {"ja", "ja-jp"}:
        return "日文"
    return "auto"


def run_pipeline(args: argparse.Namespace, models: dict[str, Path]) -> dict[str, Any]:
    if not args.audio:
        raise RuntimeError("--audio is required")
    audio = Path(args.audio).expanduser().resolve()
    if not audio.is_file():
        raise RuntimeError(f"Audio file not found: {audio}")

    started = time.perf_counter()
    # FunASR及其依赖会向stdout打印加载信息；stdout必须只保留最终JSON协议。
    with contextlib.redirect_stdout(sys.stderr):
        from funasr import AutoModel

        pipeline = AutoModel(
            model=str(models["asr"]),
            vad_model=str(models["vad"]),
            vad_kwargs={"max_single_segment_time": 30000},
            spk_model=str(models["speaker"]),
            spk_mode="vad_segment",
            punc_model=str(models["punctuation"]),
            device="cpu",
            ncpu=max(1, min(os.cpu_count() or 4, 8)),
            disable_update=True,
            disable_pbar=True,
            log_level="ERROR",
        )
        log_filter = NanoTimestampLogFilter()
        root_logger = logging.getLogger()
        root_logger.addFilter(log_filter)
        try:
            result = pipeline.generate(
                input=[str(audio)],
                cache={},
                batch_size=1,
                language=normalized_language(args.language),
                itn=True,
            )
        finally:
            root_logger.removeFilter(log_filter)
    return normalize_result(result, int((time.perf_counter() - started) * 1000))


def normalize_result(result: Any, latency_ms: int) -> dict[str, Any]:
    item = result[0] if isinstance(result, list) and result else result
    if not isinstance(item, dict):
        raise RuntimeError("FunASR returned an unsupported result")
    raw_sentences = item.get("sentence_info")
    if not isinstance(raw_sentences, list):
        raw_sentences = []

    labels: dict[str, str] = {}
    segments: list[dict[str, Any]] = []
    for index, raw in enumerate(raw_sentences):
        if not isinstance(raw, dict):
            continue
        text = first_text(raw, "sentence", "text")
        if not text:
            continue
        speaker_id = str(raw.get("spk", raw.get("speaker", ""))).strip()
        if speaker_id and speaker_id not in labels:
            labels[speaker_id] = f"Speaker {len(labels) + 1}"
        segment: dict[str, Any] = {
            "index": index,
            # 官方sentence_info的start/end单位是毫秒，llmTools协议统一使用秒。
            "start": milliseconds_to_seconds(raw.get("start")),
            "end": milliseconds_to_seconds(raw.get("end")),
            "text": text,
            "isFinal": True,
        }
        if speaker_id:
            segment["speakerID"] = speaker_id
            segment["speakerLabel"] = labels[speaker_id]
        segments.append(segment)

    if not segments:
        text = first_text(item, "text", "raw_text")
        if text:
            segments.append({"index": 0, "text": text, "isFinal": True})
    if not segments:
        raise RuntimeError("FunASR returned an empty transcript")
    return {
        "protocol": "llmtools.asr/v1",
        "runtime": "funasr-nano+fsmn-vad+cam++",
        "segments": segments,
        "latencyMilliseconds": latency_ms,
    }


def first_text(item: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = item.get(key)
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return ""


def milliseconds_to_seconds(value: Any) -> float | None:
    try:
        return max(0.0, float(value) / 1000.0)
    except (TypeError, ValueError):
        return None


def main() -> int:
    args = parse_args()
    root = runtime_root(args)
    configure_offline_runtime(root)
    models = local_models(args)
    if args.check:
        with contextlib.redirect_stdout(sys.stderr):
            import funasr
            import torch

        print(json.dumps({
            "ready": True,
            "funasr": getattr(funasr, "__version__", "unknown"),
            "torch": torch.__version__,
            "device": "cpu",
            "models": {key: str(value) for key, value in models.items()},
        }, ensure_ascii=False))
        return 0
    print(json.dumps(run_pipeline(args, models), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - parent process surfaces concise stderr.
        print(str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
