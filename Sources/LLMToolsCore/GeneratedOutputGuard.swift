import Foundation

public enum GeneratedOutputGuard {
    public static func trimDegenerateTail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cutIndex = degenerateTailCutIndex(in: trimmed) else {
            return trimmed
        }

        return trimTrailingSeparators(String(trimmed[..<cutIndex]))
    }

    public static func hasDegenerateTail(_ text: String) -> Bool {
        degenerateTailCutIndex(in: text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    static func collectGuardedResponse(from stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var response = ""
        for try await chunk in stream {
            response += chunk
        }
        return response
    }

    private static func degenerateTailCutIndex(in text: String) -> String.Index? {
        let tokens = lexicalTokens(in: text)
        guard tokens.count >= 8 else {
            return nil
        }

        var bestCutIndex: String.Index?
        let maximumUnitLength = min(12, tokens.count / 2)
        for unitLength in 1...maximumUnitLength {
            let repetitions = trailingRepetitionCount(tokens: tokens, unitLength: unitLength)
            guard repetitions >= minimumRepetitionCount(for: unitLength),
                  repetitions * unitLength >= 8 else {
                continue
            }

            let repeatedRunStart = tokens.count - repetitions * unitLength
            let secondUnitStart = repeatedRunStart + unitLength
            guard secondUnitStart < tokens.count else {
                continue
            }

            let lowerLimit = tokens[secondUnitStart - 1].range.upperBound
            let cutIndex = leadingBoundary(
                before: tokens[secondUnitStart].range.lowerBound,
                after: lowerLimit,
                in: text
            )
            if bestCutIndex == nil || cutIndex < bestCutIndex! {
                bestCutIndex = cutIndex
            }
        }

        return bestCutIndex
    }

    private static func trailingRepetitionCount(tokens: [LexicalToken], unitLength: Int) -> Int {
        guard unitLength > 0, tokens.count >= unitLength * 2 else {
            return 1
        }

        let suffixStart = tokens.count - unitLength
        var repetitions = 1
        var candidateStart = suffixStart - unitLength
        while candidateStart >= 0,
              tokenUnitsMatch(tokens: tokens, lhsStart: candidateStart, rhsStart: suffixStart, length: unitLength) {
            repetitions += 1
            candidateStart -= unitLength
        }
        return repetitions
    }

    private static func tokenUnitsMatch(
        tokens: [LexicalToken],
        lhsStart: Int,
        rhsStart: Int,
        length: Int
    ) -> Bool {
        for offset in 0..<length where tokens[lhsStart + offset].normalized != tokens[rhsStart + offset].normalized {
            return false
        }
        return true
    }

    private static func minimumRepetitionCount(for unitLength: Int) -> Int {
        switch unitLength {
        case 1:
            return 8
        case 2...3:
            return 5
        default:
            return 4
        }
    }

    private static func leadingBoundary(before index: String.Index, after lowerLimit: String.Index, in text: String) -> String.Index {
        var boundary = index
        while boundary > lowerLimit {
            let previous = text.index(before: boundary)
            guard previous > lowerLimit, isRepeatSeparator(text[previous]) else {
                break
            }
            boundary = previous
        }
        return boundary
    }

    private static func trimTrailingSeparators(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let scalar = result.unicodeScalars.last,
              trailingSeparators.contains(scalar) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static let trailingSeparators = CharacterSet(charactersIn: ",，、;；:：")
    private static let repeatSeparators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ",，、;；:："))
    private static let openingQuoteCharacters: Set<Character> = ["\"", "'", "`", "“", "‘", "「", "『", "（", "(", "["]

    private static func isRepeatSeparator(_ character: Character) -> Bool {
        openingQuoteCharacters.contains(character)
            || character.unicodeScalars.allSatisfy { repeatSeparators.contains($0) }
    }

    private static func lexicalTokens(in text: String) -> [LexicalToken] {
        var tokens: [LexicalToken] = []
        var currentStart: String.Index?
        var currentText = ""

        func flush(upTo end: String.Index) {
            guard let start = currentStart, !currentText.isEmpty else {
                currentStart = nil
                currentText = ""
                return
            }
            tokens.append(
                LexicalToken(
                    normalized: currentText.lowercased(),
                    range: start..<end
                )
            )
            currentStart = nil
            currentText = ""
        }

        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]

            if isCJK(character) {
                flush(upTo: index)
                tokens.append(
                    LexicalToken(
                        normalized: String(character),
                        range: index..<next
                    )
                )
            } else if isTokenCharacter(character) {
                if currentStart == nil {
                    currentStart = index
                }
                currentText.append(character)
            } else {
                flush(upTo: index)
            }

            index = next
        }
        flush(upTo: text.endIndex)
        return tokens
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x4E00...0x9FFF).contains(value)
                || (0x3400...0x4DBF).contains(value)
                || (0xF900...0xFAFF).contains(value)
        }
    }

    private struct LexicalToken {
        var normalized: String
        var range: Range<String.Index>
    }
}
