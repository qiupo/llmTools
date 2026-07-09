import Foundation

public enum LanguageCodeNormalizer {
    public static func normalizedBCP47(_ rawCode: String?) -> String? {
        guard var code = rawCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
            return nil
        }
        if code.hasPrefix("__label__") {
            code.removeFirst("__label__".count)
        }
        let normalizedKey = code
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if ["auto", "unknown", "und", "none", "null"].contains(normalizedKey) {
            return nil
        }
        if let mapped = aliasToBCP47[normalizedKey] {
            return mapped
        }

        let parts = normalizedKey.split(separator: "-").map(String.init)
        guard let language = parts.first, language.count == 2 else {
            return nil
        }
        if language == "zh" {
            if parts.contains("hant") || parts.contains("tw") || parts.contains("hk") || parts.contains("mo") {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        return language
    }

    public static func normalizedPair(source: String?, target: String?) -> LanguagePair? {
        guard
            let source = normalizedBCP47(source),
            let target = normalizedBCP47(target)
        else {
            return nil
        }
        return LanguagePair(source: source, target: target)
    }

    public static func code(_ rawCode: String?, for engineID: TranslationEngineID) -> String? {
        guard let normalized = normalizedBCP47(rawCode) else {
            return nil
        }
        switch engineID {
        case .llm, .customCommand:
            return normalized
        case .ctranslate2:
            return nllbCode(for: normalized)
        case .argos:
            return argosCode(for: normalized)
        }
    }

    public static func fastTextCode(for rawCode: String?) -> String? {
        guard let normalized = normalizedBCP47(rawCode) else {
            return nil
        }
        return bcp47ToFastText[normalized] ?? normalized
    }

    public static func nllbCode(for rawCode: String?) -> String? {
        guard let normalized = normalizedBCP47(rawCode) else {
            return nil
        }
        return bcp47ToNLLB[normalized]
    }

    public static func argosCode(for rawCode: String?) -> String? {
        guard let normalized = normalizedBCP47(rawCode) else {
            return nil
        }
        return bcp47ToArgos[normalized] ?? normalized
    }

    public static func asrHintCode(for rawCode: String?) -> String? {
        guard let normalized = normalizedBCP47(rawCode) else {
            return nil
        }
        return bcp47ToASRHint[normalized] ?? normalized
    }

    private static let aliasToBCP47: [String: String] = [
        "zh": "zh-Hans",
        "zh-cn": "zh-Hans",
        "zh-sg": "zh-Hans",
        "zh-hans": "zh-Hans",
        "zh-hans-cn": "zh-Hans",
        "cmn": "zh-Hans",
        "cmn-hans": "zh-Hans",
        "zho": "zh-Hans",
        "zho-hans": "zh-Hans",
        "zho-hans-cn": "zh-Hans",
        "zho-hans-sg": "zh-Hans",
        "chinese": "zh-Hans",
        "simplified-chinese": "zh-Hans",
        "simplified chinese": "zh-Hans",
        "zh-tw": "zh-Hant",
        "zh-hk": "zh-Hant",
        "zh-mo": "zh-Hant",
        "zh-hant": "zh-Hant",
        "cmn-hant": "zh-Hant",
        "zho-hant": "zh-Hant",
        "traditional-chinese": "zh-Hant",
        "traditional chinese": "zh-Hant",
        "yue": "yue",
        "yue-hant": "yue",
        "en": "en",
        "eng": "en",
        "eng-latn": "en",
        "english": "en",
        "ja": "ja",
        "jpn": "ja",
        "jpn-jpan": "ja",
        "japanese": "ja",
        "ko": "ko",
        "kor": "ko",
        "kor-hang": "ko",
        "korean": "ko",
        "vi": "vi",
        "vie": "vi",
        "vie-latn": "vi",
        "id": "id",
        "ind": "id",
        "ind-latn": "id",
        "ms": "ms",
        "msa": "ms",
        "msa-latn": "ms",
        "fil": "fil",
        "tl": "fil",
        "tgl": "fil",
        "tgl-latn": "fil",
        "ar": "ar",
        "ara": "ar",
        "ara-arab": "ar",
        "hi": "hi",
        "hin": "hi",
        "hin-deva": "hi",
        "de": "de",
        "deu": "de",
        "ger": "de",
        "deu-latn": "de",
        "fr": "fr",
        "fra": "fr",
        "fre": "fr",
        "fra-latn": "fr",
        "es": "es",
        "spa": "es",
        "spa-latn": "es",
        "pt": "pt",
        "por": "pt",
        "por-latn": "pt",
        "it": "it",
        "ita": "it",
        "ita-latn": "it",
        "ru": "ru",
        "rus": "ru",
        "rus-cyrl": "ru",
        "th": "th",
        "tha": "th",
        "tha-thai": "th"
    ]

    private static let bcp47ToFastText: [String: String] = [
        "zh-Hans": "zh",
        "zh-Hant": "zh",
        "yue": "zh",
        "en": "en",
        "ja": "ja",
        "ko": "ko",
        "vi": "vi",
        "id": "id",
        "ms": "ms",
        "fil": "tl",
        "ar": "ar",
        "hi": "hi",
        "de": "de",
        "fr": "fr",
        "es": "es",
        "pt": "pt",
        "it": "it",
        "ru": "ru",
        "th": "th"
    ]

    private static let bcp47ToNLLB: [String: String] = [
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
        "th": "tha_Thai"
    ]

    private static let bcp47ToArgos: [String: String] = [
        "zh-Hans": "zh",
        "zh-Hant": "zh",
        "yue": "zh",
        "en": "en",
        "ja": "ja",
        "ko": "ko",
        "vi": "vi",
        "id": "id",
        "ar": "ar",
        "hi": "hi",
        "de": "de",
        "fr": "fr",
        "es": "es",
        "pt": "pt",
        "it": "it",
        "ru": "ru"
    ]

    private static let bcp47ToASRHint: [String: String] = [
        "zh-Hans": "zh",
        "zh-Hant": "zh",
        "yue": "yue",
        "en": "en",
        "ja": "ja",
        "ko": "ko",
        "vi": "vi",
        "id": "id",
        "ms": "ms",
        "fil": "fil",
        "ar": "ar",
        "hi": "hi",
        "de": "de",
        "fr": "fr",
        "es": "es",
        "pt": "pt",
        "it": "it",
        "ru": "ru",
        "th": "th"
    ]
}

public enum Phase4XFixtureEnvironment {
    public static let languageIDJSON = "LLMTOOLS_LID_FIXTURE_JSON"
    public static let fastTranslationJSON = "LLMTOOLS_FAST_MT_FIXTURE_JSON"
    public static let diarizationJSON = "LLMTOOLS_DIARIZATION_FIXTURE_JSON"
}
