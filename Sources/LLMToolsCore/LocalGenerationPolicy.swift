import Foundation
import MLXLMCommon

public enum LocalGenerationPolicy {
    public static func maxTokens(for task: TaskKind) -> Int {
        switch task {
        case .translate, .polish:
            return 2048
        case .summarize, .explain:
            return 1536
        case .extractTodos:
            return 1024
        case .webPageTranslate:
            return 4096
        case .ocr:
            return maxTokens(for: OCRMode.structured)
        }
    }

    public static func maxTokens(for mode: OCRMode) -> Int {
        switch mode {
        case .plainText, .structured, .extractThenTranslate:
            return 1536
        case .explainImage:
            return 512
        }
    }

    static func parameters(for task: TaskKind) -> GenerateParameters {
        if task == .ocr {
            return parameters(for: .structured)
        }
        return GenerateParameters(maxTokens: maxTokens(for: task), temperature: 0)
    }

    static func parameters(for mode: OCRMode) -> GenerateParameters {
        GenerateParameters(maxTokens: maxTokens(for: mode), temperature: 0)
    }
}
