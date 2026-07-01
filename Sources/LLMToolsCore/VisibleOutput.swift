import Foundation

public enum VisibleOutput {
    public static func from(rawText: String) -> String {
        guard let end = rawText.range(of: "</think>", options: [.caseInsensitive]) else {
            return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(rawText[end.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
