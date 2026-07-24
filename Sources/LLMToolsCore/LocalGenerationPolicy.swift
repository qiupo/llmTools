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

    public static func maxTokens(for task: TaskKind, thinkingModeEnabled: Bool) -> Int {
        // 思考 token 与正文共享上限；开启时扩容，避免在正文生成前被截断。
        maxTokens(for: task) * (thinkingModeEnabled ? 2 : 1)
    }

    public static func maxTokens(for mode: OCRMode) -> Int {
        switch mode {
        case .plainText, .structured, .extractThenTranslate:
            return 1536
        case .explainImage:
            return 512
        }
    }

    static func parameters(for task: TaskKind, thinkingModeEnabled: Bool = false) -> GenerateParameters {
        if task == .ocr {
            return parameters(for: .structured, thinkingModeEnabled: thinkingModeEnabled)
        }
        let maxTokens = maxTokens(for: task, thinkingModeEnabled: thinkingModeEnabled)
        return GenerateParameters(maxTokens: maxTokens, temperature: 0)
    }

    static func parameters(for mode: OCRMode, thinkingModeEnabled: Bool = false) -> GenerateParameters {
        let maxTokens = maxTokens(for: mode) * (thinkingModeEnabled ? 2 : 1)
        return GenerateParameters(maxTokens: maxTokens, temperature: 0)
    }
}
