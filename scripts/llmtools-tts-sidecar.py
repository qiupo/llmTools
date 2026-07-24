#!/usr/bin/env python3
"""Persistent local VoxCPM2 TTS sidecar for llmTools.

stdin/stdout use NDJSON. Library output is redirected to stderr so stdout stays
machine-readable.
"""

from __future__ import annotations

import argparse
import contextlib
import gc
import json
import signal
import sys
import time
import wave
from pathlib import Path
from typing import Any

PROTOCOL = "llmtools.tts/v1"
# stdout 只允许输出协议事件，模型库日志统一重定向到 stderr。
PROTOCOL_STDOUT = sys.stdout


def emit(payload: dict[str, Any]) -> None:
    payload.setdefault("protocol", PROTOCOL)
    print(json.dumps(payload, ensure_ascii=False), file=PROTOCOL_STDOUT, flush=True)


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def optional_text(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None


class VoxCPM2Sidecar:
    def __init__(self, model_path: Path) -> None:
        self.model_path = model_path
        self.model = None

    def load(self) -> None:
        if self.model is not None:
            return
        with contextlib.redirect_stdout(sys.stderr), contextlib.redirect_stderr(sys.stderr):
            from mlx_audio.tts.utils import load

            self.model = load(str(self.model_path))

    def unload(self) -> None:
        # 生成队列结束后显式释放 MLX 缓存，避免 TTS 模型长期占用统一内存。
        self.model = None
        gc.collect()
        try:
            import mlx.core as mx

            mx.clear_cache()
        except Exception as error:  # noqa: BLE001
            log(f"MLX cache cleanup warning: {error}")

    def generate(self, request: dict[str, Any]) -> None:
        request_id = str(request.get("requestID") or "")
        text = optional_text(request.get("text"))
        output_path = optional_text(request.get("outputPath"))
        if not request_id or not text or not output_path:
            raise ValueError("generate requires requestID, text, and outputPath")

        self.load()
        import mlx.core as mx
        import numpy as np

        mx.reset_peak_memory()
        mx.random.seed(int(request.get("seed", 42)) & 0xFFFFFFFF)
        kwargs: dict[str, Any] = {
            "text": text,
            "inference_timesteps": max(4, min(30, int(request.get("inferenceTimesteps", 10)))),
            "cfg_value": max(1.0, min(5.0, float(request.get("guidance", 2.0)))),
        }
        mappings = {
            "instruction": "instruct",
            "referenceAudioPath": "ref_audio",
            "referenceText": "ref_text",
        }
        for source, destination in mappings.items():
            value = optional_text(request.get(source))
            if value:
                kwargs[destination] = value

        started = time.perf_counter()
        result = None
        samples = None
        pcm16 = None
        try:
            with contextlib.redirect_stdout(sys.stderr), contextlib.redirect_stderr(sys.stderr):
                result = next(self.model.generate(**kwargs))
                mx.eval(result.audio)
            samples = np.asarray(result.audio, dtype=np.float32).reshape(-1)
            destination = Path(output_path)
            destination.parent.mkdir(parents=True, exist_ok=True)
            pcm16 = np.rint(np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
            sample_rate = int(result.sample_rate)
            duration = len(samples) / max(1, sample_rate)
            peak_memory_gb = mx.get_peak_memory() / 1e9
            with wave.open(str(destination), "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(sample_rate)
                output.writeframes(pcm16.tobytes())
            destination.chmod(0o600)
            elapsed = time.perf_counter() - started
        finally:
            # 每段落盘后只回收临时推理缓冲区，模型权重仍保留在 self.model 中供下一段复用。
            result = None
            samples = None
            pcm16 = None
            gc.collect()
            try:
                active_memory_gb = mx.get_active_memory() / 1e9
                cached_before_gb = mx.get_cache_memory() / 1e9
                mx.clear_cache()
                cached_after_gb = mx.get_cache_memory() / 1e9
                log(
                    "TTS memory cleanup "
                    f"active={active_memory_gb:.2f}GB "
                    f"cache={cached_before_gb:.2f}->{cached_after_gb:.2f}GB "
                    f"peak={mx.get_peak_memory() / 1e9:.2f}GB"
                )
            except Exception as error:  # noqa: BLE001
                log(f"MLX per-segment cache cleanup warning: {error}")

        emit(
            {
                "type": "generated",
                "requestID": request_id,
                "outputPath": str(destination),
                "duration": duration,
                "sampleRate": sample_rate,
                "processingTime": elapsed,
                "peakMemoryGB": peak_memory_gb,
            }
        )

    def run(self) -> None:
        self.load()
        emit(
            {
                "type": "ready",
                "available": True,
                "model": str(self.model_path),
            }
        )
        for raw_line in sys.stdin:
            line = raw_line.strip()
            if not line:
                continue
            request: dict[str, Any] = {}
            try:
                request = json.loads(line)
                command = request.get("command")
                if command == "generate":
                    self.generate(request)
                elif command == "unload":
                    self.unload()
                    emit({"type": "unloaded", "requestID": request.get("requestID")})
                elif command == "stop":
                    emit({"type": "stopped", "requestID": request.get("requestID")})
                    return
                else:
                    raise ValueError(f"unsupported command: {command}")
            except Exception as error:  # noqa: BLE001
                log(f"TTS request failed: {error}")
                emit(
                    {
                        "type": "error",
                        "requestID": request.get("requestID"),
                        "code": "generationFailed",
                        "message": str(error),
                    }
                )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="llmTools VoxCPM2 TTS sidecar")
    parser.add_argument("--model", required=True, type=Path)
    return parser.parse_args()


def terminate_from_signal(_signum: int, _frame: Any) -> None:
    raise SystemExit(0)


def main() -> None:
    args = parse_args()
    signal.signal(signal.SIGTERM, terminate_from_signal)
    signal.signal(signal.SIGINT, terminate_from_signal)
    sidecar = VoxCPM2Sidecar(args.model)
    try:
        sidecar.run()
    finally:
        sidecar.unload()


if __name__ == "__main__":
    main()
