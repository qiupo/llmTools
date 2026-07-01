import Foundation

public enum PromptTemplates {
    public static func systemPrompt(for task: TaskKind, preferences: AppPreferences) -> String {
        switch task {
        case .translate:
            return "You are a translation engine. Preserve meaning, formatting, numbers, code, and names. Output only the translated text."
        case .webPageTranslate:
            return """
            You are a webpage translation engine. Translate English webpage text to Simplified Chinese.
            Preserve meaning, numbers, names, URLs, product names, code-like tokens, and UI intent.
            Return only valid JSON that follows the requested schema.
            Do not explain.
            """
        case .polish:
            return "You are a rewriting engine. Preserve meaning, facts, formatting, numbers, code, and names. Output only the rewritten text."
        case .summarize:
            return "You are a summarization engine. Output only the summary."
        case .explain:
            return "You are an explanation engine. Output only the explanation."
        case .extractTodos:
            return "You are a TODO extraction engine. Output only actionable TODO items."
        }
    }

    public static func retryPrompt(for request: TaskRequest, preferences: AppPreferences) -> String {
        switch request.task {
        case .translate:
            let target = request.targetLanguage ?? preferences.defaultTranslationTarget
            return translationPrompt(
                inputText: request.inputText,
                target: target,
                isRetry: true
            )
        case .webPageTranslate:
            return webPageTranslationPrompt(inputText: request.inputText, isRetry: true)
        case .polish:
            return polishPrompt(
                inputText: request.inputText,
                style: request.polishStyle ?? preferences.defaultPolishStyle,
                isRetry: true
            )
        case .summarize:
            return summarizePrompt(inputText: request.inputText, isRetry: true)
        case .explain:
            return explainPrompt(inputText: request.inputText, isRetry: true)
        case .extractTodos:
            return todosPrompt(inputText: request.inputText, isRetry: true)
        }
    }

    public static func userPrompt(for request: TaskRequest, preferences: AppPreferences) -> String {
        switch request.task {
        case .translate:
            let target = request.targetLanguage ?? preferences.defaultTranslationTarget
            return translationPrompt(
                inputText: request.inputText,
                target: target,
                isRetry: false
            )
        case .webPageTranslate:
            return webPageTranslationPrompt(inputText: request.inputText, isRetry: false)
        case .polish:
            return polishPrompt(
                inputText: request.inputText,
                style: request.polishStyle ?? preferences.defaultPolishStyle,
                isRetry: false
            )
        case .summarize:
            return summarizePrompt(inputText: request.inputText, isRetry: false)
        case .explain:
            return explainPrompt(inputText: request.inputText, isRetry: false)
        case .extractTodos:
            return todosPrompt(inputText: request.inputText, isRetry: false)
        }
    }

    private static func translationPrompt(inputText: String, target: String, isRetry: Bool) -> String {
        let targetLanguage = target == "auto"
            ? "English if the source text is mainly Chinese, otherwise Simplified Chinese"
            : targetLanguageName(for: target)

        if isRetry {
            return """
            Translate to \(targetLanguage). Output only the translation.
            \(inputText)
            """
        }

        return """
        Translate to \(targetLanguage). Output only the translation.
        \(inputText)
        """
    }

    public static func webPageBatchPrompt(
        segments: [WebPageTranslationSegment],
        targetLanguage: String,
        isRetry: Bool
    ) throws -> String {
        let items = segments.map { WebPagePromptItem(id: $0.segmentID, text: $0.text) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(items)
        let json = String(decoding: data, as: UTF8.self)
        let target = targetLanguageName(for: targetLanguage)
        let retryLine = isRetry
            ? "This is a retry. Return only the JSON array, with no Markdown fences and no prose."
            : "Return only the JSON array, with no Markdown fences and no prose."

        return """
        Translate each item to \(target).
        \(retryLine)
        Return a JSON array with objects in the same order:
        [{"id":"...","translation":"..."}]

        Rules:
        - Preserve links, numbers, product names, keyboard shortcuts, and code-like tokens.
        - For buttons and short UI labels, use concise Chinese.
        - For paragraphs, use natural Chinese.
        - Do not add commentary.

        Items:
        \(json)
        """
    }

    private static func webPageTranslationPrompt(inputText: String, isRetry: Bool) -> String {
        let retryLine = isRetry ? "Return only the translated text." : "Output only the translation."
        return """
        Translate this webpage text to Simplified Chinese. \(retryLine)
        \(inputText)
        """
    }

    private static func polishPrompt(inputText: String, style: String, isRetry: Bool) -> String {
        let retryLine = isRetry ? "这是重试，请严格只输出润色后的正文。" : "润色下面的文本。"
        return """
        你是一个文本润色函数。\(retryLine)
        风格：\(style)
        规则：
        - 只输出润色后的正文。
        - 保留原意、事实、数字、代码、格式和专有名词。

        原文：
        \(inputText)

        润色结果：
        """
    }

    private static func summarizePrompt(inputText: String, isRetry: Bool) -> String {
        let retryLine = isRetry ? "这是重试，请严格只输出总结。" : "总结下面的文本。"
        return """
        你是一个总结函数。\(retryLine)
        规则：
        - 只输出总结正文。
        - 用简洁中文输出关键点；如有行动项，合并进总结。

        原文：
        \(inputText)

        总结：
        """
    }

    private static func explainPrompt(inputText: String, isRetry: Bool) -> String {
        let retryLine = isRetry ? "这是重试，请严格只输出解释。" : "解释下面的文本。"
        return """
        你是一个解释函数。\(retryLine)
        规则：
        - 只输出解释正文。
        - 用通俗中文解释含义和关键影响。

        原文：
        \(inputText)

        解释：
        """
    }

    private static func todosPrompt(inputText: String, isRetry: Bool) -> String {
        let retryLine = isRetry ? "这是重试，请严格只输出待办列表。" : "从下面文本中提取待办。"
        return """
        你是一个待办提取函数。\(retryLine)
        规则：
        - 只输出待办列表。
        - 每条用 "- " 开头。
        - 包含任务、负责人、截止日期、优先级；没有的信息不要编造。
        - 如果没有待办，输出“无明确待办”。

        原文：
        \(inputText)

        待办：
        """
    }

    public static func targetLanguageName(for target: String) -> String {
        switch target {
        case "zh-Hans": return "Simplified Chinese"
        case "en": return "English"
        case "Chinese": return "Simplified Chinese"
        case "English": return "English"
        case "Japanese": return "Japanese"
        case "Korean": return "Korean"
        default: return target
        }
    }

    private struct WebPagePromptItem: Encodable {
        var id: String
        var text: String
    }
}
