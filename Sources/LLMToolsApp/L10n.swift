import Foundation
import LLMToolsCore

enum L10n {
    static func text(_ key: String, language: AppLanguage) -> String {
        switch language {
        case .english:
            return key
        case .chinese:
            return chinese[key] ?? key
        }
    }

    static func targetLanguageName(_ value: String, language: AppLanguage) -> String {
        switch language {
        case .english:
            switch value {
            case "auto": return "Auto"
            case "zh-Hans", "zh", "Chinese": return "Chinese"
            case "en", "English": return "English"
            case "ja", "Japanese": return "Japanese"
            case "ko", "Korean": return "Korean"
            default: return value
            }
        case .chinese:
            switch value {
            case "auto": return "自动"
            case "zh-Hans", "zh", "Chinese": return "中文"
            case "en", "English": return "英文"
            case "ja", "Japanese": return "日文"
            case "ko", "Korean": return "韩文"
            default: return value
            }
        }
    }

    static func polishStyleName(_ value: String, language: AppLanguage) -> String {
        switch language {
        case .english:
            return value.prefix(1).uppercased() + value.dropFirst()
        case .chinese:
            switch value {
            case "natural": return "自然"
            case "formal": return "正式"
            case "concise": return "简洁"
            case "conversational": return "口语"
            case "technical": return "技术"
            default: return value
            }
        }
    }

    static func summaryModeName(_ mode: SummaryMode, language: AppLanguage) -> String {
        switch language {
        case .english:
            return mode.title
        case .chinese:
            switch mode {
            case .keyPoints: return "关键要点"
            case .oneSentence: return "一句话"
            case .detailed: return "详细摘要"
            case .meetingNotes: return "会议纪要"
            case .structured: return "结构化摘要"
            }
        }
    }

    static func explanationModeName(_ mode: ExplanationMode, language: AppLanguage) -> String {
        switch language {
        case .english:
            return mode.title
        case .chinese:
            switch mode {
            case .plain: return "通俗解释"
            case .technical: return "技术解释"
            case .errorDiagnosis: return "错误诊断"
            case .code: return "代码解释"
            case .background: return "背景补充"
            }
        }
    }

    static func todoExtractionModeName(_ mode: TodoExtractionMode, language: AppLanguage) -> String {
        switch language {
        case .english:
            return mode.title
        case .chinese:
            switch mode {
            case .actionItems: return "行动项"
            case .byOwner: return "按负责人"
            case .byPriority: return "按优先级"
            case .byDeadline: return "按截止时间"
            case .table: return "任务表格"
            }
        }
    }

    static func pendingIndicatorStyleName(_ style: WebPagePendingIndicatorStyle, language: AppLanguage) -> String {
        switch language {
        case .english:
            switch style {
            case .loading: return "Loading"
            case .flipText: return "Flip text"
            case .none: return "None"
            }
        case .chinese:
            switch style {
            case .loading: return "Loading"
            case .flipText: return "翻牌"
            case .none: return "无样式"
            }
        }
    }

    static func webPageReadingModeName(_ mode: WebPageReadingMode, language: AppLanguage) -> String {
        switch language {
        case .english:
            switch mode {
            case .replace: return "Replace"
            case .bilingual: return "Bilingual"
            case .original: return "Original"
            }
        case .chinese:
            switch mode {
            case .replace: return "替换译文"
            case .bilingual: return "双语对照"
            case .original: return "原文"
            }
        }
    }

    static func webPageTranslationQualityName(_ mode: WebPageTranslationQualityMode, language: AppLanguage) -> String {
        switch language {
        case .english:
            switch mode {
            case .natural: return "Natural"
            case .literal: return "Literal"
            case .technical: return "Technical"
            }
        case .chinese:
            switch mode {
            case .natural: return "自然"
            case .literal: return "直译"
            case .technical: return "技术术语"
            }
        }
    }

    static func ocrModeName(_ mode: OCRMode, language: AppLanguage) -> String {
        switch language {
        case .english:
            return mode.title
        case .chinese:
            switch mode {
            case .plainText: return "提取文字"
            case .structured: return "结构化提取"
            case .extractThenTranslate: return "提取后翻译"
            case .explainImage: return "解释图片"
            }
        }
    }

    private static let chinese: [String: String] = [
        "Quick Action": "快捷操作",
        "Selection Actions": "选择操作",
        "Choose an action": "选择操作",
        "Widget": "组件",
        "General": "通用",
        "Shortcuts": "快捷键",
        "About": "关于",
        "Launch": "启动",
        "Interface": "界面",
        "Text": "文本",
        "Language": "语言",
        "Language Routing": "语言路由",
        "Enable language routing": "启用语言路由",
        "fastText model": "fastText 模型",
        "FTZ model file": "FTZ 模型文件",
        "BIN model file": "BIN 模型文件",
        "Choose fastText model file": "选择 fastText 模型文件",
        "Leave empty to use the installed fastText model under Application Support, or the LLMTOOLS_LID_MODEL_* environment variables.": "留空时使用 Application Support 中已安装的 fastText 模型，或使用 LLMTOOLS_LID_MODEL_* 环境变量。",
        "Use for text tasks": "用于文本任务",
        "Use for webpage translation": "用于网页翻译",
        "Use for OCR": "用于 OCR",
        "Use for subtitles": "用于字幕",
        "Latin short-text minimum": "拉丁短文本最小长度",
        "CJK short-text minimum": "中日韩短文本最小长度",
        "Low confidence threshold": "低置信度阈值",
        "OCR confidence boost": "OCR 置信度补偿",
        "Language ID command": "语言识别命令",
        "Use {python}, {sidecar}, {model_ftz}, {model_bin}, and {variant}. Empty field uses the bundled fastText sidecar when the local model is installed.": "可使用 {python}、{sidecar}、{model_ftz}、{model_bin} 和 {variant}。留空时，在本地模型已安装的情况下使用内置 fastText sidecar。",
        "Sample detection text": "检测示例文本",
        "This is a language detection health check.": "这是一段语言识别健康检查文本。",
        "Fixture mode uses LLMTOOLS_LID_FIXTURE_JSON for dependency-free checks.": "夹具模式使用 LLMTOOLS_LID_FIXTURE_JSON，可在无外部依赖时检查。",
        "Repairing language routing runtime": "正在修复语言路由运行时",
        "Language routing runtime repaired": "语言路由运行时已修复",
        "Language routing runtime repair failed": "语言路由运行时修复失败",
        "Installs or reuses the isolated fastText language routing runtime, downloads the compact model, then smoke-tests the sidecar.": "安装或复用隔离的 fastText 语言路由运行时，下载小模型，并对 sidecar 做冒烟测试。",
        "Detected source": "检测来源语言",
        "Source": "来源",
        "Selection": "划词",
        "Global shortcuts": "全局快捷键",
        "Quick Action mode shortcuts": "快捷弹窗模式",
        "Text action shortcuts": "文本动作快捷键",
        "Image action shortcuts": "图片动作快捷键",
        "Speech action shortcuts": "语音动作快捷键",
        "Switch to text mode": "切换到文本",
        "Switch to image mode": "切换到图片",
        "Switch to media mode": "切换到媒体",
        "Switch to speech mode": "切换到语音",
        "Generate speech": "生成语音",
        "Preview selected voice": "试听所选音色",
        "Read source aloud": "朗读原文",
        "Read translation aloud": "朗读译文",
        "Read word aloud": "朗读单词",
        "Stop speech generation": "停止生成朗读",
        "Translation": "译文",
        "Details": "详解",
        "Detailed translation": "详细翻译",
        "Enable detailed translation": "开启详细翻译",
        "Alternative translations": "候选译法",
        "Key vocabulary": "重点词汇",
        "Language notes": "语言提示",
        "Usage": "用法",
        "Example": "例句",
        "Play generated speech": "播放生成语音",
        "Export speech as WAV": "导出语音为 WAV",
        "Export speech as M4A": "导出语音为 M4A",
        "Open Quick Action without selected text": "打开快捷操作（不读取选中文本）",
        "Open live subtitles": "打开实时字幕",
        "Press shortcut": "按下快捷键",
        "Change shortcut": "修改快捷键",
        "Reset shortcut": "恢复默认快捷键",
        "Shortcut is already assigned": "快捷键已被占用",
        "Use Command, Option, or Control with a key": "请使用 Command、Option 或 Control 加一个按键",
        "Webpage": "网页",
        "Browser": "浏览器",
        "Extension folder": "扩展文件夹",
        "Default model": "默认模型",
        "Default LLM model": "默认 LLM 模型",
        "Task default models": "任务默认模型",
        "Used by LLM text tasks and by fast MT fallback. Fast MT uses its own local runtime/model.": "用于 LLM 文本任务和快速 MT 回退。快速 MT 使用自己的本地运行时/模型。",
        "Used as the fallback for text-mode LLM actions. Webpage translation can choose its own model on the Webpage tab.": "作为文本模式 LLM 动作的回退模型。网页翻译可以在网页页签单独选择模型。",
        "History": "历史",
        "Application": "应用",
        "Version": "版本",
        "Data": "数据",
        "Open Data Folder": "打开数据文件夹",
        "Quit llmTools": "退出 llmTools",
        "Models": "模型",
        "Models & Settings": "模型与设置",
        "Model Settings": "模型设置",
        "Model Management": "模型管理",
        "Thinking mode": "思考模式",
        "Thinking enabled": "思考模式已开启",
        "Thinking disabled": "思考模式已关闭",
        "Failed to update thinking mode": "更新思考模式失败",
        "Context updated": "上下文已更新",
        "Failed to update context": "更新上下文失败",
        "Settings": "设置",
        "Preferences": "偏好设置",
        "Defaults": "默认值",
        "Text defaults": "文本默认值",
        "Prompts": "提示词",
        "Text prompts": "文本提示词",
        "Image prompts": "图片提示词",
        "System prompt": "系统提示词",
        "User prompt": "用户提示词",
        "Mode prompt": "模式提示词",
        "Image recognition system": "图片识别系统",
        "Built-in default": "内置默认",
        "Use built-in default": "使用内置默认",
        "Empty uses the built-in default.": "留空则使用内置默认。",
        "Custom": "自定义",
        "OCR": "图片识别",
        "Image": "图片",
        "Text mode": "文本",
        "Image mode": "图片",
        "Media mode": "媒体",
        "Speech mode": "语音",
        "Voice": "音色",
        "Delivery style": "语气",
        "Natural delivery": "自然",
        "Warm and gentle": "温柔舒缓",
        "Calm and formal": "沉稳正式",
        "Cheerful and lively": "开心活泼",
        "Sad and subdued": "悲伤低沉",
        "Excited and powerful": "激动有力",
        "Soft whisper": "轻声耳语",
        "Paste text to synthesize speech.": "粘贴需要生成语音的文字。",
        "Generate or preview speech here.": "在这里生成并试听语音。",
        "Generated speech is ready to play or export.": "语音已生成，可以播放或导出。",
        "Stop generating": "停止生成",
        "Play speech": "播放语音",
        "Pause speech": "暂停语音",
        "Voice preview is generating": "正在生成音色试听",
        "Media": "媒体",
        "Meeting": "会议",
        "Feature": "功能",
        "Media subtitles": "媒体字幕",
        "Enable media subtitles": "启用媒体字幕",
        "ASR is local-only in Phase 4. No remote ASR fallback is used.": "Phase 4 的 ASR 仅本地运行，不使用远程 ASR fallback。",
        "Realtime ASR": "实时 ASR",
        "File ASR": "文件 ASR",
        "Default realtime model": "默认实时模型",
        "Default file model": "默认文件模型",
        "Health Check": "健康检查",
        "SenseVoiceSmall is low-latency; Qwen3-ASR realtime is experimental and uses a conservative final-transcript strategy.": "SenseVoiceSmall 偏低延迟；Qwen3-ASR 实时模式仍是实验性能力，并使用更保守的最终字幕策略。",
        "Qwen3-ASR-0.6B can be used for file transcription and optional realtime subtitles when the local runtime is ready.": "本地运行时就绪后，Qwen3-ASR-0.6B 可用于文件转写，也可选作实时字幕 ASR。",
        "Fun-ASR-MLT-Nano is preferred for broad-language realtime subtitles when a local streaming runtime is configured. Qwen3-ASR realtime remains experimental.": "配置本地流式运行时后，Fun-ASR-MLT-Nano 优先用于多语言实时字幕；Qwen3-ASR 实时模式仍是实验性能力。",
        "Fun-ASR-MLT-Nano remains the broad-language default; MLX Qwen3-ASR and whisper.cpp Core ML also run realtime through persistent local sidecars.": "Fun-ASR-MLT-Nano 仍作为多语言默认选择；MLX Qwen3-ASR 与 whisper.cpp Core ML 也会通过长驻本地 sidecar 运行实时字幕。",
        "Qwen3-ASR-0.6B is quality-oriented for file transcription. Fun-ASR uses local streaming or GGUF sidecars for lower-latency live captions.": "Qwen3-ASR-0.6B 更偏文件转写质量；Fun-ASR 通过本地流式或 GGUF sidecar 提供更低延迟的实时字幕。",
        "VibeVoice-ASR is a heavy file-only rich transcription model; native speaker/timestamp output is used before external diarization.": "VibeVoice-ASR 是重型文件转写模型；如果它原生返回说话人和时间戳，会优先使用这份结果，不再额外跑说话人分离。",
        "Local ASR runtime": "本地 ASR 运行时",
        "Runtime source": "运行时来源",
        "Switching ASR model": "正在切换 ASR 模型",
        "Switching audio source": "正在切换音频来源",
        "Fun-ASR command": "Fun-ASR 命令",
        "SenseVoice command": "SenseVoice 命令",
        "Qwen3-ASR command": "Qwen3-ASR 命令",
        "VibeVoice-ASR command": "VibeVoice-ASR 命令",
        "Whisper command": "Whisper 命令",
        "Generic ASR command": "通用 ASR 命令",
        "Use {model}, {audio}, {language}, {mode}, and {isFinal}. Empty fields fall back to environment variables or detected local runtimes.": "可使用 {model}、{audio}、{language}、{mode} 和 {isFinal}。留空则回退到环境变量或自动发现的本地运行时。",
        "Subtitle defaults": "字幕默认值",
        "Default subtitle settings": "默认字幕设置",
        "Source language": "源语言",
        "Target language applies when Display is Translated or Bilingual.": "目标语言仅在显示为“译文”或“双语”时生效。",
        "Display": "显示",
        "Audio source": "音频来源",
        "System audio": "系统音频",
        "Microphone": "麦克风",
        "System + Microphone": "系统音频 + 麦克风",
        "Window opacity": "窗口透明度",
        "Keep window on top": "置顶窗口",
        "Stop keeping window on top": "取消置顶",
        "Live subtitles": "实时字幕",
        "Start live subtitles": "开始实时字幕",
        "Stop live subtitles": "停止实时字幕",
        "Starting live subtitles": "正在启动实时字幕",
        "Live subtitles running": "实时字幕运行中",
        "Stopping live subtitles": "正在停止实时字幕",
        "Live subtitles stopped": "实时字幕已停止",
        "Live subtitles failed": "实时字幕失败",
        "Clear subtitle history": "清空历史字幕",
        "Subtitle text color": "字幕文字颜色",
        "Enter immersive subtitles": "进入沉浸字幕",
        "Exit immersive subtitles": "退出沉浸字幕",
        "Listening...": "正在听...",
        "System audio connected. Waiting for speech...": "系统音频已连接，等待语音...",
        "Microphone connected. Waiting for speech...": "麦克风已连接，等待语音...",
        "System audio and microphone connected. Waiting for speech...": "系统音频和麦克风已连接，等待语音...",
        "Speech detected. Waiting for ASR...": "已检测到语音，等待转写...",
        "Transcribing...": "正在转写...",
        "ASR returned no text.": "ASR 未返回文本。",
        "Draft": "草稿",
        "Save transcript history": "保存转写历史",
        "Save translated subtitle history": "保存翻译字幕历史",
        "Raw audio, full page URLs, page titles, transcripts, and translated subtitles are not saved by default.": "默认不保存原始音频、完整页面 URL、页面标题、完整转写或翻译字幕。",
        "Desktop floating subtitles": "桌面悬浮字幕",
        "Choose Media": "选择媒体",
        "Drop audio or video.": "拖入音频或视频。",
        "Media loaded": "媒体已载入",
        "Subtitle preview will appear here.": "字幕预览会显示在这里。",
        "Generate subtitles": "生成字幕",
        "Retry translation": "重试翻译",
        "Realtime": "实时",
        "File only": "仅文件",
        "Speech realtime": "语音实时",
        "Speech file-only": "语音文件",
        "Checking ASR": "正在检查 ASR",
        "ASR ready": "ASR 就绪",
        "ASR check failed": "ASR 检查失败",
        "Repair Runtime": "修复运行时",
        "Repairing ASR runtime": "正在修复 ASR 运行时",
        "ASR runtime repaired": "ASR 运行时已修复",
        "ASR runtime repair failed": "ASR 运行时修复失败",
        "Installs or reuses the matching isolated MLX ASR runtime, then writes the command template.": "安装或复用匹配的隔离 MLX ASR 运行时，并写入命令模板。",
        "Partial window": "分段窗口",
        "Reset": "重置",
        "Reset partial window to the tested default for this model.": "重置为该模型测试过的默认分段窗口。",
        "Speaker Diarization": "说话人分离",
        "Enable for file subtitles": "用于文件字幕",
        "Enable for live subtitles": "用于实时字幕",
        "Live speaker diarization remains disabled until the realtime spike passes.": "实时说话人分离在实时验证通过前保持禁用。",
        "pyannote model": "pyannote 模型",
        "Choose local pyannote config": "选择本地 pyannote 配置",
        "Use a Hugging Face repo id such as pyannote/speaker-diarization-3.1, or choose a local pyannote config.yaml if the model is already downloaded.": "可填写 Hugging Face repo id，例如 pyannote/speaker-diarization-3.1；如果模型已下载，也可以选择本地 pyannote config.yaml。",
        "HF cache directory": "HF cache 目录",
        "Choose cache folder": "选择缓存目录",
        "Open cache folder": "打开缓存目录",
        "Leave empty to use the Hugging Face default cache: %@.": "留空时使用 Hugging Face 默认缓存目录：%@。",
        "pyannote model, token, cache, command, and runtime are managed under Models > Model Settings.": "pyannote 模型、Token、缓存、命令和运行时都在 模型 > 模型设置 中统一管理。",
        "Configure pyannote in Model Settings": "去模型设置配置 pyannote",
        "Diarization command": "说话人分离命令",
        "Use {audio_wav_16k_mono}, {output_json}, {diarization_model}, and {hf_cache}. The token is provided through PYANNOTE_AUTH_TOKEN and cannot be inserted into the command template. Empty field uses the bundled pyannote sidecar when the local runtime is installed.": "可使用 {audio_wav_16k_mono}、{output_json}、{diarization_model} 和 {hf_cache}。Token 通过 PYANNOTE_AUTH_TOKEN 环境变量传递，不能插入命令模板。留空时，在本地运行时已安装的情况下使用内置 pyannote sidecar。",
        "HF token local storage": "HF Token 本地存储",
        "HF token": "HF Token",
        "Save Token": "保存 Token",
        "Delete Token": "删除 Token",
        "Open model terms": "打开模型条款",
        "Create HF token": "创建 HF Token",
        "Persist speaker embeddings": "持久化说话人 embedding",
        "pyannote requires accepting Hugging Face model terms. Tokens stay in a local Application Support file or environment variables; llmTools does not upload audio.": "pyannote 需要先接受 Hugging Face 模型条款。Token 保存在本机 Application Support 文件或环境变量中；llmTools 不会上传音频。",
        "pyannote requires accepting Hugging Face model terms unless you point to a fully cached local config. Tokens stay in a local Application Support file or environment variables; llmTools does not upload audio.": "除非你指向已完整缓存的本地 config，pyannote 需要先接受 Hugging Face 模型条款。Token 保存在本机 Application Support 文件或环境变量中；llmTools 不会上传音频。",
        "pyannote requires accepting the Hugging Face terms for both speaker-diarization-3.1 and segmentation-3.0 unless you point to a fully cached local config. Tokens stay in a local Application Support file or environment variables; llmTools does not upload audio.": "除非你指向已完整缓存的本地 config，pyannote 需要先接受 speaker-diarization-3.1 和 segmentation-3.0 两个 Hugging Face 条款。Token 保存在本机 Application Support 文件或环境变量中；llmTools 不会上传音频。",
        "Fixture mode uses LLMTOOLS_DIARIZATION_FIXTURE_JSON for dependency-free checks.": "夹具模式使用 LLMTOOLS_DIARIZATION_FIXTURE_JSON，可在无外部依赖时检查。",
        "Token present": "Token 已配置",
        "Paste a Hugging Face token first.": "请先粘贴 Hugging Face Token。",
        "Speaker diarization token not saved": "说话人分离 Token 未保存",
        "Speaker diarization runtime configured": "说话人分离运行时已配置",
        "HF token saved": "HF Token 已保存",
        "Failed to save HF token": "HF Token 保存失败",
        "HF token removed": "HF Token 已删除",
        "Failed to remove HF token": "HF Token 删除失败",
        "Repairing speaker diarization runtime": "正在修复说话人分离运行时",
        "Speaker diarization runtime repaired": "说话人分离运行时已修复",
        "Speaker diarization runtime repair failed": "说话人分离运行时修复失败",
        "Regenerate subtitles to apply speaker diarization": "请重新生成字幕以应用说话人分离",
        "Transcribing media": "正在转写媒体",
        "Transcribing and separating speakers": "正在转写并分离说话人",
        "Speaker diarization failed": "说话人分离失败",
        "No speaker labels": "没有说话人标签",
        "speaker": "个说话人",
        "speakers": "个说话人",
        "Fix path": "解决路径",
        "1. Open the pyannote model page and accept the model terms with your Hugging Face account.": "1. 打开 pyannote 模型页面，用 Hugging Face 账号接受模型条款。",
        "1. Open the pyannote model pages and accept both speaker-diarization-3.1 and segmentation-3.0 terms with your Hugging Face account.": "1. 打开 pyannote 模型页面，用同一个 Hugging Face 账号接受 speaker-diarization-3.1 和 segmentation-3.0 两个条款。",
        "2. Create a Hugging Face token, paste it into the HF token field above, then click Save Token.": "2. 创建 Hugging Face Token，粘贴到上面的 HF Token 输入框，然后点击保存 Token。",
        "3. Run Health Check again. If the next status is runtime missing, click Repair Runtime here.": "3. 再次运行健康检查。如果下一步提示运行时缺失，就在这里点击修复运行时。",
        "Installs or reuses the local pyannote runtime used by file subtitle speaker diarization.": "安装或复用文件字幕说话人分离使用的本地 pyannote 运行时。",
        "Yes": "是",
        "No": "否",
        "Preparing media": "正在处理媒体",
        "Translating subtitles": "正在翻译字幕",
        "Choose an audio or video file first.": "请先选择音频或视频文件。",
        "Media subtitles are disabled.": "媒体字幕已关闭。",
        "Choose a local speech ASR model in Settings.": "请先在设置中选择本地语音 ASR 模型。",
        "Generate transcript segments first.": "请先生成原文字幕片段。",
        "No subtitle segments to export.": "没有可导出的字幕片段。",
        "Exported": "已导出",
        "Export": "导出",
        "Image OCR": "图片 OCR",
        "Privacy": "隐私",
        "Enable image OCR": "启用图片识别",
        "Use model recognition by default": "默认使用模型识别",
        "Run recognition after image loads": "图片加载后默认识别",
        "OCR model": "识别模型",
        "Default recognition model": "默认识别模型",
        "OCR mode": "识别模式",
        "Default recognition mode": "默认识别模式",
        "OCR history": "图片识别历史",
        "Save OCR results to recent history": "图片识别写入最近历史",
        "Raw images are never saved to recent history.": "原始图片不会写入最近历史。",
        "Choose Image": "选择图片",
        "Paste Image": "粘贴图片",
        "Load URL": "加载 URL",
        "Image URL": "图片 URL",
        "Recognize": "识别",
        "Explain Image": "解释图片",
        "Image result will appear here.": "图片识别结果会显示在这里。",
        "Drop or paste an image.": "拖入或粘贴图片。",
        "Clipboard does not contain an image.": "剪贴板里没有图片。",
        "Enter an image URL first.": "请先输入图片 URL。",
        "Downloading image": "正在下载图片",
        "Loaded image": "已加载图片",
        "Failed to load image": "加载图片失败",
        "Clear Image": "清除图片",
        "Open Image Preview": "打开大图预览",
        "Image preview unavailable.": "图片预览不可用。",
        "OCR/image recognition is disabled.": "图片识别已关闭。",
        "Follow up": "继续处理",
        "Vision": "视觉",
        "Text only": "仅文本",
        "Manual": "手动",
        "Capability": "能力",
        "Marked vision-capable": "已标记为支持视觉",
        "Marked text-only": "已标记为仅文本",
        "Capability reset": "能力已重置",
        "Testing vision": "正在测试视觉能力",
        "Vision test succeeded": "视觉测试成功",
        "Vision test failed": "视觉测试失败",
        "Mark vision-capable": "标记为支持视觉",
        "Mark text-only": "标记为仅文本",
        "Reset capability": "重置能力",
        "Test vision": "测试视觉",
        "Capability source": "能力来源",
        "Confidence": "置信度",
        "Remote provider image payload": "远程 Provider 图片载荷",
        "When the OCR model is remote, the normalized local image payload is sent to that configured provider. Remote image URLs are downloaded locally first and are not passed through.": "当识别模型是远程 Provider 时，会把规范化后的本地图片载荷发送给该 Provider。远程图片 URL 会先下载到本地，不会直接透传。",
        "Choose a vision-capable OCR model in Settings.": "请在设置里选择支持视觉的识别模型。",
        "Web Page Translation": "网页翻译",
        "Enable webpage translation": "启用网页翻译",
        "Translation model": "翻译模型",
        "Use default model": "跟随默认模型",
        "Use text default model": "跟随文本默认模型",
        "Pending translation style": "待翻译样式",
        "Site rules": "站点规则",
        "Cache & Privacy": "缓存与隐私",
        "Save webpage translations to recent history": "网页翻译写入最近历史",
        "Webpage translation batches will be saved to Recent History and can include page text snippets.": "网页翻译批次会写入最近历史，可能包含页面文本片段。",
        "Default: webpage source text and translated text are not saved to the app recent history.": "默认：网页原文和译文不会保存到应用最近历史。",
        "Extension cache": "扩展缓存",
        "Stored locally in browser extension storage, capped at 2,000 entries, and clearable from the popup by page, site, or all webpage cache.": "保存在浏览器扩展本地存储中，上限 2,000 条，可在扩展弹窗按页面、站点或全部网页缓存清除。",
        "Popup diagnostics": "弹窗诊断",
        "Uses hashes, counts, timings, model name, and error codes by default; it does not show raw page URL, domain, source text, translated text, or DOM content.": "默认只使用哈希、计数、耗时、模型名和错误码；不显示原始页面 URL、域名、原文、译文或 DOM 内容。",
        "example.com": "example.com",
        "Auto translate": "自动",
        "Never translate": "不翻译",
        "Auto-translate domains": "自动翻译域名",
        "Never-translate domains": "不翻译域名",
        "No auto-translate domains.": "暂无自动翻译域名。",
        "No never-translate domains.": "暂无不翻译域名。",
        "Reset site rules": "重置站点规则",
        "Site defaults": "站点默认值",
        "Reading defaults": "阅读模式默认值",
        "Quality defaults": "翻译质量默认值",
        "No reading defaults.": "暂无阅读模式默认值。",
        "No quality defaults.": "暂无翻译质量默认值。",
        "Reading": "阅读",
        "Quality": "质量",
        "Reset site defaults": "重置站点默认值",
        "Reveal Extension Folder": "显示扩展文件夹",
        "Extension channel": "扩展通道",
        "Extension ID": "扩展 ID",
        "Extension version": "扩展版本",
        "Native Host": "Native Host",
        "Manifest": "清单",
        "Last error code": "最近错误码",
        "Last check": "最近检查",
        "Input": "输入",
        "Result": "结果",
        "Recent History": "最近历史",
        "No recent results.": "暂无历史结果。",
        "Clear": "清空",
        "Run": "运行",
        "Regenerate": "重新生成",
        "Cancel": "取消",
        "Copy": "复制",
        "Close": "关闭",
        "Load File": "加载文件",
        "Task": "任务",
        "Target": "目标语言",
        "Style": "润色风格",
        "Model": "模型",
        "No model": "没有模型",
        "No model configured": "未配置模型",
        "No models registered yet.": "还没有注册模型。",
        "Registered Models": "已注册模型",
        "Add Model": "添加模型",
        "Add Local Model": "添加本地模型",
        "Add Provider": "添加 Provider",
        "Provider": "Provider",
        "Provider model": "Provider 模型",
        "Provider name": "Provider 名称",
        "Base URL": "Base URL",
        "API Key": "API Key",
        "Context": "上下文",
        "Added provider": "已添加 Provider",
        "Failed to add provider": "添加 Provider 失败",
        "Updated provider": "已更新 Provider",
        "Failed to update provider": "更新 Provider 失败",
        "Testing provider": "正在测试 Provider",
        "Provider test succeeded": "Provider 测试成功",
        "Provider test failed": "Provider 测试失败",
        "Edit": "编辑",
        "Save Provider": "保存 Provider",
        "Cancel Edit": "取消编辑",
        "Test": "测试",
        "Testing": "测试中",
        "Optional display name": "可选显示名称",
        "Default": "默认",
        "Use as Default": "设为默认",
        "Remove": "移除",
        "Add": "添加",
        "Choose": "选择",
        "Role": "角色",
        "Size": "大小",
        "Ctx": "上下文",
        "Launch at login": "登录时启动",
        "Launch status": "启动状态",
        "Enabled": "已启用",
        "Disabled": "已关闭",
        "Needs approval": "需要批准",
        "Pending": "待处理",
        "Not found": "未找到",
        "Unknown": "未知",
        "Widget visible on all Spaces": "悬浮组件在所有桌面显示",
        "Auto-collapse widget at screen edge": "靠近屏幕边缘自动收起组件",
        "Replace original text after processing": "处理后替换原文",
        "Show action panel after mouse selection": "鼠标划词后显示操作面板",
        "Show selection action panel": "显示划词操作面板",
        "Trigger after mouse drag selection": "鼠标拖选后触发",
        "Trigger after double-click selection": "双击选词后触发",
        "Trigger after Command-A selection": "Command-A 全选后触发",
        "Special app line limits": "特殊应用行数限制",
        "Choose App": "选择应用",
        "lines": "行",
        "App language": "应用语言",
        "Default translation target": "默认翻译目标",
        "Translation quality": "翻译质量",
        "Default translation quality": "默认翻译质量",
        "Fast MT": "快速机器翻译",
        "Force LLM translation": "强制使用 LLM 翻译",
        "When enabled, all fast MT routes immediately fall back to the normal LLM path.": "开启后，所有快速机器翻译路径会立即回退到常规 LLM 路径。",
        "Fast MT model": "快速机器翻译模型",
        "OPUS is fastest for English to Chinese. NLLB 600M supports common multilingual pairs with higher latency but much better coverage.": "OPUS 英译中最快。NLLB 600M 延迟更高，但支持常用多语言互译，覆盖面明显更好。",
        "OPUS CTranslate2 model folder": "OPUS CTranslate2 模型目录",
        "NLLB CTranslate2 model folder": "NLLB CTranslate2 模型目录",
        "Choose CTranslate2 model folder": "选择 CTranslate2 模型目录",
        "Leave empty to use the installed Fast MT model under Application Support, or the LLMTOOLS_FASTMT_* environment variables.": "留空时使用 Application Support 中已安装的快速 MT 模型，或使用 LLMTOOLS_FASTMT_* 环境变量。",
        "Text translation engine": "文本翻译引擎",
        "Only Translate can use fast MT. Polish, summary, explanation, and TODO use their configured LLM models.": "只有“翻译”可以使用快速 MT。润色、总结、解释和待办使用各自配置的 LLM 模型。",
        "Subtitle engine": "字幕引擎",
        "Webpage engine": "网页引擎",
        "Subtitle translation engine": "字幕翻译引擎",
        "Webpage translation engine": "网页翻译引擎",
        "Subtitles can use LLM or the shared Fast MT runtime configured under Models.": "字幕可以使用 LLM，或使用在模型页配置的共享快速 MT 运行时。",
        "Webpage translation can use LLM or the shared Fast MT runtime configured under Models.": "网页翻译可以使用 LLM，或使用在模型页配置的共享快速 MT 运行时。",
        "Fallback policy": "失败策略",
        "When fallback is enabled, webpage translation uses the default LLM if fast MT is unavailable or does not support the language pair.": "启用回退时，如果快速机器翻译不可用或不支持当前语言对，网页翻译会继续使用默认 LLM。",
        "When fallback is enabled, any Fast MT route uses the normal LLM path if fast MT is unavailable or does not support the language pair.": "启用回退时，任意快速 MT 路径在运行时不可用或语言对不支持时都会改走常规 LLM 路径。",
        "Fast MT max concurrent batches": "快速机器翻译最大并发批次",
        "CTranslate2 command": "CTranslate2 命令",
        "Argos command": "Argos 命令",
        "Generic fast MT command": "通用快速机器翻译命令",
        "Use {python}, {sidecar}, {engine}, and {model_ct2}. Text task translation stays locked to LLM.": "可使用 {python}、{sidecar}、{engine} 和 {model_ct2}。文本任务翻译仍固定走 LLM。",
        "Use {python}, {sidecar}, {engine}, and {model_ct2}. These commands are used only by fast MT routes.": "可使用 {python}、{sidecar}、{engine} 和 {model_ct2}。这些命令只用于快速 MT 路径。",
        "Fixture mode uses LLMTOOLS_FAST_MT_FIXTURE_JSON for dependency-free checks.": "夹具模式使用 LLMTOOLS_FAST_MT_FIXTURE_JSON，可在无外部依赖时检查。",
        "Repairing fast translation runtime": "正在修复快速机器翻译运行时",
        "Fast translation runtime repaired": "快速机器翻译运行时已修复",
        "Fast translation runtime repair failed": "快速机器翻译运行时修复失败",
        "Installs or reuses the isolated CTranslate2 fast MT runtime, converts the default en-to-zh model, then smoke-tests the sidecar.": "安装或复用隔离的 CTranslate2 快速机器翻译运行时，转换默认英译中模型，并对 sidecar 做冒烟测试。",
        "Installs or reuses the isolated CTranslate2 fast MT runtime, converts the selected fast MT model, then smoke-tests the sidecar.": "安装或复用隔离的 CTranslate2 快速机器翻译运行时，转换当前选择的快速 MT 模型，并对 sidecar 做冒烟测试。",
        "Engine": "引擎",
        "Supported pairs": "支持语言对",
        "Default polish style": "默认润色风格",
        "Summary mode": "总结模式",
        "Explanation mode": "解释模式",
        "TODO mode": "待办模式",
        "Summary": "总结",
        "Explanation": "解释",
        "TODOs": "待办",
        "Recent history limit": "最近历史上限",
        "Hide source": "隐藏原文",
        "Show source": "显示原文",
        "Show Markdown source": "显示 Markdown 源码",
        "Show Markdown preview": "显示预览",
        "Show raw output": "显示原始输出",
        "Show result": "显示结果",
        "Detecting": "检测中...",
        "Key points": "关键要点",
        "Plain explanation": "通俗解释",
        "Action items": "行动项",
        "Paste text here, or drop a file onto the panel.": "在这里粘贴文本，也可以把文件拖到面板上。",
        "Paste text to translate.": "粘贴要翻译的文本。",
        "Paste text to polish.": "粘贴要润色的文本。",
        "Paste text to summarize.": "粘贴要总结的文本。",
        "Paste text to explain.": "粘贴要解释的文本。",
        "Paste text to extract TODOs.": "粘贴要提取待办的文本。",
        "Translation will appear here.": "译文会显示在这里。",
        "Polished text will appear here.": "润色结果会显示在这里。",
        "Summary will appear here.": "总结会显示在这里。",
        "Explanation will appear here.": "解释会显示在这里。",
        "TODOs will appear here.": "待办会显示在这里。",
        "The model returned an empty result. Try regenerate.": "模型返回了空结果，请重新生成。",
        "Drop text or paste here.": "拖入文本或粘贴到这里。",
        "Paste or type text": "粘贴或输入文本",
        "Captured selected text": "已读取选中文本",
        "Selected text is ready. Choose an action to send it to the remote provider.": "选中文本已就绪，请主动选择操作后再发送到远程 Provider。",
        "A global shortcut could not be registered. Choose a different shortcut.": "全局快捷键注册失败，请换一个未被占用的组合键。",
        "The previous shortcut set could not be restored.": "上一组快捷键也无法完整恢复。",
        "Selection too long": "选区过长",
        "Selected text is too long for automatic translation.": "选中的内容太长，已跳过自动翻译。",
        "Input is too long for the selected model.": "输入内容超过当前模型可处理长度，请缩短后再试。",
        "Enable Accessibility permission or paste text": "请启用辅助功能权限，或手动粘贴文本",
        "Ready": "就绪",
        "Starting": "启动中",
        "Status": "状态",
        "Added model": "已添加模型",
        "Failed to add model": "添加模型失败",
        "Failed to load file": "加载文件失败",
        "Loaded dropped text": "已载入拖入文本",
        "Please paste or type some text first.": "请先粘贴或输入文本。",
        "Failed": "失败",
        "Result copied; replacement unavailable": "结果已复制；无法替换原文",
        "Result pasted back": "结果已贴回原文",
        "Result copied": "结果已复制",
        "Replace original text requires Accessibility permission.": "替换原文需要辅助功能权限。",
        "Could not replace the original text from the current selection.": "无法替换当前选区中的原文。",
        "Launch at login needs approval in System Settings.": "登录时启动需要在系统设置中批准。",
        "Launch at login needs approval": "登录时启动需要批准",
        "Launch at login enabled": "已启用登录时启动",
        "Launch at login disabled": "已关闭登录时启动",
        "Launch at login update failed": "登录启动设置更新失败",
        "Launch at login could not be updated": "无法更新登录启动设置",
        "Launch at login could not be saved": "无法保存登录启动设置",
        "Loaded": "已加载",
        "Running": "正在运行",
        "Cancelled": "已取消",
        "Finished": "已完成",
        "finished": "已完成",
        "Open Quick Action": "打开快捷操作",
        "Open Floating Widget": "打开悬浮组件",
        "Quit": "退出"
    ]
}
