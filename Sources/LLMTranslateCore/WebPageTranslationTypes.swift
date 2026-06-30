import Foundation

public struct WebPageTranslationPreferences: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var defaultTargetLanguage: String
    public var translateVisibleOnly: Bool
    public var autoTranslateDomains: [String]
    public var disabledDomains: [String]
    public var persistWebHistory: Bool
    public var maxSegmentsPerBatch: Int
    public var maxCharactersPerBatch: Int

    public init(
        enabled: Bool = true,
        defaultTargetLanguage: String = "zh-Hans",
        translateVisibleOnly: Bool = true,
        autoTranslateDomains: [String] = [],
        disabledDomains: [String] = [],
        persistWebHistory: Bool = false,
        maxSegmentsPerBatch: Int = 20,
        maxCharactersPerBatch: Int = 2_000
    ) {
        self.enabled = enabled
        self.defaultTargetLanguage = defaultTargetLanguage
        self.translateVisibleOnly = translateVisibleOnly
        self.autoTranslateDomains = autoTranslateDomains
        self.disabledDomains = disabledDomains
        self.persistWebHistory = persistWebHistory
        self.maxSegmentsPerBatch = maxSegmentsPerBatch
        self.maxCharactersPerBatch = maxCharactersPerBatch
    }
}

public enum BrowserIntegrationStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case notInstalled
    case extensionMissing
    case extensionInstalledDisabled
    case permissionMissing
    case nativeHostMissing
    case nativeHostInvalid
    case appNotRunning
    case pairingRequired
    case ready
    case failed
}

public struct BrowserIntegrationState: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var bundleID: String
    public var appPath: String?
    public var extensionID: String?
    public var extensionVersion: String?
    public var nativeHostManifestPath: String?
    public var status: BrowserIntegrationStatus
    public var pairedAt: Date?
    public var lastPingAt: Date?
    public var lastErrorCode: String?
    public var lastErrorMessage: String?

    public init(
        id: String,
        name: String,
        bundleID: String,
        appPath: String? = nil,
        extensionID: String? = nil,
        extensionVersion: String? = nil,
        nativeHostManifestPath: String? = nil,
        status: BrowserIntegrationStatus,
        pairedAt: Date? = nil,
        lastPingAt: Date? = nil,
        lastErrorCode: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.appPath = appPath
        self.extensionID = extensionID
        self.extensionVersion = extensionVersion
        self.nativeHostManifestPath = nativeHostManifestPath
        self.status = status
        self.pairedAt = pairedAt
        self.lastPingAt = lastPingAt
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
    }
}

public enum WebPageTranslationErrorCode: String, Codable, Sendable, Hashable {
    case appNotRunning = "app_not_running"
    case nativeHostMissing = "native_host_missing"
    case nativeHostInvalid = "native_host_invalid"
    case extensionNotPaired = "extension_not_paired"
    case extensionNotAllowed = "extension_not_allowed"
    case modelNotConfigured = "model_not_configured"
    case modelNotReady = "model_not_ready"
    case modelLoadFailed = "model_load_failed"
    case translationFailed = "translation_failed"
    case payloadTooLarge = "payload_too_large"
    case timeout
    case cancelled
    case permissionMissing = "permission_missing"
    case unsupportedPage = "unsupported_page"
    case tabChanged = "tab_changed"
    case pageSessionExpired = "page_session_expired"
    case rateLimited = "rate_limited"
    case internalError = "internal_error"
}

public struct WebPageTranslationError: Codable, Sendable, Hashable, Error {
    public var code: WebPageTranslationErrorCode
    public var message: String
    public var repairAction: String?
    public var diagnostic: String?

    public init(
        code: WebPageTranslationErrorCode,
        message: String,
        repairAction: String? = nil,
        diagnostic: String? = nil
    ) {
        self.code = code
        self.message = message
        self.repairAction = repairAction
        self.diagnostic = diagnostic
    }
}

public enum WebPageSegmentTranslationStatus: String, Codable, Sendable, Hashable {
    case translated
    case skipped
    case failed
}

public struct WebPageTranslationSegment: Codable, Sendable, Hashable, Identifiable {
    public var segmentID: String
    public var text: String
    public var tagName: String?
    public var blockContext: String?
    public var priority: Int?
    public var textHash: String?

    public var id: String { segmentID }

    public init(
        segmentID: String,
        text: String,
        tagName: String? = nil,
        blockContext: String? = nil,
        priority: Int? = nil,
        textHash: String? = nil
    ) {
        self.segmentID = segmentID
        self.text = text
        self.tagName = tagName
        self.blockContext = blockContext
        self.priority = priority
        self.textHash = textHash
    }
}

public struct WebPageTranslateSegmentsPayload: Codable, Sendable, Hashable {
    public var jobID: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var urlHash: String?
    public var title: String?
    public var segments: [WebPageTranslationSegment]

    public init(
        jobID: String,
        sourceLanguage: String = "en",
        targetLanguage: String = "zh-Hans",
        urlHash: String? = nil,
        title: String? = nil,
        segments: [WebPageTranslationSegment]
    ) {
        self.jobID = jobID
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.urlHash = urlHash
        self.title = title
        self.segments = segments
    }
}

public struct WebPageSegmentTranslation: Codable, Sendable, Hashable, Identifiable {
    public var segmentID: String
    public var translation: String
    public var status: WebPageSegmentTranslationStatus
    public var errorMessage: String?

    public var id: String { segmentID }

    public init(
        segmentID: String,
        translation: String,
        status: WebPageSegmentTranslationStatus = .translated,
        errorMessage: String? = nil
    ) {
        self.segmentID = segmentID
        self.translation = translation
        self.status = status
        self.errorMessage = errorMessage
    }
}

public struct WebPageTranslationUsage: Codable, Sendable, Hashable {
    public var sourceCharacters: Int
    public var targetCharacters: Int

    public init(sourceCharacters: Int, targetCharacters: Int) {
        self.sourceCharacters = sourceCharacters
        self.targetCharacters = targetCharacters
    }
}

public struct WebPageTranslateSegmentsResult: Codable, Sendable, Hashable {
    public var jobID: String
    public var modelName: String
    public var translations: [WebPageSegmentTranslation]
    public var usage: WebPageTranslationUsage

    public init(
        jobID: String,
        modelName: String,
        translations: [WebPageSegmentTranslation],
        usage: WebPageTranslationUsage
    ) {
        self.jobID = jobID
        self.modelName = modelName
        self.translations = translations
        self.usage = usage
    }
}

public struct NativeMessageEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public var protocolVersion: Int
    public var requestID: String
    public var type: String
    public var browserID: String?
    public var extensionVersion: String?
    public var tabID: Int?
    public var pageSessionID: String?
    public var sentAt: Date?
    public var status: String?
    public var payload: Payload?
    public var error: WebPageTranslationError?

    public init(
        protocolVersion: Int = 1,
        requestID: String,
        type: String,
        browserID: String? = nil,
        extensionVersion: String? = nil,
        tabID: Int? = nil,
        pageSessionID: String? = nil,
        sentAt: Date? = nil,
        status: String? = nil,
        payload: Payload? = nil,
        error: WebPageTranslationError? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.type = type
        self.browserID = browserID
        self.extensionVersion = extensionVersion
        self.tabID = tabID
        self.pageSessionID = pageSessionID
        self.sentAt = sentAt
        self.status = status
        self.payload = payload
        self.error = error
    }
}

public struct EmptyPayload: Codable, Sendable, Hashable {
    public init() {}
}

