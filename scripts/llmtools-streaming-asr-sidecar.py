#!/usr/bin/env python3
"""Long-lived local ASR sidecar for llmTools live subtitles.

Protocol:
  stdin:  one JSON object per line
  stdout: one JSON object per line

All model/library logs are redirected to stderr so stdout remains valid NDJSON.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import http.client
import json
import os
import re
import signal
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
import wave
from pathlib import Path
from typing import Any

import numpy as np

PROTOCOL_STDOUT = sys.stdout

# 原版 Fun-ASR-Nano 必须只使用已经下载到本机的模型，实时会话中禁止隐式联网补文件。
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("MODELSCOPE_OFFLINE", "1")


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False), file=PROTOCOL_STDOUT, flush=True)


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def terminate_from_signal(signum: int, _frame: Any) -> None:
    # 让 SIGTERM 穿过 main 的 finally，确保 whisper 子服务和临时目录一并清理。
    raise SystemExit(128 + signum)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="llmTools streaming ASR sidecar")
    parser.add_argument("--model", required=True, help="Local model directory")
    parser.add_argument("--family", required=True, help="SpeechModelFamily raw value")
    parser.add_argument("--language", default="auto", help="Default source language hint")
    parser.add_argument("--max-tokens", type=int, default=192)
    return parser.parse_args()


def read_model_type(model_path: Path) -> str:
    config_path = model_path / "config.json"
    try:
        with config_path.open("r", encoding="utf-8") as handle:
            value = json.load(handle).get("model_type")
            return str(value or "")
    except Exception:
        return ""


def language_code(value: str | None) -> str:
    normalized = (value or "auto").strip()
    if not normalized:
        return "auto"
    normalized = normalized.replace("_", "-")
    aliases = {
        "zh-hans": "zh",
        "zh-hant": "zh",
        "zh-cn": "zh",
        "zh-tw": "zh",
        "cn": "zh",
    }
    return aliases.get(normalized.lower(), normalized)


def qwen_language(value: str | None) -> str | None:
    code = language_code(value).lower()
    if code in {"", "auto"}:
        return None
    aliases = {
        "zh": "Chinese",
        "yue": "Chinese",
        "en": "English",
        "ja": "Japanese",
        "ko": "Korean",
        "fr": "French",
        "de": "German",
        "es": "Spanish",
        "pt": "Portuguese",
        "it": "Italian",
        "ru": "Russian",
    }
    return aliases.get(code, value)


def whisper_language(value: str | None) -> str:
    code = language_code(value).lower()
    if code in {"", "auto"}:
        return "auto"
    aliases = {
        "yue": "zh",
        "fil": "tl",
    }
    return aliases.get(code, code.split("-", 1)[0])


def fun_language(value: str | None, family: str) -> str | None:
    code = language_code(value)
    if family == "funASRNano" and code.lower() == "auto":
        return None
    return code


def official_fun_language(value: str | None) -> str | None:
    code = language_code(value).lower()
    if code in {"", "auto"}:
        return None
    return {
        "zh": "中文",
        "yue": "粤语",
        "en": "English",
        "ja": "日本語",
        "ko": "한국어",
    }.get(code, value)


def clean_text(text: str) -> str:
    value = text or ""
    value = re.sub(r"<think>.*?</think>", "", value, flags=re.DOTALL)
    if "<asr_text>" in value:
        value = value.split("<asr_text>", 1)[1]
    value = re.sub(r"<\|[^>]+?\|>", "", value)
    value = value.replace("<s>", "").replace("</s>", "")
    value = value.replace("▁", " ")
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def pcm16_bytes(pcm16_base64: str) -> bytes:
    raw = base64.b64decode(pcm16_base64)
    return raw[: len(raw) - (len(raw) % 2)]


def pcm16_to_float32(pcm16_base64: str) -> np.ndarray:
    raw = pcm16_bytes(pcm16_base64)
    return pcm16_data_to_float32(raw)


def pcm16_data_to_float32(raw: bytes) -> np.ndarray:
    if not raw:
        return np.zeros((0,), dtype=np.float32)
    samples = np.frombuffer(raw, dtype="<i2")
    return samples.astype(np.float32) / 32768.0


def write_pcm16_wav(path: Path, pcm16_data: bytes, sample_rate: int) -> None:
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(int(sample_rate or 16000))
        handle.writeframes(pcm16_data)


class StreamingASRSidecar:
    def __init__(self, args: argparse.Namespace) -> None:
        self.family = args.family
        self.default_language = args.language
        self.max_tokens = max(1, int(args.max_tokens))
        self.model_path = Path(args.model).expanduser().resolve()
        if not self.model_path.exists():
            raise FileNotFoundError(f"ASR model directory not found: {self.model_path}")
        self._tmpdir: tempfile.TemporaryDirectory[str] | None = None
        self._whisper_process: subprocess.Popen[str] | None = None
        self._whisper_port: int | None = None
        self._whisper_tmpdir: tempfile.TemporaryDirectory[str] | None = None
        self._official_fun_kwargs: dict[str, Any] | None = None
        self._official_fun_prev_text = ""
        self._official_fun_device: str | None = None
        self.model: Any | None = None
        self.backend = self._backend_for_family()
        start = time.perf_counter()
        if self.backend == "whisper-cpp-coreml":
            self._start_whisper_server()
        elif self.backend == "funasr-torch":
            self._load_official_fun_model()
        else:
            self._load_mlx_audio_model()
        self.load_ms = int((time.perf_counter() - start) * 1000)

    def _backend_for_family(self) -> str:
        if self.family == "qwen3ASRSherpaOnnx":
            raise RuntimeError("sherpa-onnx Qwen3-ASR backend has been removed; use the MLX Qwen3-ASR backend on Apple Silicon.")
        if self.family == "whisperCppCoreML":
            return "whisper-cpp-coreml"
        if self.family == "funASRNano" and (self.model_path / "model.pt").is_file() and (self.model_path / "config.yaml").is_file():
            return "funasr-torch"
        return "mlx-audio"

    def _load_official_fun_model(self) -> None:
        with contextlib.redirect_stdout(sys.stderr):
            import torch
            from funasr.models.fun_asr_nano.model import FunASRNano

            requested_device = os.environ.get("LLMTOOLS_FUNASR_DEVICE", "").strip()
            if requested_device:
                device = requested_device
            elif torch.cuda.is_available():
                device = "cuda:0"
            elif torch.backends.mps.is_available():
                device = "mps"
            else:
                device = "cpu"
            self.model, self._official_fun_kwargs = FunASRNano.from_pretrained(
                model=str(self.model_path),
                device=device,
                disable_update=True,
            )
        self.model.eval()
        self._official_fun_device = device

    def _load_mlx_audio_model(self) -> None:
        self._loaded_model_path = self._model_path_for_loading(self.model_path)
        with contextlib.redirect_stdout(sys.stderr):
            from mlx_audio.stt.utils import load_model

            self.model = load_model(str(self._loaded_model_path))

    def _model_path_for_loading(self, model_path: Path) -> Path:
        model_type = read_model_type(model_path)
        if model_type != "funasr":
            return model_path
        self._tmpdir = tempfile.TemporaryDirectory(prefix="llmtools-funasr-model.")
        link = Path(self._tmpdir.name) / "funasr"
        os.symlink(model_path, link)
        return link

    def _start_whisper_server(self) -> None:
        model_bin = self._whisper_model_bin()
        coreml_dir = model_bin.with_name(f"{model_bin.stem}-encoder.mlmodelc")
        if not coreml_dir.is_dir():
            raise FileNotFoundError(f"Core ML encoder is missing: {coreml_dir}")
        root = Path(os.environ.get("LLMTOOLS_WHISPER_CPP_ROOT", str(Path.home() / "Library/Application Support/llmTools/asr-runtime/whisper-cpp"))).expanduser()
        server = self._whisper_server_path(root)
        if server is None:
            raise FileNotFoundError("whisper-server not found. Install whisper.cpp Core ML runtime or set LLMTOOLS_WHISPER_CPP_ROOT.")
        self._whisper_tmpdir = tempfile.TemporaryDirectory(prefix="llmtools-whisper-server.")
        public_dir = root / "whisper.cpp" / "examples" / "server" / "public"
        if not public_dir.is_dir():
            public_dir = Path(self._whisper_tmpdir.name)
        self._whisper_port = self._reserve_local_port()
        threads = str(max(1, int(os.environ.get("LLMTOOLS_WHISPER_CPP_THREADS", "4") or "4")))
        command = [
            str(server),
            "-m",
            str(model_bin),
            "--host",
            "127.0.0.1",
            "--port",
            str(self._whisper_port),
            "--public",
            str(public_dir),
            "--tmp-dir",
            self._whisper_tmpdir.name,
            "-t",
            threads,
        ]
        env = os.environ.copy()
        env["TOKENIZERS_PARALLELISM"] = "false"
        log(f"Starting whisper.cpp Core ML server on 127.0.0.1:{self._whisper_port}")
        self._whisper_process = subprocess.Popen(
            command,
            stdout=sys.stderr,
            stderr=sys.stderr,
            stdin=subprocess.DEVNULL,
            text=True,
            env=env,
        )
        self._wait_for_whisper_server()

    def _whisper_model_bin(self) -> Path:
        if self.model_path.is_file():
            if self.model_path.name.startswith("ggml-") and self.model_path.suffix == ".bin":
                return self.model_path
            raise FileNotFoundError(f"No whisper.cpp ggml model file found at: {self.model_path}")
        candidates = sorted(self.model_path.glob("ggml-*.bin"))
        if not candidates:
            raise FileNotFoundError(f"No whisper.cpp ggml model file found in: {self.model_path}")
        return candidates[0]

    def _whisper_server_path(self, root: Path) -> Path | None:
        candidates = [
            Path(os.environ["LLMTOOLS_WHISPER_CPP_SERVER"]) if os.environ.get("LLMTOOLS_WHISPER_CPP_SERVER") else None,
            root / "whisper.cpp" / "build" / "bin" / "whisper-server",
            root / "bin" / "whisper-server",
            Path(shutil.which("whisper-server") or ""),
        ]
        for candidate in candidates:
            if candidate and candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate
        return None

    def _reserve_local_port(self) -> int:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            return int(sock.getsockname()[1])

    def _wait_for_whisper_server(self) -> None:
        assert self._whisper_port is not None
        deadline = time.monotonic() + float(os.environ.get("LLMTOOLS_WHISPER_CPP_SERVER_TIMEOUT", "45") or "45")
        last_error = ""
        while time.monotonic() < deadline:
            if self._whisper_process is not None and self._whisper_process.poll() is not None:
                raise RuntimeError(f"whisper-server exited with code {self._whisper_process.returncode}")
            try:
                connection = http.client.HTTPConnection("127.0.0.1", self._whisper_port, timeout=1.0)
                connection.request("GET", "/")
                response = connection.getresponse()
                response.read()
                connection.close()
                if 200 <= response.status < 500:
                    return
            except Exception as error:
                last_error = str(error)
            time.sleep(0.2)
        raise TimeoutError(f"whisper-server did not become ready: {last_error}")

    def close(self) -> None:
        if self._whisper_process is not None:
            if self._whisper_process.poll() is None:
                self._whisper_process.terminate()
                try:
                    self._whisper_process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self._whisper_process.kill()
            self._whisper_process = None
        if self._whisper_tmpdir is not None:
            self._whisper_tmpdir.cleanup()
            self._whisper_tmpdir = None
        if self._tmpdir is not None:
            self._tmpdir.cleanup()
            self._tmpdir = None

    def run(self) -> None:
        emit(
            {
                    "type": "ready",
                    "family": self.family,
                    "backend": self.backend,
                    "device": self._official_fun_device,
                    "model": str(self.model_path),
                    "loadMilliseconds": self.load_ms,
                }
            )
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
                command = request.get("command")
                if command == "stop":
                    emit({"type": "stopped", "requestID": request.get("requestID")})
                    return
                if command != "transcribe":
                    emit(
                        {
                            "type": "error",
                            "requestID": request.get("requestID"),
                            "message": f"Unsupported command: {command}",
                        }
                    )
                    continue
                self.handle_transcribe(request)
            except Exception as error:
                emit({"type": "error", "message": str(error)})

    def handle_transcribe(self, request: dict[str, Any]) -> None:
        request_id = request.get("requestID")
        start = time.perf_counter()
        encoded_pcm16 = str(request.get("pcm16Base64") or "")
        raw_pcm16 = pcm16_bytes(encoded_pcm16)
        audio = pcm16_data_to_float32(raw_pcm16)
        sample_rate = int(request.get("sampleRate") or 16000)
        duration = float(len(audio)) / float(sample_rate or 16000)
        is_final = bool(request.get("isFinal", True))
        language = request.get("language") or self.default_language

        if len(audio) == 0:
            emit(
                {
                    "type": "result",
                    "requestID": request_id,
                    "segments": [],
                    "elapsedMilliseconds": int((time.perf_counter() - start) * 1000),
                }
            )
            return

        with contextlib.redirect_stdout(sys.stderr):
            text, detected_language = self.decode(audio, language, is_final, sample_rate, raw_pcm16)

        text = clean_text(text)
        segments = []
        if text:
            segments.append(
                {
                    "index": 0,
                    "start": 0.0,
                    "end": duration,
                    "text": text,
                    "language": detected_language,
                    "isFinal": is_final,
                }
            )

        emit(
            {
                "type": "result",
                "requestID": request_id,
                "segments": segments,
                "text": text,
                "language": detected_language,
                "elapsedMilliseconds": int((time.perf_counter() - start) * 1000),
                "mode": "streaming-window",
            }
        )

    def decode(
        self,
        audio: np.ndarray,
        language: str | None,
        is_final: bool,
        sample_rate: int,
        raw_pcm16: bytes,
    ) -> tuple[str, str | None]:
        if self.family == "whisperCppCoreML":
            return self.decode_whisper_cpp_coreml(raw_pcm16, language, sample_rate)
        if self.family == "qwen3ASR06B":
            return self.decode_qwen(audio, language)
        if self.backend == "funasr-torch":
            return self.decode_official_fun(audio, language, is_final)
        if self.family in {"funASRMLTNano", "funASRNano"}:
            return self.decode_fun(audio, language)
        if self.family == "senseVoiceSmall":
            return self.decode_sensevoice(audio, language)
        return self.decode_generic(audio, language, is_final)

    def decode_whisper_cpp_coreml(
        self,
        raw_pcm16: bytes,
        language: str | None,
        sample_rate: int,
    ) -> tuple[str, str | None]:
        if self._whisper_port is None:
            raise RuntimeError("whisper.cpp Core ML server is not running.")
        if not raw_pcm16:
            return "", None
        assert self._whisper_tmpdir is not None
        wav_path = Path(self._whisper_tmpdir.name) / f"window-{uuid.uuid4().hex}.wav"
        write_pcm16_wav(wav_path, raw_pcm16, sample_rate)
        try:
            payload = self._post_whisper_inference(wav_path, whisper_language(language))
        finally:
            try:
                wav_path.unlink()
            except FileNotFoundError:
                pass
        text = self._text_from_whisper_payload(payload)
        detected_language = None if whisper_language(language) == "auto" else whisper_language(language)
        return text, detected_language

    def _post_whisper_inference(self, wav_path: Path, language: str) -> dict[str, Any]:
        assert self._whisper_port is not None
        boundary = f"----llmtools-{uuid.uuid4().hex}"
        fields = [
            ("response_format", "verbose_json"),
            ("language", language),
        ]
        body = bytearray()
        for name, value in fields:
            body.extend(f"--{boundary}\r\n".encode("utf-8"))
            body.extend(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
            body.extend(str(value).encode("utf-8"))
            body.extend(b"\r\n")
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(
            (
                f'Content-Disposition: form-data; name="file"; filename="{wav_path.name}"\r\n'
                "Content-Type: audio/wav\r\n\r\n"
            ).encode("utf-8")
        )
        body.extend(wav_path.read_bytes())
        body.extend(b"\r\n")
        body.extend(f"--{boundary}--\r\n".encode("utf-8"))
        request = urllib.request.Request(
            f"http://127.0.0.1:{self._whisper_port}/inference",
            data=bytes(body),
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=float(os.environ.get("LLMTOOLS_WHISPER_CPP_INFERENCE_TIMEOUT", "120") or "120")) as response:
                response_body = response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as error:
            response_body = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"whisper-server inference failed with HTTP {error.code}: {response_body}") from error
        try:
            parsed = json.loads(response_body)
        except json.JSONDecodeError:
            return {"text": response_body}
        if isinstance(parsed, dict):
            return parsed
        return {"text": str(parsed)}

    def _text_from_whisper_payload(self, payload: dict[str, Any]) -> str:
        text = str(payload.get("text", "") or "").strip()
        if text:
            return text
        transcription = payload.get("transcription")
        if isinstance(transcription, list):
            pieces = [str(item.get("text", "") or "").strip() for item in transcription if isinstance(item, dict)]
            text = " ".join(piece for piece in pieces if piece).strip()
            if text:
                return text
        segments = payload.get("segments")
        if isinstance(segments, list):
            pieces = [str(item.get("text", "") or "").strip() for item in segments if isinstance(item, dict)]
            text = " ".join(piece for piece in pieces if piece).strip()
            if text:
                return text
        return ""

    def decode_qwen(self, audio: np.ndarray, language: str | None) -> tuple[str, str | None]:
        from mlx_lm.sample_utils import make_sampler

        qwen_lang = qwen_language(language)
        sampler = make_sampler(0.0, 1.0, 0.0, min_tokens_to_keep=1, top_k=0)
        token_ids: list[int] = []
        for token, _ in self.model.stream_generate(
            audio,
            max_tokens=self.max_tokens,
            sampler=sampler,
            logits_processors=None,
            language=qwen_lang,
            prefill_step_size=2048,
            verbose=False,
        ):
            token_ids.append(int(token))
        text = self.model._tokenizer.decode(token_ids, skip_special_tokens=True)
        detected_language = qwen_lang
        if qwen_lang is None and hasattr(self.model, "extract_language"):
            detected_language, text = self.model.extract_language(text)
        return text, detected_language

    def decode_fun(self, audio: np.ndarray, language: str | None) -> tuple[str, str | None]:
        lang = fun_language(language, self.family)
        if self.family == "funASRMLTNano":
            pieces: list[str] = []
            stream = self.model.generate(
                audio,
                max_tokens=self.max_tokens,
                language=lang or "auto",
                stream=True,
                verbose=False,
            )
            for chunk in stream:
                if chunk:
                    pieces.append(str(chunk))
            text = "".join(pieces)
            if hasattr(self.model, "_clean_output"):
                text = self.model._clean_output(text)
            return text, lang or "auto"

        from mlx_lm.sample_utils import make_logits_processors, make_sampler

        sampler = make_sampler(0.0, 1.0, 0.0, min_tokens_to_keep=1, top_k=0)
        logits_processors = make_logits_processors()
        token_ids: list[int] = []
        for token, _ in self.model.stream_generate(
            audio,
            max_tokens=self.max_tokens,
            sampler=sampler,
            logits_processors=logits_processors,
            language=lang,
            itn=True,
        ):
            token_ids.append(int(token))
        text = self.model._tokenizer.decode(token_ids, skip_special_tokens=True)
        return text, lang or "auto"

    def decode_official_fun(
        self,
        audio: np.ndarray,
        language: str | None,
        is_final: bool,
    ) -> tuple[str, str | None]:
        import torch

        assert self._official_fun_kwargs is not None
        kwargs = dict(self._official_fun_kwargs)
        kwargs.update(
            prev_text=self._official_fun_prev_text,
            language=official_fun_language(language),
            max_length=self.max_tokens,
        )
        result = self.model.inference(
            [torch.from_numpy(np.ascontiguousarray(audio))],
            **kwargs,
        )[0][0]
        text = str(result.get("text", "") or "")
        if is_final:
            self._official_fun_prev_text = ""
        else:
            # 官方 demo2 会回滚末尾 5 个 token，下一轮用累积音频重新确认不稳定尾部。
            tokenizer = kwargs["tokenizer"]
            token_ids = tokenizer.encode(text)
            stable_ids = token_ids[:-5] if len(token_ids) > 5 else []
            self._official_fun_prev_text = tokenizer.decode(stable_ids).replace("�", "")
        detected_language = language_code(language)
        return text, None if detected_language == "auto" else detected_language

    def decode_sensevoice(
        self,
        audio: np.ndarray,
        language: str | None,
    ) -> tuple[str, str | None]:
        result = self.model.generate(
            audio,
            language=language_code(language),
            use_itn=False,
            verbose=False,
        )
        return str(getattr(result, "text", "") or ""), getattr(result, "language", None)

    def decode_generic(
        self,
        audio: np.ndarray,
        language: str | None,
        is_final: bool,
    ) -> tuple[str, str | None]:
        signature = getattr(self.model.generate, "__call__", self.model.generate)
        kwargs: dict[str, Any] = {"verbose": False}
        del signature
        if language:
            kwargs["language"] = language_code(language)
        if "stream" in getattr(self.model.generate, "__annotations__", {}):
            kwargs["stream"] = not is_final
        result = self.model.generate(audio, **kwargs)
        return str(getattr(result, "text", "") or ""), getattr(result, "language", None)


def main() -> int:
    signal.signal(signal.SIGTERM, terminate_from_signal)
    signal.signal(signal.SIGINT, terminate_from_signal)
    args = parse_args()
    sidecar: StreamingASRSidecar | None = None
    try:
        sidecar = StreamingASRSidecar(args)
        sidecar.run()
        return 0
    except Exception as error:
        emit({"type": "error", "message": str(error)})
        return 1
    finally:
        if sidecar is not None:
            sidecar.close()


if __name__ == "__main__":
    raise SystemExit(main())
