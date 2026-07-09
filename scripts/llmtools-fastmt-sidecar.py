#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import sys
import time

PROTOCOL = "llmtools.fastmt/v1"
BCP47_TO_ARGOS = {
    "zh-Hans": "zh",
    "zh-Hant": "zt",
}
ARGOS_TO_BCP47 = {
    "zh": "zh-Hans",
    "zt": "zh-Hant",
}
BCP47_TO_NLLB = {
    "zh-Hans": "zho_Hans",
    "zh-Hant": "zho_Hant",
    "yue": "yue_Hant",
    "en": "eng_Latn",
    "ja": "jpn_Jpan",
    "ko": "kor_Hang",
    "vi": "vie_Latn",
    "id": "ind_Latn",
    "ms": "zsm_Latn",
    "fil": "tgl_Latn",
    "ar": "arb_Arab",
    "hi": "hin_Deva",
    "de": "deu_Latn",
    "fr": "fra_Latn",
    "es": "spa_Latn",
    "pt": "por_Latn",
    "it": "ita_Latn",
    "ru": "rus_Cyrl",
    "th": "tha_Thai",
}
NLLB_TO_BCP47 = {value: key for key, value in BCP47_TO_NLLB.items()}


def emit(payload):
    payload.setdefault("protocol", PROTOCOL)
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def bcp47_code(code):
    normalized = (code or "").strip()
    if not normalized:
        return ""
    return ARGOS_TO_BCP47.get(normalized, normalized)


def argos_code(code):
    normalized = (code or "").strip()
    if not normalized:
        return ""
    return BCP47_TO_ARGOS.get(normalized, normalized)


def nllb_code(code):
    normalized = (code or "").strip()
    if not normalized:
        return ""
    return BCP47_TO_NLLB.get(normalized, normalized if normalized in NLLB_TO_BCP47 else "")


def normalize_pair(source, target):
    source_code = NLLB_TO_BCP47.get(source, bcp47_code(source) or "en")
    target_code = NLLB_TO_BCP47.get(target, bcp47_code(target) or "zh-Hans")
    return {"source": source_code, "target": target_code}


class Translator:
    def __init__(self, args):
        self.args = args
        self.engine = args.engine
        self.model = args.model or ("argos-installed" if args.engine == "argos" else "opus-mt-en-zh")
        self.model_type = args.model_type
        self.available = False
        self.error = None
        self._translator = None
        self._source_sp = None
        self._target_sp = None
        self._argos_translate = None
        self._tokenizer_cls = None
        self._nllb_tokenizers = {}
        self._load()

    def _load(self):
        if self.engine == "ctranslate2":
            if not self.args.model:
                self.error = "CTranslate2 model path is required."
                return
            model_path = Path(self.args.model).expanduser()
            if not model_path.is_dir():
                self.error = f"CTranslate2 model directory was not found: {model_path}"
                return
            if not (model_path / "model.bin").is_file():
                self.error = f"CTranslate2 model.bin was not found in: {model_path}"
                return
            try:
                import ctranslate2
            except Exception as exc:
                self.error = f"CTranslate2 runtime missing: {exc}"
                return
            self.model_type = self._resolved_ctranslate2_model_type(model_path)
            try:
                if self.model_type == "nllb":
                    from transformers import AutoTokenizer
                    self._tokenizer_cls = AutoTokenizer
                else:
                    import sentencepiece
                    spm_paths = self._sentencepiece_paths(model_path)
                    if spm_paths is None:
                        self.error = f"SentencePiece model files were not found in: {model_path}"
                        return
                    source_spm, target_spm = spm_paths
                    self._source_sp = sentencepiece.SentencePieceProcessor(model_file=str(source_spm))
                    self._target_sp = sentencepiece.SentencePieceProcessor(model_file=str(target_spm))
                self._translator = self._load_ct2_translator(ctranslate2, model_path)
            except Exception as exc:
                self.error = f"CTranslate2 model load failed: {exc}"
                return
            self.available = True
            return
        if self.engine == "argos":
            try:
                import argostranslate.translate as argos_translate
            except Exception as exc:
                self.error = f"Argos Translate runtime missing: {exc}"
                return
            self._argos_translate = argos_translate
            self.available = True
            return
        self.error = f"Unsupported engine: {self.engine}"

    def _load_ct2_translator(self, ctranslate2, model_path):
        cpu_count = os.cpu_count() or 1
        inter_threads = max(1, min(4, cpu_count))
        try:
            return ctranslate2.Translator(
                str(model_path),
                device="auto",
                inter_threads=inter_threads,
            )
        except Exception:
            return ctranslate2.Translator(
                str(model_path),
                device="cpu",
                inter_threads=inter_threads,
            )

    def _resolved_ctranslate2_model_type(self, model_path):
        requested = (self.model_type or "auto").strip()
        if requested != "auto":
            return requested
        if (model_path / "sentencepiece.bpe.model").is_file():
            return "nllb"
        return "opus-mt"

    def _sentencepiece_paths(self, model_path):
        source_spm = model_path / "source.spm"
        target_spm = model_path / "target.spm"
        if source_spm.is_file() and target_spm.is_file():
            return source_spm, target_spm

        for shared_name in ("sentencepiece.model", "spm.model", "tokenizer.model"):
            shared = model_path / shared_name
            if shared.is_file():
                return shared, shared

        spm_files = sorted(model_path.glob("*.spm"))
        if len(spm_files) == 1:
            return spm_files[0], spm_files[0]
        if len(spm_files) >= 2:
            source = next((item for item in spm_files if "source" in item.name.lower()), spm_files[0])
            target = next((item for item in spm_files if "target" in item.name.lower()), spm_files[1])
            return source, target
        return None

    @property
    def supported_pairs(self):
        if self.engine == "ctranslate2":
            if self.model_type == "nllb":
                languages = list(BCP47_TO_NLLB.keys())
                return [
                    {"source": source, "target": target}
                    for source in languages
                    for target in languages
                    if source != target
                ]
            return [normalize_pair("en", "zh-Hans")]
        if self.engine == "argos" and self._argos_translate:
            pairs = []
            try:
                installed = self._argos_translate.get_installed_languages()
                for source in installed:
                    for target in installed:
                        if source.code != target.code and source.get_translation(target) is not None:
                            pairs.append(normalize_pair(source.code, target.code))
            except Exception:
                return []
            return pairs
        return []

    def supports_pair(self, source_language, target_language):
        pair = normalize_pair(source_language, target_language)
        return pair in self.supported_pairs

    def translate(self, source_language, target_language, segments):
        if not self.available:
            raise RuntimeError(self.error or "Fast translation runtime is unavailable.")
        if not self.supports_pair(source_language, target_language):
            raise ValueError(f"Unsupported language pair: {source_language}->{target_language}")
        if self.engine == "ctranslate2":
            if self.model_type == "nllb":
                return self._translate_nllb(source_language, target_language, segments)
            return self._translate_ctranslate2(segments)
        if self.engine == "argos":
            source_code = argos_code(source_language)
            target_code = argos_code(target_language)
            return [
                {
                    "id": item.get("id", ""),
                    "translation": self._argos_translate.translate(
                        item.get("text", ""),
                        source_code,
                        target_code,
                    ),
                }
                for item in segments
            ]
        raise RuntimeError(self.error or "Fast translation runtime is unavailable.")

    def _translate_ctranslate2(self, segments):
        texts = [item.get("text", "") for item in segments]
        token_batches = [
            self._source_sp.encode(text, out_type=str) + ["</s>"]
            for text in texts
        ]
        results = self._translator.translate_batch(
            token_batches,
            beam_size=1,
            max_batch_size=max(1, min(32, len(token_batches) or 1)),
        )
        translated = []
        for item, result in zip(segments, results):
            hypothesis = result.hypotheses[0] if result.hypotheses else []
            cleaned = [
                token for token in hypothesis
                if token not in {"</s>", "<s>", "<pad>", "<unk>"} and not token.startswith(">>")
            ]
            translated.append({
                "id": item.get("id", ""),
                "translation": self._target_sp.decode(cleaned).strip(),
            })
        return translated

    def _nllb_tokenizer(self, source_code):
        tokenizer = self._nllb_tokenizers.get(source_code)
        if tokenizer is None:
            tokenizer = self._tokenizer_cls.from_pretrained(
                str(Path(self.args.model).expanduser()),
                local_files_only=True,
                src_lang=source_code,
                use_fast=False,
            )
            self._nllb_tokenizers[source_code] = tokenizer
        return tokenizer

    def _translate_nllb(self, source_language, target_language, segments):
        source_code = nllb_code(source_language)
        target_code = nllb_code(target_language)
        if not source_code or not target_code:
            raise ValueError(f"Unsupported NLLB language pair: {source_language}->{target_language}")
        tokenizer = self._nllb_tokenizer(source_code)
        token_batches = [
            tokenizer.convert_ids_to_tokens(tokenizer.encode(item.get("text", "")))
            for item in segments
        ]
        results = self._translator.translate_batch(
            token_batches,
            target_prefix=[[target_code] for _ in token_batches],
            beam_size=1,
            max_batch_size=max(1, min(16, len(token_batches) or 1)),
            max_decoding_length=128,
        )
        translated = []
        for item, result in zip(segments, results):
            hypothesis = result.hypotheses[0] if result.hypotheses else []
            cleaned = [
                token for token in hypothesis
                if token not in {"</s>", "<s>", "<pad>", "<unk>"}
            ]
            if cleaned and cleaned[0] == target_code:
                cleaned = cleaned[1:]
            token_ids = tokenizer.convert_tokens_to_ids(cleaned)
            translated.append({
                "id": item.get("id", ""),
                "translation": tokenizer.decode(token_ids, skip_special_tokens=True).strip(),
            })
        return translated


def main():
    parser = argparse.ArgumentParser(description="llmTools fast MT sidecar")
    parser.add_argument("--engine", choices=["ctranslate2", "argos"], default="ctranslate2")
    parser.add_argument("--model", default="")
    parser.add_argument("--model-type", choices=["auto", "opus-mt", "nllb"], default="auto")
    parser.add_argument("--source", default="en")
    parser.add_argument("--target", default="zh-Hans")
    args = parser.parse_args()

    translator = Translator(args)
    supported_pairs = translator.supported_pairs
    if not translator.available:
        emit({
            "type": "error",
            "engine": args.engine,
            "model": translator.model,
            "code": "runtimeUnavailable",
            "message": translator.error or "Fast translation runtime is unavailable.",
        })
        return
    if not supported_pairs:
        emit({
            "type": "error",
            "engine": args.engine,
            "model": translator.model,
            "code": "unsupportedLanguagePair",
            "message": "Fast translation runtime is installed, but no language package supports the requested translation pair.",
        })
        return
    emit({
        "type": "ready",
        "engine": args.engine,
        "model": translator.model,
        "available": True,
        "supportedPairs": supported_pairs,
        "message": translator.error,
    })

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except Exception as exc:
            emit({"type": "error", "code": "invalidJSON", "message": str(exc)})
            continue
        request_id = request.get("requestID")
        command = request.get("command")
        if command in {"stop", "cancel"}:
            if command == "stop":
                return
            emit({"type": "cancelled", "requestID": request_id})
            continue
        if command != "translate":
            emit({"type": "error", "requestID": request_id, "code": "unknownCommand", "message": f"Unknown command: {command}"})
            continue
        source_language = request.get("sourceLanguage") or args.source
        target_language = request.get("targetLanguage") or args.target
        segments = request.get("segments") or []
        started = time.monotonic()
        try:
            translated = translator.translate(source_language, target_language, segments)
            emit({
                "type": "translation",
                "requestID": request_id,
                "engine": args.engine,
                "model": translator.model,
                "segments": translated,
                "latencyMilliseconds": int((time.monotonic() - started) * 1000),
            })
        except Exception as exc:
            code = "unsupportedLanguagePair" if isinstance(exc, ValueError) else "runtimeUnavailable"
            emit({
                "type": "error",
                "requestID": request_id,
                "code": code,
                "message": str(exc),
            })


if __name__ == "__main__":
    main()
