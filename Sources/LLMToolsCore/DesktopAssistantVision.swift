import Foundation

/// 截图只在内存中短暂经过视觉模型，进入上下文的只有这份受限摘要。
public struct AssistantSceneSummary: Codable, Sendable, Hashable {
    public var activity: String
    public var observation: String
    public var visibleText: [String]
    public var signal: String
    public var confidence: Double

    public init(
        activity: String,
        observation: String,
        visibleText: [String] = [],
        signal: String = "none",
        confidence: Double
    ) {
        self.activity = String(activity.prefix(32)).trimmingCharacters(in: .whitespacesAndNewlines)
        self.observation = String(observation.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
        self.visibleText = visibleText
            .map { String($0.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
        self.signal = String(signal.prefix(24)).trimmingCharacters(in: .whitespacesAndNewlines)
        self.confidence = min(max(confidence, 0), 1)
    }

    public var contextText: String {
        var parts = [
            "activity=\(activity)",
            "signal=\(signal)",
            "observation=\(observation)"
        ]
        if !visibleText.isEmpty {
            parts.append("visibleText=\(visibleText.joined(separator: " | "))")
        }
        return parts.joined(separator: "; ")
    }

    public var isUsable: Bool {
        confidence >= 0.55 && !activity.isEmpty && !observation.isEmpty
    }
}

public enum AssistantSceneContract {
    public static let promptVersion = 1
    public static let systemPrompt = """
    Describe only what is visibly present in the supplied desktop-window image. Return exactly one JSON object and no Markdown. Use exactly these keys: activity (short category such as coding, reading, chat, form, media, unknown), observation (one concrete sentence, maximum 180 characters), visibleText (array of at most three short exact snippets), signal (one of none, blocked, deadline, waiting, success, confusion, fatigue), confidence (number 0...1). Do not infer off-screen state, private identity, intent, or unseen application data. If uncertain, use activity=unknown, signal=none, and a cautious observation.
    """

    public static func parse(_ text: String) -> AssistantSceneSummary? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else { return nil }
        let objectText = String(value[start...end])
        guard let data = objectText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["activity", "observation", "visibleText", "signal", "confidence"]),
              let activity = object["activity"] as? String,
              let observation = object["observation"] as? String,
              let visibleText = object["visibleText"] as? [String],
              let signal = object["signal"] as? String,
              let confidence = object["confidence"] as? Double else { return nil }
        let allowedSignals = Set(["none", "blocked", "deadline", "waiting", "success", "confusion", "fatigue"])
        guard allowedSignals.contains(signal),
              confidence.isFinite,
              !AssistantPrivacyPolicy.looksSensitive(observation),
              visibleText.allSatisfy({ !AssistantPrivacyPolicy.looksSensitive($0) }) else { return nil }
        let summary = AssistantSceneSummary(
            activity: activity,
            observation: observation,
            visibleText: visibleText,
            signal: signal,
            confidence: confidence
        )
        return summary.isUsable ? summary : nil
    }
}
