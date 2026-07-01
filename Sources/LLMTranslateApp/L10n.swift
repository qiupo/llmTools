import Foundation
import LLMTranslateCore

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
            default: return value
            }
        case .chinese:
            switch value {
            case "auto": return "自动"
            case "Chinese": return "中文"
            case "English": return "英文"
            case "Japanese": return "日文"
            case "Korean": return "韩文"
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
        "Selection": "划词",
        "Global shortcuts": "全局快捷键",
        "Open Quick Action without selected text": "打开快捷操作（不读取选中文本）",
        "Press shortcut": "按下快捷键",
        "Change shortcut": "修改快捷键",
        "Reset shortcut": "恢复默认快捷键",
        "Shortcut is already assigned": "快捷键已被占用",
        "Use Command, Option, or Control with a key": "请使用 Command、Option 或 Control 加一个按键",
        "Webpage": "网页",
        "Browser": "浏览器",
        "Extension folder": "扩展文件夹",
        "Default model": "默认模型",
        "History": "历史",
        "Application": "应用",
        "Version": "版本",
        "Data": "数据",
        "Open Data Folder": "打开数据文件夹",
        "Quit llmTranslate": "退出 llmTranslate",
        "Models": "模型",
        "Models & Settings": "模型与设置",
        "Settings": "设置",
        "Preferences": "偏好设置",
        "Defaults": "默认值",
        "Web Page Translation": "网页翻译",
        "Enable webpage translation": "启用网页翻译",
        "Translation model": "翻译模型",
        "Use default model": "跟随默认模型",
        "Pending translation style": "待翻译样式",
        "Repair Chrome Bridge": "修复 Chrome 桥接",
        "Open Chrome Extensions": "打开 Chrome 扩展",
        "Chrome bridge repaired": "Chrome 桥接已修复",
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
        "App language": "应用语言",
        "Default translation target": "默认翻译目标",
        "Default polish style": "默认润色风格",
        "Recent history limit": "最近历史上限",
        "Hide source": "隐藏原文",
        "Show source": "显示原文",
        "Show raw output": "显示原始输出",
        "Show result": "显示结果",
        "Detecting": "检测中...",
        "Auto detect": "自动检测",
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
        "finished": "已完成",
        "Open Quick Action": "打开快捷操作",
        "Open Floating Widget": "打开悬浮组件",
        "Quit": "退出"
    ]
}
