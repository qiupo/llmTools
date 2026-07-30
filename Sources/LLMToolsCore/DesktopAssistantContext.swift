import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum AssistantActivityType: String, Codable, Sendable, CaseIterable, Hashable {
    case applicationActivated
    case windowContextChanged
    case clipboardChanged
    case selectionCaptured
    case fileDropped
    case foreignTextDetected
    case taskFailed
}

public enum AssistantContentType: String, Codable, Sendable, CaseIterable, Hashable {
    case metadata
    case text
    case url
    case file
    case image
    case media
}

public enum AssistantDropKind: String, Sendable, Hashable {
    case text
    case textFile
    case image
    case media
    case url
    case unsupported
    case multipleItems
}

public enum AssistantDropPayload: Sendable, Hashable {
    case text(String)
    case file(URL, AssistantDropKind)
    case url(URL)
}

public struct AssistantDropClassification: Sendable, Hashable {
    public var kind: AssistantDropKind
    public var payload: AssistantDropPayload?
    public var displayName: String?

    public init(kind: AssistantDropKind, payload: AssistantDropPayload?, displayName: String? = nil) {
        self.kind = kind
        self.payload = payload
        self.displayName = displayName
    }

    public var isSupported: Bool {
        payload != nil && kind != .unsupported && kind != .multipleItems
    }
}

public enum AssistantDropClassifier {
    public static func classify(text: String) -> AssistantDropClassification {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return AssistantDropClassification(kind: .unsupported, payload: nil)
        }
        if AssistantPrivacyPolicy.looksLikeURL(value),
           let url = URL(string: value),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return AssistantDropClassification(kind: .url, payload: .url(url), displayName: url.host)
        }
        return AssistantDropClassification(kind: .text, payload: .text(value))
    }

    public static func classify(fileURL: URL) -> AssistantDropClassification {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return AssistantDropClassification(kind: .unsupported, payload: nil, displayName: fileURL.lastPathComponent)
        }
        let type = UTType(filenameExtension: fileURL.pathExtension)
        let kind: AssistantDropKind
        if ["txt", "md", "markdown"].contains(fileURL.pathExtension.lowercased()) {
            kind = .textFile
        } else if type?.conforms(to: .image) == true {
            kind = .image
        } else if type?.conforms(to: .audio) == true
                    || type?.conforms(to: .movie) == true
                    || type?.conforms(to: .video) == true {
            kind = .media
        } else {
            return AssistantDropClassification(kind: .unsupported, payload: nil, displayName: fileURL.lastPathComponent)
        }
        return AssistantDropClassification(
            kind: kind,
            payload: .file(fileURL, kind),
            displayName: fileURL.lastPathComponent
        )
    }

    public static var multipleItems: AssistantDropClassification {
        AssistantDropClassification(kind: .multipleItems, payload: nil)
    }
}

public enum AssistantClipboardObservationKind: String, Sendable, Hashable {
    case plainText
    case file
    case image
    case richText
    case other
}

public enum AssistantClipboardClassifier {
    public static func classify(typeIdentifiers: [String]) -> AssistantClipboardObservationKind {
        let types = typeIdentifiers.map { $0.lowercased() }
        func contains(_ fragments: [String]) -> Bool {
            types.contains { type in fragments.contains(where: type.contains) }
        }
        if contains(["file-url", "filepromise", "file promise", "urlnodedata", "pdf"]) { return .file }
        if contains(["image", "png", "tiff", "jpeg", "heic"]) { return .image }
        if contains(["rtf", "rtfd", "webarchive"]) { return .richText }
        if contains(["public.utf8-plain-text", "public.utf16-plain-text", "public.plain-text", "public.text", "string"]) {
            return .plainText
        }
        // 浏览器通常同时提供 HTML 和标准纯文本表示；这里只读取纯文本表示，不解析 HTML。
        if contains(["html"]) { return .richText }
        return .other
    }
}

public struct AssistantActivityEvent: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var occurredAt: Date
    public var firstOccurredAt: Date
    public var type: AssistantActivityType
    public var source: AssistantSource
    public var appIdentity: String?
    public var contentType: AssistantContentType?
    public var sanitizedSummary: String?
    public var contentFingerprint: String?
    public var sensitivity: AssistantSensitivity
    public var confidence: Double
    public var occurrenceCount: Int
    public var ephemeralContextReference: UUID?
    public var expiresAt: Date

    public init(
        id: UUID = UUID(),
        occurredAt: Date = .now,
        firstOccurredAt: Date? = nil,
        type: AssistantActivityType,
        source: AssistantSource,
        appIdentity: String? = nil,
        contentType: AssistantContentType? = nil,
        sanitizedSummary: String? = nil,
        contentFingerprint: String? = nil,
        sensitivity: AssistantSensitivity = .normal,
        confidence: Double = 1,
        occurrenceCount: Int = 1,
        ephemeralContextReference: UUID? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.firstOccurredAt = firstOccurredAt ?? occurredAt
        self.type = type
        self.source = source
        self.appIdentity = appIdentity
        self.contentType = contentType
        self.sanitizedSummary = sanitizedSummary
        self.contentFingerprint = contentFingerprint
        self.sensitivity = sensitivity
        self.confidence = min(max(confidence, 0), 1)
        self.occurrenceCount = max(1, occurrenceCount)
        self.ephemeralContextReference = ephemeralContextReference
        self.expiresAt = expiresAt ?? occurredAt.addingTimeInterval(60 * 60)
    }
}

public actor AssistantContextBuffer {
    public static let eventTTL: TimeInterval = 60 * 60
    public static let rawContextTTL: TimeInterval = 10 * 60
    public static let maximumEventCount = 2_000
    public static let maximumClipboardTextLength = 12_000

    private struct RawContext: Sendable {
        var source: AssistantSource
        var text: String
        var expiresAt: Date
    }

    private var events: [AssistantActivityEvent] = []
    private var rawContexts: [UUID: RawContext] = [:]
    private var epoch: UInt64 = 0

    public init() {}

    @discardableResult
    public func append(
        _ incoming: AssistantActivityEvent,
        rawText: String? = nil,
        now: Date = .now
    ) -> AssistantActivityEvent {
        prune(now: now)
        var event = incoming
        event.expiresAt = min(event.expiresAt, event.occurredAt.addingTimeInterval(Self.eventTTL))

        let raw = rawText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if event.sensitivity == .normal,
           let raw,
           !raw.isEmpty,
           raw.count <= Self.maximumClipboardTextLength {
            let reference = UUID()
            rawContexts[reference] = RawContext(
                source: event.source,
                text: raw,
                expiresAt: event.occurredAt.addingTimeInterval(Self.rawContextTTL)
            )
            event.ephemeralContextReference = reference
        } else {
            event.ephemeralContextReference = nil
            if event.sensitivity == .normal,
               let raw,
               raw.count > Self.maximumClipboardTextLength {
                // 超长正文只保留清洗后的首尾摘要；完整原文永不进入短期 raw context。
                event.sanitizedSummary = AssistantPrivacyPolicy().sanitizeOversizedContextSummary(raw)
            }
        }

        // 同来源、同应用、同指纹只累计次数，避免剪贴板轮询或重复回调挤满队列。
        if let fingerprint = event.contentFingerprint,
           let index = events.lastIndex(where: {
               $0.type == event.type
                   && $0.source == event.source
                   && $0.appIdentity == event.appIdentity
                   && $0.contentFingerprint == fingerprint
           }) {
            if let oldReference = events[index].ephemeralContextReference,
               oldReference != event.ephemeralContextReference {
                rawContexts.removeValue(forKey: oldReference)
            }
            events[index].occurredAt = max(events[index].occurredAt, event.occurredAt)
            events[index].expiresAt = event.expiresAt
            events[index].confidence = max(events[index].confidence, event.confidence)
            events[index].occurrenceCount += event.occurrenceCount
            events[index].ephemeralContextReference = event.ephemeralContextReference
            return events[index]
        }

        events.append(event)
        if events.count > Self.maximumEventCount {
            let removalCount = events.count - Self.maximumEventCount
            let removed = events.prefix(removalCount)
            for event in removed {
                if let reference = event.ephemeralContextReference {
                    rawContexts.removeValue(forKey: reference)
                }
            }
            events.removeFirst(removalCount)
        }
        return event
    }

    public func appendIfCurrent(
        _ incoming: AssistantActivityEvent,
        rawText: String? = nil,
        expectedEpoch: UInt64,
        now: Date = .now
    ) -> AssistantActivityEvent? {
        guard expectedEpoch == epoch else { return nil }
        return append(incoming, rawText: rawText, now: now)
    }

    public func snapshot(now: Date = .now) -> [AssistantActivityEvent] {
        prune(now: now)
        return events.sorted { $0.occurredAt < $1.occurredAt }
    }

    public func rawText(for reference: UUID?, now: Date = .now) -> String? {
        prune(now: now)
        guard let reference else { return nil }
        return rawContexts[reference]?.text
    }

    public func rawTexts(for references: [UUID], now: Date = .now) -> [String] {
        prune(now: now)
        return references.compactMap { rawContexts[$0]?.text }
    }

    public func clear(source: AssistantSource? = nil) {
        guard let source else {
            events.removeAll()
            rawContexts.removeAll()
            return
        }
        events.removeAll { event in
            guard event.source == source else { return false }
            if let reference = event.ephemeralContextReference {
                rawContexts.removeValue(forKey: reference)
            }
            return true
        }
        rawContexts = rawContexts.filter { $0.value.source != source }
    }

    public func clear(appIdentity: String) {
        events.removeAll { event in
            guard event.appIdentity?.caseInsensitiveCompare(appIdentity) == .orderedSame else { return false }
            if let reference = event.ephemeralContextReference {
                rawContexts.removeValue(forKey: reference)
            }
            return true
        }
    }

    public func advanceEpochAndClear(
        to newEpoch: UInt64,
        source: AssistantSource? = nil,
        appIdentity: String? = nil
    ) {
        // 多个撤销请求可能乱序到达 actor；epoch 只前进，但每个指定清理都必须执行。
        epoch = max(epoch, newEpoch)
        if let appIdentity {
            clear(appIdentity: appIdentity)
        } else {
            clear(source: source)
        }
    }

    private func prune(now: Date) {
        let oldest = now.addingTimeInterval(-Self.eventTTL)
        events.removeAll { event in
            let expired = event.occurredAt < oldest || event.expiresAt <= now
            if expired, let reference = event.ephemeralContextReference {
                rawContexts.removeValue(forKey: reference)
            }
            return expired
        }
        rawContexts = rawContexts.filter { $0.value.expiresAt > now }
    }
}

public struct AssistantPrivacyPolicy: Sendable {
    public var excludedApplicationBundleIDs: Set<String>

    public init(excludedApplicationBundleIDs: [String] = DesktopAssistantPreferences.defaultExcludedApplicationBundleIDs) {
        self.excludedApplicationBundleIDs = Set(excludedApplicationBundleIDs.map { $0.lowercased() })
    }

    public func sensitivity(text: String?, bundleID: String?) -> AssistantSensitivity {
        if let bundleID, excludedApplicationBundleIDs.contains(bundleID.lowercased()) {
            return .excludedApplication
        }
        if let text, Self.looksSensitive(text) {
            return .sensitive
        }
        return .normal
    }

    public func sanitizeWindowTitle(_ title: String) -> String? {
        var value = title.precomposedStringWithCanonicalMapping
        value = Self.replacing(#"(?i)file://\S+|/(?:Users|private|tmp|var)/\S+"#, in: value, with: "[path]")
        value = Self.replacing(#"(?i)https?://([^\s/?#]+)[^\s]*"#, in: value, with: "$1")
        value = Self.replacing(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: value, with: "[email]")
        value = Self.replacing(#"\b\d{7,}\b"#, in: value, with: "[number]")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !Self.looksSensitive(value) else { return nil }
        return String(value.prefix(160))
    }

    public func sanitizeEvidenceSummary(_ summary: String?) -> String? {
        guard let summary else { return nil }
        return sanitizedText(summary, maximumLength: 240, preserveBothEnds: false)
    }

    public func sanitizeModelEvidence(_ text: String) -> String? {
        // 模型证据只在 10 分钟内存中使用；长文本保留首尾，避免把单纯原文前缀写进持久化摘要。
        guard !Self.looksSensitive(text) else { return nil }
        return sanitizedText(text, maximumLength: 1_200, preserveBothEnds: true)
    }

    public func sanitizeOversizedContextSummary(_ text: String) -> String? {
        guard !Self.looksSensitive(text) else { return nil }
        return sanitizedText(text, maximumLength: 240, preserveBothEnds: true)
    }

    private func sanitizedText(
        _ text: String,
        maximumLength: Int,
        preserveBothEnds: Bool
    ) -> String? {
        var value = text.precomposedStringWithCanonicalMapping
        value = Self.replacing(#"-----BEGIN[\s\S]*?PRIVATE KEY-----"#, in: value, with: "[sensitive]")
        value = Self.replacing(#"(?i)\b(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{12,}|xox[baprs]-[A-Za-z0-9-]{10,})\b"#, in: value, with: "[sensitive]")
        value = Self.replacing(#"(?i)\b(api[_-]?key|token|password|passwd|secret|验证码|密码)\b\s*[:=]?\s*\S+"#, in: value, with: "$1 [redacted]")
        value = Self.replacing(#"(?i)file://\S+|/(?:Users|private|tmp|var)/\S+"#, in: value, with: "[path]")
        value = Self.replacing(#"(?i)(https?://[^\s?#]+)[?#][^\s]*"#, in: value, with: "$1")
        value = Self.replacing(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: value, with: "[email]")
        value = Self.replacing(#"\b\d{7,}\b"#, in: value, with: "[number]")
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !Self.looksSensitive(value) else { return nil }
        guard value.count > maximumLength, preserveBothEnds else {
            return String(value.prefix(maximumLength))
        }
        let separator = " ... "
        let availableLength = max(2, maximumLength - separator.count)
        let prefixLength = availableLength / 2
        let suffixLength = availableLength - prefixLength
        return "\(value.prefix(prefixLength))\(separator)\(value.suffix(suffixLength))"
    }

    public static func appCategory(for bundleID: String) -> String {
        let value = bundleID.lowercased()
        if value.contains("xcode") || value.contains("vscode") || value.contains("terminal") || value.contains("iterm") {
            return "development"
        }
        if value.contains("safari") || value.contains("chrome") || value.contains("firefox") || value.contains("browser") {
            return "browser"
        }
        if value.contains("mail") || value.contains("outlook") || value.contains("calendar") {
            return "communication"
        }
        if value.contains("pages") || value.contains("word") || value.contains("notion") || value.contains("notes") {
            return "productivity"
        }
        return "other"
    }

    public static func normalizedFingerprintText(_ text: String, removeErrorNoise: Bool = false) -> String {
        var value = text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if removeErrorNoise {
            value = replacing(#"(?m)^\s*\[?\d{2}:\d{2}:\d{2}(?:\.\d+)?\]?\s*"#, in: value, with: "")
            value = replacing(#"(?i)/(?:Users|private|tmp|var)/[^\s:]+"#, in: value, with: "[path]")
            value = replacing(#"(?i)\bline\s+\d+\b|:\d+(?::\d+)?\b"#, in: value, with: "[line]")
        }
        return value
    }

    public static func looksLikeURL(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: { $0.isWhitespace }) else { return false }
        return URL(string: value).flatMap { $0.scheme } != nil
    }

    public static func containsWebURL(_ text: String) -> Bool {
        // 拖入分类仍要求整段 URL；模型证据则必须否决夹在正文中的链接，避免把网页内容当成本地已知事实。
        text.range(
            of: #"(?i)(?:https?://|www\.)[^\s<>\"']+"#,
            options: .regularExpression
        ) != nil
    }

    public static func looksLikeCode(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let symbols = value.filter { "{}[]();=<>".contains($0) }.count
        return value.contains("```")
            || value.hasPrefix("#!")
            || value.contains("func ")
            || value.contains("class ")
            || value.contains("const ")
            || symbols >= max(6, value.count / 8)
    }

    public static func looksSensitive(_ text: String) -> Bool {
        let patterns = [
            #"-----BEGIN[\s\S]*?PRIVATE KEY-----"#,
            #"(?i)\b(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{12,}|xox[baprs]-[A-Za-z0-9-]{10,})\b"#,
            #"(?i)\b(api[_-]?key|access[_-]?token|token|password|passwd|secret|验证码|密码)\b\s*[:=]\s*\S+"#,
            #"(?i)\b(?:otp|验证码|verification code)\D{0,8}\d{4,8}\b"#,
            #"\b(?:\d[ -]?){16,19}\b"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
    }
}

public actor AssistantFingerprintStore {
    private let fileURL: URL
    private var cachedKey: SymmetricKey?

    public init(fileURL: URL = AppPaths.assistantFingerprintKeyFileURL) {
        self.fileURL = fileURL
    }

    public func fingerprint(text: String, removeErrorNoise: Bool = false) throws -> String {
        let normalized = AssistantPrivacyPolicy.normalizedFingerprintText(text, removeErrorNoise: removeErrorNoise)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(normalized.utf8), using: try key())
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    public func ensureKey() throws {
        _ = try key()
    }

    @discardableResult
    public func rotate() throws -> String {
        cachedKey = nil
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        return try fingerprint(text: "assistant-key-verification")
    }

    private func key() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        try AppPaths.preparePrivateFileStorage(at: fileURL)
        let key: SymmetricKey
        if FileManager.default.fileExists(atPath: fileURL.path) {
            key = SymmetricKey(data: try Data(contentsOf: fileURL))
        } else {
            key = SymmetricKey(size: .bits256)
            let data = key.withUnsafeBytes { Data($0) }
            try data.write(to: fileURL, options: .atomic)
            try AppPaths.hardenPrivateFile(at: fileURL)
        }
        cachedKey = key
        return key
    }
}

public enum AssistantBehaviorOutcome: String, Codable, Sendable, CaseIterable, Hashable {
    case suppressed
    case badged
    case presented
    case viewed
    case acted
    case dismissed
}

public enum AssistantSuppressionReason: String, Codable, Sendable, CaseIterable, Hashable {
    case sensitiveContent
}

public struct AssistantBehaviorRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var occurredAt: Date
    public var patternType: AssistantPatternType?
    public var sourceTypes: [AssistantSource]
    public var appIdentity: String?
    public var appCategory: String?
    public var evidenceFeatures: [String: Double]
    public var sanitizedEvidenceSummary: String?
    public var contentFingerprint: String?
    public var sensitivity: AssistantSensitivity
    public var assistantDecision: AssistantPresentation
    public var judgmentModelID: UUID?
    public var judgmentConfidence: Double?
    public var presentationResult: AssistantBehaviorOutcome
    public var userFeedback: AssistantFeedback?
    public var selectedActionID: AssistantActionID?
    public var actionSucceeded: Bool?
    public var expiresAt: Date?
    public var suppressionReason: AssistantSuppressionReason?

    public init(
        id: UUID = UUID(),
        occurredAt: Date = .now,
        patternType: AssistantPatternType?,
        sourceTypes: [AssistantSource],
        appIdentity: String? = nil,
        appCategory: String? = nil,
        evidenceFeatures: [String: Double] = [:],
        sanitizedEvidenceSummary: String? = nil,
        contentFingerprint: String? = nil,
        sensitivity: AssistantSensitivity = .normal,
        assistantDecision: AssistantPresentation,
        judgmentModelID: UUID? = nil,
        judgmentConfidence: Double? = nil,
        presentationResult: AssistantBehaviorOutcome,
        userFeedback: AssistantFeedback? = nil,
        selectedActionID: AssistantActionID? = nil,
        actionSucceeded: Bool? = nil,
        expiresAt: Date? = nil,
        suppressionReason: AssistantSuppressionReason? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.patternType = patternType
        self.sourceTypes = Array(Set(sourceTypes)).sorted { $0.rawValue < $1.rawValue }
        self.appIdentity = appIdentity
        self.appCategory = appCategory
        self.evidenceFeatures = evidenceFeatures
        self.sanitizedEvidenceSummary = sanitizedEvidenceSummary
        self.contentFingerprint = contentFingerprint
        self.sensitivity = sensitivity
        self.assistantDecision = assistantDecision
        self.judgmentModelID = judgmentModelID
        self.judgmentConfidence = judgmentConfidence.map { min(max($0, 0), 1) }
        self.presentationResult = presentationResult
        self.userFeedback = userFeedback
        self.selectedActionID = selectedActionID
        self.actionSucceeded = actionSucceeded
        self.expiresAt = expiresAt
        self.suppressionReason = suppressionReason
    }
}

public struct AssistantPatternAggregate: Codable, Sendable, Hashable {
    public var detectedCount: Int
    public var presentedCount: Int
    public var actedCount: Int
    public var irrelevantCount: Int
    public var unfunnyCount: Int

    public init(
        detectedCount: Int = 0,
        presentedCount: Int = 0,
        actedCount: Int = 0,
        irrelevantCount: Int = 0,
        unfunnyCount: Int = 0
    ) {
        self.detectedCount = detectedCount
        self.presentedCount = presentedCount
        self.actedCount = actedCount
        self.irrelevantCount = irrelevantCount
        self.unfunnyCount = unfunnyCount
    }
}

public struct AssistantBehaviorSnapshot: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var records: [AssistantBehaviorRecord]
    public var aggregatePreferences: [AssistantPatternType: AssistantPatternAggregate]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = AssistantBehaviorStore.currentSchemaVersion,
        records: [AssistantBehaviorRecord] = [],
        aggregatePreferences: [AssistantPatternType: AssistantPatternAggregate] = [:],
        updatedAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
        self.aggregatePreferences = aggregatePreferences
        self.updatedAt = updatedAt
    }
}

public enum AssistantBehaviorStoreStatus: String, Codable, Sendable, Hashable {
    case ready
    case recoveredFromCorruption
    case futureSchemaReadOnly
    case saveFailed
}

public struct AssistantBehaviorStoreSummary: Sendable, Hashable {
    public var status: AssistantBehaviorStoreStatus
    public var recordCount: Int
    public var earliestDate: Date?
    public var latestDate: Date?
    public var byteCount: Int
    public var schemaVersion: Int
    public var patternCounts: [AssistantPatternType: Int]

    public init(
        status: AssistantBehaviorStoreStatus,
        recordCount: Int,
        earliestDate: Date?,
        latestDate: Date?,
        byteCount: Int,
        schemaVersion: Int,
        patternCounts: [AssistantPatternType: Int] = [:]
    ) {
        self.status = status
        self.recordCount = recordCount
        self.earliestDate = earliestDate
        self.latestDate = latestDate
        self.byteCount = byteCount
        self.schemaVersion = schemaVersion
        self.patternCounts = patternCounts
    }
}

public actor AssistantBehaviorStore {
    public static let currentSchemaVersion = 1
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    public static let maximumRecordCount = 5_000
    public static let maximumByteCount = 10 * 1_024 * 1_024

    private struct SnapshotHeader: Decodable {
        var schemaVersion: Int
    }

    private let fileURL: URL
    private let fingerprintStore: AssistantFingerprintStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var snapshot = AssistantBehaviorSnapshot()
    private var status: AssistantBehaviorStoreStatus = .ready
    private var isReadOnly = false
    private var lastEncodedByteCount = 0
    private var loadedSchemaVersion = AssistantBehaviorStore.currentSchemaVersion

    public init(
        fileURL: URL = AppPaths.assistantBehaviorFileURL,
        fingerprintStore: AssistantFingerprintStore? = nil
    ) {
        self.fileURL = fileURL
        self.fingerprintStore = fingerprintStore ?? AssistantFingerprintStore()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    @discardableResult
    public func load(now: Date = .now) -> AssistantBehaviorSnapshot {
        do {
            try AppPaths.preparePrivateFileStorage(at: fileURL)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                snapshot = AssistantBehaviorSnapshot(updatedAt: now)
                status = .ready
                lastEncodedByteCount = 0
                loadedSchemaVersion = Self.currentSchemaVersion
                return snapshot
            }
            let data = try Data(contentsOf: fileURL)
            let header = try decoder.decode(SnapshotHeader.self, from: data)
            guard header.schemaVersion <= Self.currentSchemaVersion else {
                snapshot = AssistantBehaviorSnapshot(updatedAt: now)
                status = .futureSchemaReadOnly
                isReadOnly = true
                lastEncodedByteCount = data.count
                loadedSchemaVersion = header.schemaVersion
                return snapshot
            }
            snapshot = try decoder.decode(AssistantBehaviorSnapshot.self, from: data)
            let recordsBeforePruning = snapshot.records
            snapshot.records = prunedRecords(snapshot.records, now: now)
            status = .ready
            isReadOnly = false
            lastEncodedByteCount = data.count
            loadedSchemaVersion = snapshot.schemaVersion
            if snapshot.records != recordsBeforePruning || data.count > Self.maximumByteCount {
                _ = save(now: now)
            }
            return snapshot
        } catch {
            quarantineCorruptFile()
            snapshot = AssistantBehaviorSnapshot(updatedAt: now)
            status = .recoveredFromCorruption
            isReadOnly = false
            lastEncodedByteCount = 0
            loadedSchemaVersion = Self.currentSchemaVersion
            return snapshot
        }
    }

    @discardableResult
    public func append(_ input: AssistantBehaviorRecord, now: Date = .now) -> Bool {
        guard !isReadOnly, input.sensitivity != .excludedApplication else { return false }
        var record = input
        record.sourceTypes = Array(Set(record.sourceTypes)).sorted { $0.rawValue < $1.rawValue }
        record.sanitizedEvidenceSummary = AssistantPrivacyPolicy().sanitizeEvidenceSummary(record.sanitizedEvidenceSummary)
        record.appIdentity = Self.validBundleID(record.appIdentity)
        record.appCategory = record.appCategory.map { String($0.prefix(64)) }
        record.evidenceFeatures = Dictionary(
            uniqueKeysWithValues: record.evidenceFeatures
                .filter { !$0.key.isEmpty && $0.key.count <= 64 && $0.value.isFinite }
                .sorted { $0.key < $1.key }
                .prefix(16)
                .map { ($0.key, $0.value) }
        )
        if record.sensitivity == .sensitive {
            record.patternType = nil
            record.sourceTypes = []
            record.appIdentity = nil
            record.appCategory = nil
            record.evidenceFeatures = [:]
            record.sanitizedEvidenceSummary = nil
            record.contentFingerprint = nil
            record.assistantDecision = .silent
            record.judgmentModelID = nil
            record.judgmentConfidence = nil
            record.presentationResult = .suppressed
            record.userFeedback = nil
            record.selectedActionID = nil
            record.actionSucceeded = nil
            record.suppressionReason = .sensitiveContent
        }
        if let existing = snapshot.records.first(where: { $0.id == record.id }) {
            updateAggregate(for: existing, delta: -1)
        }
        snapshot.records.removeAll { $0.id == record.id }
        snapshot.records.append(record)
        updateAggregate(for: record)
        snapshot.updatedAt = now
        return save(now: now)
    }

    @discardableResult
    public func update(
        id: UUID,
        feedback: AssistantFeedback? = nil,
        outcome: AssistantBehaviorOutcome? = nil,
        selectedActionID: AssistantActionID? = nil,
        actionSucceeded: Bool? = nil,
        now: Date = .now
    ) -> Bool {
        guard !isReadOnly, let index = snapshot.records.firstIndex(where: { $0.id == id }) else { return false }
        let previous = snapshot.records[index]
        if let feedback { snapshot.records[index].userFeedback = feedback }
        if let outcome { snapshot.records[index].presentationResult = outcome }
        if let selectedActionID { snapshot.records[index].selectedActionID = selectedActionID }
        if let actionSucceeded { snapshot.records[index].actionSucceeded = actionSucceeded }
        // 长期聚合不能从仅保留 30 天的明细重建；只替换当前记录的统计贡献。
        updateAggregate(for: previous, delta: -1)
        updateAggregate(for: snapshot.records[index])
        snapshot.updatedAt = now
        return save(now: now)
    }

    public func records(
        pattern: AssistantPatternType? = nil,
        source: AssistantSource? = nil,
        appCategory: String? = nil,
        limit: Int = 5,
        now: Date = .now
    ) -> [AssistantBehaviorRecord] {
        let currentRecords = pruneDetailedRecordsIfNeeded(now: now)
        return currentRecords
            .filter { pattern == nil || $0.patternType == pattern }
            .filter { record in source.map(record.sourceTypes.contains) ?? true }
            .filter { record in appCategory.map { record.appCategory == $0 } ?? true }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(max(0, min(limit, 5)))
            .map { $0 }
    }

    public func summary(now: Date = .now) -> AssistantBehaviorStoreSummary {
        let currentRecords = pruneDetailedRecordsIfNeeded(now: now)
        let dates = currentRecords.map(\.occurredAt)
        let patternCounts = Dictionary(grouping: currentRecords.compactMap(\.patternType), by: { $0 })
            .mapValues(\.count)
        return AssistantBehaviorStoreSummary(
            status: status,
            recordCount: currentRecords.count,
            earliestDate: dates.min(),
            latestDate: dates.max(),
            byteCount: lastEncodedByteCount,
            schemaVersion: loadedSchemaVersion,
            patternCounts: patternCounts
        )
    }

    public func aggregate(for pattern: AssistantPatternType) -> AssistantPatternAggregate {
        snapshot.aggregatePreferences[pattern] ?? AssistantPatternAggregate()
    }

    @discardableResult
    public func clearDetailedRecords(clearAggregatePreferences: Bool, now: Date = .now) async -> Bool {
        guard !isReadOnly else { return false }
        snapshot.records.removeAll()
        var operationSucceeded = true
        if clearAggregatePreferences {
            snapshot.aggregatePreferences.removeAll()
            do {
                _ = try await fingerprintStore.rotate()
            } catch {
                // 明细删除仍会提交，但密钥轮换失败必须让设置页看到失败状态。
                operationSucceeded = false
            }
        }
        snapshot.updatedAt = now
        guard save(now: now) else { return false }
        do {
            try removeQuarantineFiles()
        } catch {
            status = .saveFailed
            return false
        }
        if !operationSucceeded {
            status = .saveFailed
        }
        return operationSucceeded
    }

    @discardableResult
    public func clearDetailedRecords(source: AssistantSource, now: Date = .now) -> Bool {
        guard !isReadOnly else { return false }
        snapshot.records.removeAll {
            $0.sourceTypes.contains(source)
                || (source == .foregroundApplication && $0.appIdentity != nil)
        }
        // 与“仅删除详细记录”一致，来源清除不隐式重置长期聚合偏好。
        snapshot.updatedAt = now
        guard save(now: now) else { return false }
        do {
            try removeQuarantineFiles()
            return true
        } catch {
            status = .saveFailed
            return false
        }
    }

    @discardableResult
    public func deleteAllFilesAndRotateKey(now: Date = .now) async -> Bool {
        // 先清空 actor 内的旧快照；密钥轮换发生重入时，任何旧记录 update 都只能失败。
        snapshot = AssistantBehaviorSnapshot(updatedAt: now)
        isReadOnly = false
        status = .ready
        lastEncodedByteCount = 0
        loadedSchemaVersion = Self.currentSchemaVersion
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try removeQuarantineFiles()
            _ = try await fingerprintStore.rotate()
            // 轮换 await 期间即使出现并发写入，完成删除时也不能留下旧磁盘内容。
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try removeQuarantineFiles()
            snapshot = AssistantBehaviorSnapshot(updatedAt: now)
            lastEncodedByteCount = 0
            return true
        } catch {
            status = .saveFailed
            return false
        }
    }

    private func save(now: Date) -> Bool {
        guard !isReadOnly else { return false }
        snapshot.records = prunedRecords(snapshot.records, now: now)
        snapshot.schemaVersion = Self.currentSchemaVersion
        loadedSchemaVersion = Self.currentSchemaVersion
        snapshot.updatedAt = now
        do {
            var data = try encoder.encode(snapshot)
            // 记录上限很小；按编码后占比批量删除最老记录即可满足 10MB，不引入数据库索引。
            while data.count > Self.maximumByteCount, !snapshot.records.isEmpty {
                let overflowRatio = 1 - (Double(Self.maximumByteCount) / Double(data.count))
                let removalCount = max(1, Int(ceil(Double(snapshot.records.count) * overflowRatio)))
                snapshot.records.removeFirst(min(removalCount, snapshot.records.count))
                data = try encoder.encode(snapshot)
            }
            try AppPaths.preparePrivateFileStorage(at: fileURL)
            try data.write(to: fileURL, options: .atomic)
            try AppPaths.hardenPrivateFile(at: fileURL)
            lastEncodedByteCount = data.count
            status = .ready
            return true
        } catch {
            // 写入失败时保留内存快照；下一次 append/update 会再次尝试保存。
            status = .saveFailed
            return false
        }
    }

    private func prunedRecords(_ records: [AssistantBehaviorRecord], now: Date) -> [AssistantBehaviorRecord] {
        let oldest = now.addingTimeInterval(-Self.retentionInterval)
        return records
            .filter { $0.occurredAt >= oldest && ($0.expiresAt == nil || $0.expiresAt! > now) }
            .sorted { $0.occurredAt < $1.occurredAt }
            .suffix(Self.maximumRecordCount)
            .map { $0 }
    }

    private func pruneDetailedRecordsIfNeeded(now: Date) -> [AssistantBehaviorRecord] {
        let current = prunedRecords(snapshot.records, now: now)
        guard current != snapshot.records else { return current }
        guard !isReadOnly else { return current }
        // 长期学习聚合独立保留；这里只把超过保留期的详细记录从磁盘原子裁剪。
        snapshot.records = current
        _ = save(now: now)
        return snapshot.records
    }

    private func updateAggregate(for record: AssistantBehaviorRecord, delta: Int = 1) {
        guard let patternType = record.patternType else { return }
        var aggregate = snapshot.aggregatePreferences[patternType] ?? AssistantPatternAggregate()
        aggregate.detectedCount = max(0, aggregate.detectedCount + delta)
        if record.assistantDecision == .peek {
            aggregate.presentedCount = max(0, aggregate.presentedCount + delta)
        }
        if record.presentationResult == .acted { aggregate.actedCount = max(0, aggregate.actedCount + delta) }
        if record.userFeedback == .irrelevant { aggregate.irrelevantCount = max(0, aggregate.irrelevantCount + delta) }
        if record.userFeedback == .unfunny { aggregate.unfunnyCount = max(0, aggregate.unfunnyCount + delta) }
        snapshot.aggregatePreferences[patternType] = aggregate
    }

    private func quarantineCorruptFile() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? removeQuarantineFiles()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let quarantine = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(stamp)")
        do {
            try FileManager.default.moveItem(at: fileURL, to: quarantine)
            try AppPaths.hardenPrivateFile(at: quarantine)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func removeQuarantineFiles() throws {
        let directory = fileURL.deletingLastPathComponent()
        let prefix = "\(fileURL.lastPathComponent).corrupt-"
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private static func validBundleID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= 200,
              value.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }
}
