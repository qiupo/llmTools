import Foundation
import MLXLMCommon

public enum LocalGenerationPolicy {
    public static let maximumThinkingTokens = 256
    public static let maximumStructuredOCRPostProcessingCharacters = 1_024

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

    public static func maxTokens(
        for task: TaskKind,
        thinkingModeEnabled: Bool,
        override: Int? = nil
    ) -> Int {
        let regularLimit = maxTokens(for: task)
        let requestedLimit = override.map { min(max(1, $0), regularLimit) } ?? regularLimit
        guard thinkingModeEnabled else { return requestedLimit }
        // 小模型可能把全部预算耗在隐藏思考里；限制首轮预算，未产出正文时由 runner 关闭思考重试。
        return min(requestedLimit, maximumThinkingTokens)
    }

    public static func shouldRetryThinkingGeneration(
        visibleOutput: String,
        reachedTokenLimit: Bool
    ) -> Bool {
        visibleOutput.isEmpty || reachedTokenLimit
    }

    public static func maxTokens(for mode: OCRMode) -> Int {
        switch mode {
        case .plainText, .structured, .extractThenTranslate:
            return 1536
        case .explainImage:
            return 512
        }
    }

    static func parameters(
        for task: TaskKind,
        thinkingModeEnabled: Bool = false,
        maxTokensOverride: Int? = nil
    ) -> GenerateParameters {
        if task == .ocr {
            return parameters(for: .structured, thinkingModeEnabled: thinkingModeEnabled)
        }
        let maxTokens = maxTokens(
            for: task,
            thinkingModeEnabled: thinkingModeEnabled,
            override: maxTokensOverride
        )
        return GenerateParameters(maxTokens: maxTokens, temperature: 0)
    }

    static func parameters(for mode: OCRMode, thinkingModeEnabled: Bool = false) -> GenerateParameters {
        let regularLimit = maxTokens(for: mode)
        let maxTokens = thinkingModeEnabled ? min(regularLimit, maximumThinkingTokens) : regularLimit
        return GenerateParameters(maxTokens: maxTokens, temperature: 0)
    }
}
