import Foundation

public enum PromptTemplates {
    public static func systemPrompt(for task: TaskKind, preferences: AppPreferences) -> String {
        if let customPrompt = customSystemPrompt(for: task, preferences: preferences) {
            return customPrompt
        }
        return defaultSystemPrompt(for: task)
    }

    public static func defaultSystemPrompt(for task: TaskKind) -> String {
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
        if let customPrompt = customUserPrompt(for: request, preferences: preferences, isRetry: true) {
            return customPrompt
        }
        return defaultUserPrompt(for: request, preferences: preferences, isRetry: true)
    }

    public static func userPrompt(for request: TaskRequest, preferences: AppPreferences) -> String {
        if let customPrompt = customUserPrompt(for: request, preferences: preferences, isRetry: false) {
            return customPrompt
        }
        return defaultUserPrompt(for: request, preferences: preferences, isRetry: false)
    }

    public static func defaultUserPrompt(for request: TaskRequest, preferences: AppPreferences, isRetry: Bool = false) -> String {
        switch request.task {
        case .translate:
            let target = request.targetLanguage ?? preferences.defaultTranslationTarget
            let qualityMode = request.translationQuality ?? preferences.defaultTranslationQuality
            return translationPrompt(
                inputText: request.inputText,
                target: target,
                qualityMode: qualityMode,
                isRetry: isRetry
            )
        case .webPageTranslate:
            return webPageTranslationPrompt(inputText: request.inputText, isRetry: isRetry)
        case .polish:
            return polishPrompt(
                inputText: request.inputText,
                style: request.polishStyle ?? preferences.defaultPolishStyle,
                isRetry: isRetry
            )
        case .summarize:
            return summarizePrompt(
                inputText: request.inputText,
                mode: request.summaryMode ?? preferences.defaultSummaryMode,
                isRetry: isRetry
            )
        case .explain:
            return explainPrompt(
                inputText: request.inputText,
                mode: request.explanationMode ?? preferences.defaultExplanationMode,
                isRetry: isRetry
            )
        case .extractTodos:
            return todosPrompt(
                inputText: request.inputText,
                mode: request.todoExtractionMode ?? preferences.defaultTodoExtractionMode,
                isRetry: isRetry
            )
        case .ocr:
            return request.inputText
        }
    }

    private static func customSystemPrompt(for task: TaskKind, preferences: AppPreferences) -> String? {
        let rawPrompt: String
        switch task {
        case .translate, .polish, .summarize, .explain, .extractTodos:
            rawPrompt = preferences.promptTemplates.textPrompt(for: task).systemPrompt
        case .ocr:
            rawPrompt = preferences.promptTemplates.ocrSystemPrompt
        case .webPageTranslate:
            return nil
        }
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return renderPromptTemplate(
            rawPrompt,
            variables: systemVariables(for: task, preferences: preferences),
            appendInputIfMissing: false
        )
    }

    private static func customUserPrompt(for request: TaskRequest, preferences: AppPreferences, isRetry: Bool) -> String? {
        guard TaskKind.interactiveCases.contains(request.task) else {
            return nil
        }
        let rawPrompt = preferences.promptTemplates.textPrompt(for: request.task).userPrompt
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return renderPromptTemplate(
            rawPrompt,
            variables: textTaskVariables(for: request, preferences: preferences, isRetry: isRetry),
            appendInputIfMissing: true
        )
    }

    private static func textTaskVariables(
        for request: TaskRequest,
        preferences: AppPreferences,
        isRetry: Bool
    ) -> [String: String] {
        let target = request.targetLanguage ?? preferences.defaultTranslationTarget
        let translationQuality = request.translationQuality ?? preferences.defaultTranslationQuality
        let polishStyle = request.polishStyle ?? preferences.defaultPolishStyle
        let summaryMode = request.summaryMode ?? preferences.defaultSummaryMode
        let explanationMode = request.explanationMode ?? preferences.defaultExplanationMode
        let todoMode = request.todoExtractionMode ?? preferences.defaultTodoExtractionMode

        var variables = systemVariables(for: request.task, preferences: preferences)
        variables["input"] = request.inputText
        variables["sourceLanguage"] = request.sourceLanguage ?? "auto"
        variables["targetLanguage"] = targetLanguageName(for: target)
        variables["target"] = targetLanguageName(for: target)
        variables["targetLanguageValue"] = target
        variables["translationQuality"] = translationQualityInstruction(translationQuality)
        variables["translationQualityInstruction"] = translationQualityInstruction(translationQuality)
        variables["translationQualityValue"] = translationQuality.rawValue
        variables["polishStyle"] = polishStyleInstruction(polishStyle)
        variables["polishStyleValue"] = polishStyle
        variables["summaryMode"] = summaryModeInstruction(summaryMode)
        variables["summaryModeValue"] = summaryMode.rawValue
        variables["summaryModeTitle"] = summaryMode.title
        variables["explanationMode"] = explanationModeInstruction(explanationMode)
        variables["explanationModeValue"] = explanationMode.rawValue
        variables["explanationModeTitle"] = explanationMode.title
        variables["todoMode"] = todoModeInstruction(todoMode)
        variables["todoModeValue"] = todoMode.rawValue
        variables["todoModeTitle"] = todoMode.title
        variables["retryInstruction"] = retryInstruction(for: request.task, isRetry: isRetry)
        return variables
    }

    private static func systemVariables(for task: TaskKind, preferences: AppPreferences) -> [String: String] {
        [
            "task": task.rawValue,
            "taskName": task.title,
            "targetLanguage": targetLanguageName(for: preferences.defaultTranslationTarget),
            "target": targetLanguageName(for: preferences.defaultTranslationTarget),
            "targetLanguageValue": preferences.defaultTranslationTarget,
            "translationQuality": translationQualityInstruction(preferences.defaultTranslationQuality),
            "translationQualityInstruction": translationQualityInstruction(preferences.defaultTranslationQuality),
            "translationQualityValue": preferences.defaultTranslationQuality.rawValue,
            "polishStyle": polishStyleInstruction(preferences.defaultPolishStyle),
            "polishStyleValue": preferences.defaultPolishStyle,
            "summaryMode": summaryModeInstruction(preferences.defaultSummaryMode),
            "summaryModeValue": preferences.defaultSummaryMode.rawValue,
            "summaryModeTitle": preferences.defaultSummaryMode.title,
            "explanationMode": explanationModeInstruction(preferences.defaultExplanationMode),
            "explanationModeValue": preferences.defaultExplanationMode.rawValue,
            "explanationModeTitle": preferences.defaultExplanationMode.title,
            "todoMode": todoModeInstruction(preferences.defaultTodoExtractionMode),
            "todoModeValue": preferences.defaultTodoExtractionMode.rawValue,
            "todoModeTitle": preferences.defaultTodoExtractionMode.title
        ]
    }

    private static func retryInstruction(for task: TaskKind, isRetry: Bool) -> String {
        guard isRetry else {
            return ""
        }
        switch task {
        case .translate, .webPageTranslate:
            return "This is a retry. Output only the requested result."
        case .polish:
            return "这是重试，请严格只输出润色后的正文。"
        case .summarize:
            return "这是重试，请严格只输出总结。"
        case .explain:
            return "这是重试，请严格只输出解释。"
        case .extractTodos:
            return "这是重试，请严格只输出待办列表。"
        case .ocr:
            return "This is a retry. Output only the requested image result."
        }
    }

    private static func renderPromptTemplate(
        _ template: String,
        variables: [String: String],
        appendInputIfMissing: Bool
    ) -> String {
        var rendered = template
        for key in variables.keys.sorted(by: { $0.count > $1.count }) {
            let value = variables[key] ?? ""
            rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: value)
            rendered = rendered.replacingOccurrences(of: "{\(key)}", with: value)
        }
        if appendInputIfMissing,
           let input = variables["input"],
           !input.isEmpty,
           !containsTemplateVariable(template, "input") {
            rendered += "\n\n\(input)"
        }
        return rendered
    }

    private static func containsTemplateVariable(_ template: String, _ variable: String) -> Bool {
        template.contains("{\(variable)}") || template.contains("{{\(variable)}}")
    }

    private static func translationPrompt(
        inputText: String,
        target: String,
        qualityMode: WebPageTranslationQualityMode,
        isRetry: Bool
    ) -> String {
        let targetLanguage = target == "auto"
            ? "English if the source text is mainly Chinese, otherwise Simplified Chinese"
            : targetLanguageName(for: target)
        let qualityInstruction = translationQualityInstruction(qualityMode)

        if isRetry {
            return """
            Translate to \(targetLanguage). \(qualityInstruction) Output only the translation.
            \(inputText)
            """
        }

        return """
        Translate to \(targetLanguage). \(qualityInstruction) Output only the translation.
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

    public static func subtitleBatchPrompt(
        segments: [SubtitleSegment],
        targetLanguage: String,
        isRetry: Bool
    ) throws -> String {
        let items = segments.map { SubtitlePromptItem(id: $0.id.uuidString, text: $0.originalText) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(items)
        let json = String(decoding: data, as: UTF8.self)
        let target = targetLanguageName(for: targetLanguage)
        let retryLine = isRetry
            ? "This is a retry. Return only the JSON array, with no Markdown fences and no prose."
            : "Return only the JSON array, with no Markdown fences and no prose."

        return """
        Translate each subtitle item to \(target).
        \(retryLine)
        Return a JSON array with objects in the same order:
        [{"id":"...","translation":"..."}]

        Subtitle translation rules:
        - Keep each line concise enough to read as a subtitle.
        - Preserve names, numbers, units, UI labels, and technical terms.
        - Do not merge, split, reorder, or add segments.
        - Do not add explanations or speaker labels unless they are present in the source.
        - Prefer natural, readable \(target) over long literal prose.

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

    private static func translationQualityInstruction(_ mode: WebPageTranslationQualityMode) -> String {
        switch mode {
        case .natural:
            return "Prefer fluent, natural phrasing in the target language while preserving the source meaning."
        case .literal:
            return "Prefer a more literal translation; preserve source sentence structure and terminology when readable."
        case .technical:
            return "Preserve technical terminology, API names, product names, code-like tokens, and UI labels; use standard technical wording in the target language where appropriate."
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

    private static func summarizePrompt(inputText: String, mode: SummaryMode, isRetry: Bool) -> String {
        let retryLine = isRetry ? "这是重试，请严格只输出总结。" : "总结下面的文本。"
        return """
        你是一个总结函数。\(retryLine)
        规则：
        \(summaryModeInstruction(mode))
        - 不编造原文没有的结论、日期、负责人或优先级。

        原文：
        \(inputText)

        总结：
        """
    }

    private static func explainPrompt(inputText: String, mode: ExplanationMode, isRetry: Bool) -> String {
        let retryLine = isRetry ? "这是重试，请严格只输出解释。" : "解释下面的文本。"
        return """
        你是一个解释函数。\(retryLine)
        规则：
        \(explanationModeInstruction(mode))
        - 不编造外部上下文；不确定的地方明确说不确定。

        原文：
        \(inputText)

        解释：
        """
    }

    private static func todosPrompt(inputText: String, mode: TodoExtractionMode, isRetry: Bool) -> String {
        let retryLine = isRetry ? "这是重试，请严格只输出待办列表。" : "从下面文本中提取待办。"
        return """
        你是一个待办提取函数。\(retryLine)
        规则：
        \(todoModeInstruction(mode))
        - 只提取可以执行的事项，不把背景信息或愿望改写成待办。
        - 如果没有待办，输出“无明确待办”。

        原文：
        \(inputText)

        待办：
        """
    }

    private static func summaryModeInstruction(_ mode: SummaryMode) -> String {
        switch mode {
        case .keyPoints:
            return """
            - 只输出总结正文。
            - 用简洁中文输出 3-6 条关键点。
            - 如果原文包含行动项，单独用“行动项：”列出；不要把行动项混进普通摘要。
            """
        case .oneSentence:
            return """
            - 只输出一句中文总结。
            - 这句话必须概括原文最核心的信息，避免项目符号、标题和额外说明。
            """
        case .detailed:
            return """
            - 输出较完整的中文摘要。
            - 按“背景：”“重点：”“结论：”组织内容；缺失的信息写“未提及”。
            - 重点部分可以使用项目符号，但不要超过 8 条。
            """
        case .meetingNotes:
            return """
            - 输出会议纪要格式。
            - 按“议题：”“结论：”“行动项：”组织内容；没有行动项时写“无明确行动项”。
            - 行动项要尽量包含任务、负责人和截止日期；缺失的信息写“未提及”。
            """
        case .structured:
            return """
            - 输出结构化摘要。
            - 固定使用“背景：”“重点：”“风险：”“下一步：”四个小节。
            - 每个小节只写原文明确支持的信息；缺失时写“未提及”。
            """
        }
    }

    private static func explanationModeInstruction(_ mode: ExplanationMode) -> String {
        switch mode {
        case .plain:
            return """
            - 只输出解释正文。
            - 用通俗中文解释含义、背景、关键影响和用户应该注意的点。
            - 如果输入像术语、错误、日志、代码片段或密集段落，先说明它是什么，再解释为什么重要。
            """
        case .technical:
            return """
            - 只输出技术解释正文。
            - 保留专业术语、接口名、错误码、代码符号和关键数字。
            - 解释机制、依赖关系、影响范围和需要注意的技术边界。
            """
        case .errorDiagnosis:
            return """
            - 输出错误诊断格式。
            - 按“现象：”“可能原因：”“排查步骤：”“处理建议：”组织内容。
            - 如果输入不是错误、日志或异常信息，也要说明可诊断信息不足。
            """
        case .code:
            return """
            - 输出代码解释格式。
            - 说明代码在做什么、核心流程、输入输出、边界情况和潜在风险。
            - 保留函数名、变量名、类型名和关键代码符号。
            """
        case .background:
            return """
            - 输出背景补充说明。
            - 解释它是什么、常见上下文、为什么重要、可能影响和用户应关注的点。
            - 不确定的背景必须标注为推测或不确定。
            """
        }
    }

    private static func todoModeInstruction(_ mode: TodoExtractionMode) -> String {
        switch mode {
        case .actionItems:
            return """
            - 只输出待办列表。
            - 每条用 "- " 开头。
            - 每条尽量包含任务、负责人、截止日期、优先级；没有的信息不要编造。
            """
        case .byOwner:
            return """
            - 按负责人分组输出待办。
            - 负责人明确时使用“负责人：姓名”作为分组标题；没有负责人时归入“未指定负责人：”。
            - 每条待办用 "- " 开头，并保留截止日期、优先级等原文明确的信息。
            """
        case .byPriority:
            return """
            - 按优先级分组输出待办。
            - 固定使用“高优先级：”“中优先级：”“低优先级：”“未指定优先级：”四组；没有内容的组可以省略。
            - 只能根据原文明确表述判断优先级，不要自行推断。
            """
        case .byDeadline:
            return """
            - 按截止时间从近到远输出待办。
            - 每条用 "- " 开头，包含任务和原文明确的截止时间。
            - 没有截止时间的任务放在“未指定截止时间：”分组。
            """
        case .table:
            return """
            - 输出 Markdown 表格。
            - 表头固定为：任务 | 负责人 | 截止时间 | 优先级 | 依据。
            - 没有明确负责人、截止时间或优先级时写“未提及”；依据列引用简短原文片段。
            """
        }
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

    public static func ocrPrompt(
        mode: OCRMode,
        targetLanguage: String = "zh-Hans",
        preferences: AppPreferences = AppPreferences()
    ) -> String {
        let rawPrompt = preferences.promptTemplates.ocrPrompt(for: mode)
        if !rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return renderPromptTemplate(
                rawPrompt,
                variables: ocrVariables(mode: mode, targetLanguage: targetLanguage),
                appendInputIfMissing: false
            )
        }
        return defaultOCRPrompt(mode: mode, targetLanguage: targetLanguage)
    }

    public static func defaultOCRPrompt(mode: OCRMode, targetLanguage: String = "zh-Hans") -> String {
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
            - Do not enumerate the same word, legend label, or data-point label repeatedly; mention repeated items once.
            - Keep the explanation concise and stop when the relevant visible content is covered.
            - Do not invent off-screen context.
            - If the image is unreadable, say what cannot be determined.
            - Output only the explanation.
            """
        }
    }

    private static func ocrVariables(mode: OCRMode, targetLanguage: String) -> [String: String] {
        [
            "mode": mode.rawValue,
            "modeName": mode.title,
            "targetLanguage": targetLanguageName(for: targetLanguage),
            "target": targetLanguageName(for: targetLanguage),
            "targetLanguageValue": targetLanguage
        ]
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

    private struct SubtitlePromptItem: Encodable {
        var id: String
        var text: String
    }
}
