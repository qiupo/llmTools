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
        case .ocr:
            return "You are an OCR and image-understanding engine. Follow the user's image task exactly. Output only the requested result."
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
        case .ocr:
            return request.inputText
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
        case .ocr:
            return request.inputText
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
        qualityMode: WebPageTranslationQualityMode = .natural,
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
        \(webPageQualityInstruction(qualityMode))
        - Do not add commentary.

        Items:
        \(json)
        """
    }

    private static func webPageQualityInstruction(_ mode: WebPageTranslationQualityMode) -> String {
        switch mode {
        case .natural:
            return "- Prefer fluent, natural Simplified Chinese while preserving the source meaning."
        case .literal:
            return "- Prefer a more literal translation; preserve source sentence structure and terminology when it remains readable."
        case .technical:
            return "- Preserve technical terminology, API names, product names, code-like tokens, and UI labels; use standard technical Chinese where appropriate."
        }
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
        风格：\(polishStyleInstruction(style))
        规则：
        - 只输出润色后的正文。
        - 保留原意、事实、数字、代码、格式和专有名词。
        - 不新增原文没有的信息，不改变说话人的立场。

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
        - 用简洁中文输出 3-6 条关键点。
        - 如果原文包含行动项，单独用“行动项：”列出；不要把行动项混进普通摘要。
        - 不编造原文没有的结论、日期、负责人或优先级。

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
        - 用通俗中文解释含义、背景、关键影响和用户应该注意的点。
        - 如果输入像术语、错误、日志、代码片段或密集段落，先说明它是什么，再解释为什么重要。
        - 不编造外部上下文；不确定的地方明确说不确定。

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
        - 每条尽量包含任务、负责人、截止日期、优先级；没有的信息不要编造。
        - 只提取可以执行的事项，不把背景信息或愿望改写成待办。
        - 如果没有待办，输出“无明确待办”。

        原文：
        \(inputText)

        待办：
        """
    }

    private static func polishStyleInstruction(_ style: String) -> String {
        switch style {
        case "formal":
            return "正式、清晰、适合商务或公告语境"
        case "concise":
            return "简洁，删掉冗余表达但保留必要信息"
        case "conversational":
            return "自然口语化，读起来像真实对话"
        case "technical":
            return "技术写作风格，保留术语、接口名、代码符号和准确性"
        default:
            return "自然流畅，保持原文语气"
        }
    }

    public static func ocrPrompt(mode: OCRMode, targetLanguage: String = "zh-Hans") -> String {
        switch mode {
        case .plainText:
            return """
            Extract visible text from the image.
            Rules:
            - Output only text that is visible in the image.
            - Preserve original languages, line breaks, numbers, punctuation, labels, and reading order.
            - Do not describe the image.
            - Do not infer hidden text or missing words.
            - If no readable text is visible, output exactly: No readable text detected.
            """
        case .structured:
            return """
            Extract visible text from the image and preserve useful structure.
            Rules:
            - Output only visible text from the image.
            - Use Markdown tables only when row and column structure is clear.
            - Preserve key-value pairs, receipt lines, labels, amounts, dates, and units.
            - Do not invent owners, totals, dates, labels, or missing values.
            - If no readable text is visible, output exactly: No readable text detected.
            """
        case .extractThenTranslate:
            return """
            Extract visible text from the image.
            Rules:
            - Output only text that is visible in the image.
            - Preserve original languages, line breaks, numbers, punctuation, labels, and reading order.
            - Do not translate in this step.
            - Do not describe the image.
            - If no readable text is visible, output exactly: No readable text detected.
            """
        case .explainImage:
            return """
            Explain the screenshot or image in clear Chinese.
            Rules:
            - Describe the visible content, UI, chart, error, workflow, or document state that matters.
            - Quote short visible text only when it helps the explanation.
            - Do not invent off-screen context.
            - If the image is unreadable, say what cannot be determined.
            - Output only the explanation.
            """
        }
    }

    public static func visionProbePrompt() -> String {
        """
        This is a capability probe using a generated non-sensitive image.
        If this request reaches you with an image attached, reply exactly: VISION_OK
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
