import Foundation

public enum VisibleOutput {
    public static func from(rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = trimmed.range(of: "</think>", options: [.caseInsensitive]) {
            return String(trimmed[end.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lines = trimmed.components(separatedBy: .newlines)
        let firstLine = lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#*")))
            .lowercased()
        guard firstLine == "thinking process:" || firstLine?.hasPrefix("<think>") == true else {
            return trimmed
        }

        let finalMarkers = ["final answer:", "final response:", "answer:", "最终答案：", "最终答案:", "正文：", "正文:"]
        if let markerIndex = lines.lastIndex(where: { line in
            let normalized = line
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#*")))
                .lowercased()
            return finalMarkers.contains(normalized)
        }) {
            return lines.dropFirst(markerIndex + 1)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 没有明确正文边界时宁可视为空结果，也不能把思考过程显示给用户。
        return ""
    }
}
