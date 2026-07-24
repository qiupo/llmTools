import Foundation

public enum TranslationOutputMode: String, Sendable, Hashable {
    case plain
    case detailed
}

public struct TranslationKeyTerm: Decodable, Sendable, Hashable {
    public var term: String
    public var pronunciation: String
    public var partOfSpeech: String
    public var meaning: String
    public var usage: String
    public var example: String
    public var exampleTranslation: String

    public init(
        term: String,
        pronunciation: String = "",
        partOfSpeech: String = "",
        meaning: String = "",
        usage: String = "",
        example: String = "",
        exampleTranslation: String = ""
    ) {
        self.term = term
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.usage = usage
        self.example = example
        self.exampleTranslation = exampleTranslation
    }

    private enum CodingKeys: String, CodingKey {
        case term
        case pronunciation
        case partOfSpeech
        case meaning
        case usage
        case example
        case exampleTranslation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decodeIfPresent(String.self, forKey: .term) ?? ""
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        usage = try container.decodeIfPresent(String.self, forKey: .usage) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation) ?? ""
    }
}

public struct TranslationStudyResult: Decodable, Sendable, Hashable {
    public var translation: String
    public var alternatives: [String]
    public var keyTerms: [TranslationKeyTerm]
    public var notes: [String]

    public init(
        translation: String,
        alternatives: [String] = [],
        keyTerms: [TranslationKeyTerm] = [],
        notes: [String] = []
    ) {
        self.translation = translation
        self.alternatives = alternatives
        self.keyTerms = keyTerms
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case translation
        case alternatives
        case keyTerms
        case importantWords
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        alternatives = try container.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        keyTerms = try container.decodeIfPresent([TranslationKeyTerm].self, forKey: .keyTerms)
            ?? container.decodeIfPresent([TranslationKeyTerm].self, forKey: .importantWords)
            ?? []
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    public static func parse(modelText: String) -> TranslationStudyResult? {
        let trimmed = VisibleOutput.from(rawText: modelText)
        guard !trimmed.isEmpty else { return nil }

        // 小模型偶尔会包一层 Markdown 围栏；只截取最外层 JSON 对象后交给 JSONDecoder。
        var candidates = [trimmed]
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            candidates.append(String(trimmed[firstBrace ... lastBrace]))
        }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  var result = try? JSONDecoder().decode(TranslationStudyResult.self, from: data)
            else { continue }

            result.translation = normalized(result.translation)
            guard !result.translation.isEmpty else { continue }
            result.alternatives = uniqueNonEmpty(result.alternatives)
                .filter { $0 != result.translation }
                .prefix(3)
                .map { $0 }
            result.keyTerms = result.keyTerms.compactMap(normalizedTerm).prefix(8).map { $0 }
            result.notes = uniqueNonEmpty(result.notes).prefix(4).map { $0 }
            return result
        }
        return nil
    }

    private static func normalizedTerm(_ value: TranslationKeyTerm) -> TranslationKeyTerm? {
        var term = value
        term.term = normalized(term.term)
        guard !term.term.isEmpty else { return nil }
        term.pronunciation = normalized(term.pronunciation)
        term.partOfSpeech = normalized(term.partOfSpeech)
        term.meaning = normalized(term.meaning)
        term.usage = normalized(term.usage)
        term.example = normalized(term.example)
        term.exampleTranslation = normalized(term.exampleTranslation)
        return term
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let value = normalized(value)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
