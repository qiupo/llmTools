import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import LLMToolsCore

@MainActor
final class AppState: ObservableObject {
    private static let modelIdleUnloadDelayNanoseconds: UInt64 = 30 * 1_000_000_000
    private static let maxLiveSubtitleHistoryCount = 120

    enum InputOrigin: Equatable {
        case selection
        case manual
        case file
    }

    enum QuickActionMode: String, Equatable {
        case text
        case image
        case media
    }

    enum AppLiveSubtitleRunState: String, Equatable {
        case stopped
        case starting
        case running
        case stopping
        case failed
    }

    private struct QuickActionOutputState {
        var outputText: String = ""
        var rawOutputText: String = ""
        var showsRawOutput: Bool = false
    }

    private struct LiveSubtitleRuntimeSession {
        var id: String
        var asrModel: ModelDescriptor
        var targetLanguage: String
        var sourceLanguageHint: ASRSourceLanguageHint
        var displayMode: SubtitleDisplayMode
        var sampleRate: Int
        var sequence: Int = -1
        var startedAt: Date = .now
        var speechFrameCount: Int = 0
        var silenceFrameCount: Int = 0
        var emittedFixtureSegmentCount: Int = 0
        var emittedLiveSegmentCount: Int = 0
        var audioBuffer = Data()
        var lastPartialASRMilliseconds: Int = 0
        var bufferedMilliseconds: Int = 0
        var asrInFlight = false
        var asrRevision = 0
        var streamingASR: StreamingASRProcessSession?
    }

    private struct LiveSubtitleASRStrategy {
        var minimumPartialMilliseconds: Int
        var partialIntervalMilliseconds: Int
        var maximumPartialMilliseconds: Int?
        var minimumFinalMilliseconds: Int
        var continuousFinalIntervalMilliseconds: Int
        var silenceFrameThreshold: Int
        var emitsPartialTranscripts: Bool

        static func strategy(for model: ModelDescriptor) -> LiveSubtitleASRStrategy {
            switch model.capabilities.speech?.family {
            case .funASRNano, .funASRMLTNano:
                return LiveSubtitleASRStrategy(
                    minimumPartialMilliseconds: 1_500,
                    partialIntervalMilliseconds: 1_500,
                    maximumPartialMilliseconds: 4_000,
                    minimumFinalMilliseconds: 600,
                    continuousFinalIntervalMilliseconds: 3_000,
                    silenceFrameThreshold: 3,
                    emitsPartialTranscripts: true
                )
            case .senseVoiceSmall:
                return LiveSubtitleASRStrategy(
                    minimumPartialMilliseconds: 1_200,
                    partialIntervalMilliseconds: 1_200,
                    maximumPartialMilliseconds: 3_000,
                    minimumFinalMilliseconds: 600,
                    continuousFinalIntervalMilliseconds: 3_000,
                    silenceFrameThreshold: 3,
                    emitsPartialTranscripts: true
                )
            case .qwen3ASR06B:
                return LiveSubtitleASRStrategy(
                    minimumPartialMilliseconds: 1_350,
                    partialIntervalMilliseconds: 1_350,
                    maximumPartialMilliseconds: 4_500,
                    minimumFinalMilliseconds: 700,
                    continuousFinalIntervalMilliseconds: 3_000,
                    silenceFrameThreshold: 4,
                    emitsPartialTranscripts: true
                )
            case .whisperCppCoreML:
                return LiveSubtitleASRStrategy(
                    minimumPartialMilliseconds: 2_000,
                    partialIntervalMilliseconds: 2_000,
                    maximumPartialMilliseconds: 6_000,
                    minimumFinalMilliseconds: 1_000,
                    continuousFinalIntervalMilliseconds: 4_000,
                    silenceFrameThreshold: 4,
                    emitsPartialTranscripts: true
                )
            default:
                return LiveSubtitleASRStrategy(
                    minimumPartialMilliseconds: 700,
                    partialIntervalMilliseconds: 1_000,
                    maximumPartialMilliseconds: 4_000,
                    minimumFinalMilliseconds: 700,
                    continuousFinalIntervalMilliseconds: 5_000,
                    silenceFrameThreshold: 3,
                    emitsPartialTranscripts: true
                )
            }
        }

        func applying(partialMilliseconds: Int?) -> LiveSubtitleASRStrategy {
            guard let partialMilliseconds else {
                return self
            }
            var strategy = self
            strategy.minimumPartialMilliseconds = partialMilliseconds
            strategy.partialIntervalMilliseconds = partialMilliseconds
            if let maximumPartialMilliseconds = strategy.maximumPartialMilliseconds,
               maximumPartialMilliseconds < partialMilliseconds {
                strategy.maximumPartialMilliseconds = partialMilliseconds
            }
            return strategy
        }
    }

    @Published var models: [ModelDescriptor] = []
    @Published var preferences = AppPreferences()
    @Published var history: [HistoryItem] = []
    @Published var quickActionMode: QuickActionMode = .text {
        didSet {
            guard oldValue != quickActionMode else {
                return
            }
            switchQuickActionOutputState(from: oldValue, to: quickActionMode)
        }
    }
    @Published var selectedTask: TaskKind = .translate
    @Published var inputText: String = ""
    @Published var inputOrigin: InputOrigin = .manual
    @Published var outputText: String = ""
    @Published var rawOutputText: String = ""
    @Published var showsRawOutput: Bool = false
    @Published var selectionInlineResultVisible: Bool = false
    @Published var statusMessage: String = L10n.text("Ready", language: .chinese)
    @Published var selectedModelID: UUID?
    @Published var isRunning: Bool = false
    @Published var isPreparingOCRImage: Bool = false
    @Published var validationError: String?
    @Published var providerTestModelID: UUID?
    @Published var visionProbeModelID: UUID?
    @Published var ocrImageInput: OCRImageInput?
    @Published var ocrPreviewImage: NSImage?
    @Published var ocrMode: OCRMode = .plainText
    @Published var mediaSubtitleFileURL: URL?
    @Published var mediaSubtitleDescriptor: MediaFileDescriptor?
    @Published var mediaSubtitleSegments: [SubtitleSegment] = []
    @Published var mediaSubtitleDiagnostics: MediaSubtitleDiagnostics?
    @Published var mediaSubtitleMode: SubtitleDisplayMode = .bilingual
    @Published var mediaSubtitleHealthReport: ASRHealthReport?
    @Published var mediaSubtitleHealthCheckMode: SpeechRuntimeMode?
    @Published var mediaSubtitleASRRepairMode: SpeechRuntimeMode?
    @Published var languageDetectionHealthReport: LanguageDetectionHealth?
    @Published var languageDetectionHealthCheckInProgress = false
    @Published var languageDetectionRuntimeRepairInProgress = false
    @Published var languageDetectionSampleText = "This is a language detection health check."
    @Published var speakerDiarizationHealthReport: SpeakerDiarizationHealth?
    @Published var speakerDiarizationHealthCheckInProgress = false
    @Published var speakerDiarizationRuntimeRepairInProgress = false
    @Published var fastTranslationHealthReport: FastTranslationHealth?
    @Published var fastTranslationHealthCheckInProgress = false
    @Published var fastTranslationRuntimeRepairInProgress = false
    @Published var appLiveSubtitleRunState: AppLiveSubtitleRunState = .stopped
    @Published var appLiveSubtitleSessionID: String?
    @Published var appLiveSubtitleAudioSource: LiveSubtitleAudioSource = .systemAndMicrophone
    @Published var appLiveSubtitleTargetLanguage: String = "zh-Hans"
    @Published var appLiveSubtitleDisplayMode: SubtitleDisplayMode = .bilingual
    @Published var appLiveSubtitleModelName: String?
    @Published var appLiveSubtitleOriginalText: String = ""
    @Published var appLiveSubtitleTranslatedText: String = ""
    @Published var appLiveSubtitleHistory: [SubtitleSegment] = []
    @Published var appLiveSubtitleIsPartial: Bool = false
    @Published var appLiveSubtitleMessage: String?
    @Published var appLiveSubtitleAudioLevel: Double = 0
    @Published var appLiveSubtitleBufferedMilliseconds: Int = 0
    @Published var appLiveSubtitleSpeechDetected: Bool = false
    @Published var appLiveSubtitleASRInFlight: Bool = false
    @Published var appLiveSubtitleIsImmersive: Bool = false

    let engine: TaskEngine
    private var preferenceSaveRevision = 0
    private var currentRunTask: Task<Void, Never>?
    private var runRevision = 0
    private var activeExternalModelUseCount = 0
    private var scheduledModelUnloadTask: Task<Void, Never>?
    private var textOutputState = QuickActionOutputState()
    private var imageOutputState = QuickActionOutputState()
    private var mediaOutputState = QuickActionOutputState()
    private var liveSubtitleSessions: [String: LiveSubtitleRuntimeSession] = [:]
    private var appLiveSubtitleSequence = -1
    private lazy var liveSubtitleCaptureService = LiveSubtitleCaptureService { [weak self] data in
        Task { @MainActor [weak self] in
            await self?.handleAppLiveAudioChunk(data)
        }
    }

    init(engine: TaskEngine = TaskEngine()) {
        self.engine = engine
    }

    func bootstrap() async {
        await engine.bootstrap()
        let snapshot = await engine.registry()
        var preferences = snapshot.preferences
        clearMissingWebPageModelPreference(&preferences, models: snapshot.models)
        clearMissingOCRModelPreference(&preferences, models: snapshot.models)
        clearMissingMediaSubtitlePreferences(&preferences, models: snapshot.models)
        self.models = snapshot.models
        self.preferences = preferences
        self.ocrMode = preferences.ocr.defaultMode
        self.mediaSubtitleMode = preferences.mediaSubtitles.defaultSubtitleMode
        self.appLiveSubtitleAudioSource = preferences.mediaSubtitles.liveAudioSource
        self.appLiveSubtitleTargetLanguage = preferences.mediaSubtitles.defaultTargetLanguage
        self.appLiveSubtitleDisplayMode = preferences.mediaSubtitles.defaultSubtitleMode
        self.selectedModelID = preferences.defaultModelID ?? snapshot.models.first(where: { $0.enabled && $0.capabilities.supportsText })?.id
        self.history = await engine.recentHistory()
        self.statusMessage = snapshot.models.isEmpty
            ? t("No model configured")
            : t("Ready")
    }

    func launchAtLoginStatusText() -> String {
        guard preferences.launchAtLogin else {
            return t("Disabled")
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return t("Enabled")
        case .requiresApproval:
            return t("Needs approval")
        case .notRegistered:
            return t("Pending")
        case .notFound:
            return t("Not found")
        @unknown default:
            return t("Unknown")
        }
    }

    func reloadSnapshot() async {
        let snapshot = await engine.registry()
        let currentModelID = selectedModelID
        var preferences = snapshot.preferences
        clearMissingWebPageModelPreference(&preferences, models: snapshot.models)
        clearMissingOCRModelPreference(&preferences, models: snapshot.models)
        clearMissingMediaSubtitlePreferences(&preferences, models: snapshot.models)
        models = snapshot.models
        self.preferences = preferences
        if !OCRMode.allCases.contains(ocrMode) {
            ocrMode = preferences.ocr.defaultMode
        }
        if appLiveSubtitleRunState == .stopped || appLiveSubtitleRunState == .failed {
            appLiveSubtitleAudioSource = preferences.mediaSubtitles.liveAudioSource
            appLiveSubtitleTargetLanguage = preferences.mediaSubtitles.defaultTargetLanguage
            appLiveSubtitleDisplayMode = preferences.mediaSubtitles.defaultSubtitleMode
        }
        if let currentModelID, snapshot.models.contains(where: { $0.id == currentModelID }) {
            selectedModelID = currentModelID
        } else {
            selectedModelID = preferences.defaultModelID ?? snapshot.models.first(where: { $0.enabled && $0.capabilities.supportsText })?.id
        }
        history = await engine.recentHistory()
    }

    func addModel(from url: URL) {
        Task {
            do {
                _ = try await engine.addModel(from: url)
                await reloadSnapshot()
                await MainActor.run {
                    validationError = nil
                    statusMessage = t("Added model")
                }
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                    statusMessage = t("Failed to add model")
                }
            }
        }
    }

    func addProviderModel(
        providerID: ModelProviderID,
        name: String,
        modelID: String,
        apiKey: String,
        baseURL: String,
        contextLength: Int
    ) {
        Task {
            do {
                _ = try await engine.addProviderModel(
                    providerID: providerID,
                    name: name,
                    modelID: modelID,
                    apiKey: apiKey,
                    baseURL: baseURL,
                    contextLength: contextLength
                )
                await reloadSnapshot()
                await MainActor.run {
                    validationError = nil
                    statusMessage = t("Added provider")
                }
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                    statusMessage = t("Failed to add provider")
                }
            }
        }
    }

    func updateProviderModel(
        id: UUID,
        providerID: ModelProviderID,
        name: String,
        modelID: String,
        apiKey: String,
        baseURL: String,
        contextLength: Int
    ) {
        Task {
            do {
                _ = try await engine.updateProviderModel(
                    id: id,
                    providerID: providerID,
                    name: name,
                    modelID: modelID,
                    apiKey: apiKey,
                    baseURL: baseURL,
                    contextLength: contextLength
                )
                await reloadSnapshot()
                await MainActor.run {
                    validationError = nil
                    statusMessage = t("Updated provider")
                }
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                    statusMessage = t("Failed to update provider")
                }
            }
        }
    }

    func testProviderModel(id: UUID) {
        guard providerTestModelID == nil else {
            return
        }
        providerTestModelID = id
        validationError = nil
        statusMessage = t("Testing provider")

        Task {
            do {
                _ = try await engine.testProviderModel(id: id)
                await reloadSnapshot()
                await MainActor.run {
                    providerTestModelID = nil
                    validationError = nil
                    statusMessage = t("Provider test succeeded")
                }
            } catch {
                await reloadSnapshot()
                await MainActor.run {
                    providerTestModelID = nil
                    validationError = error.localizedDescription
                    statusMessage = t("Provider test failed")
                }
            }
        }
    }

    func markModelVisionCapable(id: UUID) {
        Task {
            do {
                _ = try await engine.markModelVisionCapable(id: id)
                await reloadSnapshot()
                await MainActor.run {
                    validationError = nil
                    statusMessage = t("Marked vision-capable")
                }
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                    statusMessage = t("Failed")
                }
            }
        }
    }

    func markModelTextOnly(id: UUID) {
        Task {
            do {
                _ = try await engine.markModelTextOnly(id: id)
                await reloadSnapshot()
                await MainActor.run {
                    validationError = nil
                    statusMessage = t("Marked text-only")
                }
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                    statusMessage = t("Failed")
                }
            }
        }
    }

    func resetModelCapabilities(id: UUID) {
        Task {
            do {
                _ = try await engine.resetModelCapabilities(id: id)
                await reloadSnapshot()
                await MainActor.run {
                    validationError = nil
                    statusMessage = t("Capability reset")
                }
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                    statusMessage = t("Failed")
                }
            }
        }
    }

    func testVisionCapability(id: UUID) {
        guard visionProbeModelID == nil else {
            return
        }
        visionProbeModelID = id
        validationError = nil
        statusMessage = t("Testing vision")

        Task {
            do {
                _ = try await engine.testVisionCapability(id: id)
                await reloadSnapshot()
                await MainActor.run {
                    visionProbeModelID = nil
                    validationError = nil
                    statusMessage = t("Vision test succeeded")
                }
            } catch {
                await reloadSnapshot()
                await MainActor.run {
                    visionProbeModelID = nil
                    validationError = error.localizedDescription
                    statusMessage = t("Vision test failed")
                }
            }
        }
    }

    func loadInputFile(from url: URL) {
        if MediaIntakeService.isSupportedMediaFile(url) {
            loadMediaSubtitleFile(from: url)
            return
        }
        do {
            let resourceAccess = url.startAccessingSecurityScopedResource()
            defer {
                if resourceAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let content = try String(contentsOf: url, encoding: .utf8)
            setInputText(content, origin: .file)
            validationError = nil
            statusMessage = "\(t("Loaded")) \(url.lastPathComponent)"
        } catch {
            validationError = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
            statusMessage = t("Failed to load file")
        }
    }

    func loadMediaSubtitleFile(from url: URL) {
        do {
            let resourceAccess = url.startAccessingSecurityScopedResource()
            defer {
                if resourceAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let descriptor = try MediaIntakeService.descriptor(for: url)
            quickActionMode = .media
            mediaSubtitleFileURL = url
            mediaSubtitleDescriptor = descriptor
            mediaSubtitleSegments = []
            mediaSubtitleDiagnostics = nil
            outputText = ""
            rawOutputText = ""
            showsRawOutput = false
            validationError = nil
            mediaSubtitleMode = preferences.mediaSubtitles.defaultSubtitleMode
            statusMessage = "\(t("Loaded")) \(descriptor.fileName)"
        } catch {
            validationError = error.localizedDescription
            statusMessage = t("Failed to load file")
        }
    }

    func loadOCRImageFile(from url: URL) {
        do {
            let resourceAccess = url.startAccessingSecurityScopedResource()
            defer {
                if resourceAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let image = try OCRImagePreprocessor.normalizeImageFile(
                at: url,
                preferences: preferences.ocr
            )
            finishLoadingOCRImage(image, statusMessage: "\(t("Loaded")) \(url.lastPathComponent)")
        } catch {
            validationError = error.localizedDescription
            statusMessage = t("Failed to load image")
        }
    }

    func loadOCRImageData(_ data: Data, fileName: String? = nil, sourceDescription: String = "Image") {
        do {
            let image = try OCRImagePreprocessor.normalizeImageData(
                data,
                preferences: preferences.ocr,
                fileName: fileName,
                sourceDescription: sourceDescription
            )
            finishLoadingOCRImage(image, statusMessage: t("Loaded image"))
        } catch {
            validationError = error.localizedDescription
            statusMessage = t("Failed to load image")
        }
    }

    func loadOCRImageFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) {
            loadOCRImageData(data, fileName: "clipboard.png", sourceDescription: "Clipboard image")
            return
        }
        if let data = pasteboard.data(forType: .tiff) {
            loadOCRImageData(data, fileName: "clipboard.tiff", sourceDescription: "Clipboard image")
            return
        }
        if let image = NSImage(pasteboard: pasteboard),
           let data = image.tiffRepresentation {
            loadOCRImageData(data, fileName: "clipboard.tiff", sourceDescription: "Clipboard image")
            return
        }
        if let url = NSURL(from: pasteboard) as URL? {
            loadOCRImageFile(from: url)
            return
        }
        validationError = t("Clipboard does not contain an image.")
        statusMessage = t("Failed to load image")
    }

    func canLoadOCRImageFromPasteboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        if pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil {
            return true
        }
        if NSImage(pasteboard: pasteboard) != nil {
            return true
        }
        guard let url = NSURL(from: pasteboard) as URL?,
              let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    func loadOCRImageFromRemoteURL(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationError = t("Enter an image URL first.")
            return
        }
        isPreparingOCRImage = true
        validationError = nil
        statusMessage = t("Downloading image")
        Task {
            do {
                let image = try await OCRImagePreprocessor.downloadAndNormalizeRemoteImage(
                    from: value,
                    preferences: preferences.ocr
                )
                await MainActor.run {
                    isPreparingOCRImage = false
                    finishLoadingOCRImage(image, statusMessage: t("Loaded image"))
                }
            } catch {
                await MainActor.run {
                    isPreparingOCRImage = false
                    validationError = error.localizedDescription
                    statusMessage = t("Failed to load image")
                }
            }
        }
    }

    func removeModel(id: UUID) {
        Task {
            do {
                try await engine.removeModel(id: id)
                await reloadSnapshot()
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                }
            }
        }
    }

    func updatePreferences(_ transform: @escaping (inout AppPreferences) -> Void) {
        let previous = preferences
        let previousSelectedModelID = selectedModelID
        var updated = preferences
        transform(&updated)
        guard updated != preferences else {
            return
        }

        preferences = updated
        if updated.defaultModelID != previous.defaultModelID {
            selectedModelID = updated.defaultModelID
        }
        validationError = nil
        preferenceSaveRevision += 1
        let revision = preferenceSaveRevision

        Task {
            do {
                try await engine.setPreferences(updated)
            } catch {
                if revision == preferenceSaveRevision {
                    preferences = previous
                    selectedModelID = previousSelectedModelID
                    validationError = error.localizedDescription
                }
            }
        }
    }

    func setDefaultModel(id: UUID) {
        guard models.contains(where: { $0.id == id && $0.enabled && $0.capabilities.supportsText }) else {
            return
        }
        selectedModelID = id
        updatePreferences { $0.defaultModelID = id }
    }

    func setInputText(_ text: String, origin: InputOrigin) {
        quickActionMode = .text
        inputText = text
        inputOrigin = origin
        outputText = ""
        rawOutputText = ""
        showsRawOutput = false
        selectionInlineResultVisible = false
        validationError = nil
        if origin != .selection {
            SelectedTextService.clearCapturedSelectionSource()
        }
    }

    func setOCRMode(_ mode: OCRMode) {
        ocrMode = mode
        updatePreferences { $0.ocr.defaultMode = mode }
    }

    func clearOCRImage() {
        ocrImageInput = nil
        ocrPreviewImage = nil
        outputText = ""
        rawOutputText = ""
        showsRawOutput = false
        validationError = nil
        statusMessage = t("Ready")
    }

    func clearMediaSubtitleFile() {
        mediaSubtitleFileURL = nil
        mediaSubtitleDescriptor = nil
        mediaSubtitleSegments = []
        mediaSubtitleDiagnostics = nil
        outputText = ""
        rawOutputText = ""
        showsRawOutput = false
        validationError = nil
        statusMessage = t("Ready")
    }

    func setMediaSubtitleMode(_ mode: SubtitleDisplayMode) {
        mediaSubtitleMode = mode
        appLiveSubtitleDisplayMode = mode
        updatePreferences { $0.mediaSubtitles.defaultSubtitleMode = mode }
        updateActiveLiveSubtitleSession { session in
            session.displayMode = mode
        }
        refreshMediaSubtitlePreview()
    }

    func setFileSpeakerDiarizationEnabled(_ enabled: Bool) {
        let previous = preferences.speakerDiarization.enabledForFileSubtitles
        updatePreferences { $0.speakerDiarization.enabledForFileSubtitles = enabled }
        guard enabled, !previous, !mediaSubtitleSegments.isEmpty,
              SpeakerTurnMapper.speakerCount(in: mediaSubtitleSegments) == 0 else {
            return
        }
        statusMessage = t("Regenerate subtitles to apply speaker diarization")
    }

    func setMediaSubtitleTargetLanguage(_ targetLanguage: String) {
        appLiveSubtitleTargetLanguage = targetLanguage
        updatePreferences { $0.mediaSubtitles.defaultTargetLanguage = targetLanguage }
        updateActiveLiveSubtitleSession { session in
            session.targetLanguage = targetLanguage
        }
    }

    func setMediaSubtitleSourceLanguageHint(_ hint: ASRSourceLanguageHint) {
        updatePreferences { $0.mediaSubtitles.sourceLanguageHint = hint }
        updateActiveLiveSubtitleSession { session in
            session.sourceLanguageHint = hint
            session.audioBuffer.removeAll(keepingCapacity: false)
            session.speechFrameCount = 0
            session.silenceFrameCount = 0
            session.asrRevision += 1
        }
    }

    func defaultLiveASRPartialMilliseconds(for model: ModelDescriptor?) -> Int {
        guard let model else {
            return 0
        }
        return LiveSubtitleASRStrategy.strategy(for: model).minimumPartialMilliseconds
    }

    func effectiveLiveASRPartialMilliseconds(for model: ModelDescriptor?) -> Int {
        guard let model else {
            return 0
        }
        return liveSubtitleASRStrategy(for: model).minimumPartialMilliseconds
    }

    func liveASRPartialMillisecondsOverride(for model: ModelDescriptor?) -> Int? {
        guard let model else {
            return nil
        }
        return preferences.mediaSubtitles.liveASRPartialMillisecondsOverride(for: model.id)
    }

    func setLiveASRPartialMillisecondsOverride(_ milliseconds: Int?, for model: ModelDescriptor?) {
        guard let model else {
            return
        }
        let normalized = milliseconds.map(MediaSubtitlePreferences.normalizedLiveASRPartialMilliseconds)
        updatePreferences {
            $0.mediaSubtitles.setLiveASRPartialMillisecondsOverride(normalized, for: model.id)
        }
    }

    func setRealtimeASRModel(id modelID: UUID?) {
        let previousRunningModelID = liveSubtitleSessions[appLiveSubtitleSessionID ?? ""]?.asrModel.id
        updatePreferences { $0.mediaSubtitles.realtimeASRModelID = modelID }
        if appLiveSubtitleRunState == .running {
            Task { @MainActor in
                await switchActiveLiveSubtitleASRModel(to: modelID, previousModelID: previousRunningModelID)
            }
        } else {
            appLiveSubtitleModelName = selectedRealtimeASRModel?.name
        }
    }

    func setLiveSubtitleAudioSource(_ source: LiveSubtitleAudioSource) {
        appLiveSubtitleAudioSource = source
        updatePreferences { $0.mediaSubtitles.liveAudioSource = source }
        guard appLiveSubtitleRunState == .running else {
            if source.includesMicrophone {
                Task { @MainActor in
                    await preflightLiveSubtitleMicrophoneAccess(for: source)
                }
            }
            return
        }
        Task { @MainActor in
            await restartLiveSubtitleCapture(source: source)
        }
    }

    func setLiveSubtitleWindowOpacity(_ opacity: Double) {
        let normalized = MediaSubtitlePreferences.normalizedOpacity(opacity)
        updatePreferences { $0.mediaSubtitles.liveWindowOpacity = normalized }
    }

    func setLiveSubtitleWindowSize(width: Double, height: Double) {
        let normalizedWidth = MediaSubtitlePreferences.normalizedLiveWindowWidth(width)
        let normalizedHeight = MediaSubtitlePreferences.normalizedLiveWindowHeight(height)
        updatePreferences {
            $0.mediaSubtitles.liveWindowWidth = normalizedWidth
            $0.mediaSubtitles.liveWindowHeight = normalizedHeight
        }
    }

    func setLiveSubtitleImmersive(_ isImmersive: Bool) {
        appLiveSubtitleIsImmersive = isImmersive
    }

    private func updateActiveLiveSubtitleSession(_ transform: (inout LiveSubtitleRuntimeSession) -> Void) {
        guard let sessionID = appLiveSubtitleSessionID,
              var session = liveSubtitleSessions[sessionID] else {
            return
        }
        transform(&session)
        liveSubtitleSessions[sessionID] = session
    }

    private func copyLiveSubtitlePresentation(
        from latest: LiveSubtitleRuntimeSession,
        into session: inout LiveSubtitleRuntimeSession
    ) {
        session.targetLanguage = latest.targetLanguage
        session.displayMode = latest.displayMode
    }

    private func restartLiveSubtitleCapture(source: LiveSubtitleAudioSource) async {
        guard appLiveSubtitleRunState == .running,
              let sessionID = appLiveSubtitleSessionID else {
            return
        }
        appLiveSubtitleMessage = t("Switching audio source")
        do {
            await liveSubtitleCaptureService.stop()
            clearActiveLiveSubtitleAudioBuffer(sessionID: sessionID, incrementRevision: true)
            resetAppLiveSubtitleRuntimeMeters()
            try await liveSubtitleCaptureService.start(source: source)
            appLiveSubtitleMessage = nil
            statusMessage = t("Live subtitles running")
        } catch {
            appLiveSubtitleRunState = .failed
            appLiveSubtitleMessage = error.localizedDescription
            resetAppLiveSubtitleRuntimeMeters(keepASRMessage: true)
            validationError = error.localizedDescription
            statusMessage = t("Live subtitles failed")
            await liveSubtitleCaptureService.stop()
            if let sessionID = appLiveSubtitleSessionID {
                _ = stopLiveSubtitleSession(payload: StopLiveSubtitleSessionPayload(sessionID: sessionID, reason: "audio_source_failed"))
            }
            appLiveSubtitleSessionID = nil
        }
    }

    private func preflightLiveSubtitleMicrophoneAccess(for source: LiveSubtitleAudioSource) async {
        guard source.includesMicrophone else {
            return
        }
        do {
            try await liveSubtitleCaptureService.requestMicrophoneAccessIfNeeded()
            guard appLiveSubtitleAudioSource == source else {
                return
            }
            if appLiveSubtitleRunState != .running {
                appLiveSubtitleMessage = nil
            }
        } catch {
            guard appLiveSubtitleAudioSource == source else {
                return
            }
            appLiveSubtitleMessage = error.localizedDescription
            validationError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private func clearActiveLiveSubtitleAudioBuffer(sessionID: String, incrementRevision: Bool) {
        guard var session = liveSubtitleSessions[sessionID] else {
            return
        }
        session.audioBuffer.removeAll(keepingCapacity: false)
        session.speechFrameCount = 0
        session.silenceFrameCount = 0
        session.lastPartialASRMilliseconds = session.bufferedMilliseconds
        if incrementRevision {
            session.asrRevision += 1
        }
        liveSubtitleSessions[sessionID] = session
    }

    func sendOutputToTask(_ task: TaskKind) {
        let text = displayedOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, TaskKind.interactiveCases.contains(task) else {
            return
        }
        quickActionMode = .text
        selectedTask = task
        inputText = text
        inputOrigin = .manual
        outputText = ""
        rawOutputText = ""
        showsRawOutput = false
        validationError = nil
        statusMessage = t("Ready")
    }

    func prepareAutomaticSelectionText(_ text: String) -> Bool {
        quickActionMode = .text
        let characterCount = text.count
        let limit = automaticSelectionCharacterLimit
        guard characterCount <= limit else {
            inputText = ""
            inputOrigin = .selection
            outputText = ""
            rawOutputText = ""
            showsRawOutput = false
            selectionInlineResultVisible = true
            validationError = "\(t("Selected text is too long for automatic translation.")) \(characterCount)/\(limit)"
            statusMessage = t("Selection too long")
            SelectedTextService.clearCapturedSelectionSource()
            return false
        }
        return true
    }

    func showSelectionInlineResult() {
        selectionInlineResultVisible = true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let previous = preferences
        var updated = preferences
        updated.launchAtLogin = enabled
        preferences = updated
        validationError = nil

        Task {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }

                let actualStatus = SMAppService.mainApp.status
                if enabled && actualStatus != .enabled {
                    await MainActor.run {
                        self.validationError = self.t("Launch at login needs approval in System Settings.")
                        self.statusMessage = self.t("Launch at login needs approval")
                    }
                } else {
                    await MainActor.run {
                        self.statusMessage = enabled ? self.t("Launch at login enabled") : self.t("Launch at login disabled")
                    }
                }

                try await engine.setPreferences(updated)
                await reloadSnapshot()
            } catch {
                await MainActor.run {
                    self.preferences = previous
                    self.validationError = "\(self.t("Launch at login could not be updated")): \(error.localizedDescription)"
                    self.statusMessage = self.t("Launch at login update failed")
                }
                do {
                    try await engine.setPreferences(previous)
                    await reloadSnapshot()
                } catch {
                    await MainActor.run {
                        self.validationError = "\(self.t("Launch at login could not be saved")): \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func runCurrentTask() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            validationError = t("Please paste or type some text first.")
            return
        }
        guard validateInputLength(text) else {
            return
        }

        currentRunTask?.cancel()
        cancelScheduledModelUnload()
        runRevision += 1
        let revision = runRevision
        let request = TaskRequest(
            task: selectedTask,
            inputText: text,
            targetLanguage: preferences.defaultTranslationTarget,
            translationQuality: preferences.defaultTranslationQuality,
            polishStyle: preferences.defaultPolishStyle,
            summaryMode: preferences.defaultSummaryMode,
            explanationMode: preferences.defaultExplanationMode,
            todoExtractionMode: preferences.defaultTodoExtractionMode
        )
        let modelID = selectedModelID
        isRunning = true
        validationError = nil
        statusMessage = "\(t("Running")) \(selectedTask.title(language: preferences.appLanguage))..."
        currentRunTask = Task {
            do {
                let result = try await engine.run(
                    request: request,
                    modelID: modelID
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    outputText = result.text
                    rawOutputText = result.rawText
                    showsRawOutput = false
                    statusMessage = finishedStatusMessage(for: result)
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
                await replaceOriginalTextIfNeeded(result.text)
                await reloadSnapshot()
            } catch is CancellationError {
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    statusMessage = t("Cancelled")
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            } catch {
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    if let runnerError = error as? RunnerError, case .emptyResult = runnerError {
                        validationError = nil
                        outputText = t("The model returned an empty result. Try regenerate.")
                        rawOutputText = outputText
                        showsRawOutput = false
                    } else {
                        validationError = error.localizedDescription
                    }
                    statusMessage = t("Failed")
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            }
        }
    }

    func runCurrentOCR() {
        guard let image = ocrImageInput else {
            validationError = OCRTaskError.missingImage.localizedDescription
            return
        }
        guard preferences.ocr.enabled else {
            validationError = t("OCR/image recognition is disabled.")
            statusMessage = t("Failed")
            return
        }
        guard let modelID = selectedOCRModel?.id else {
            validationError = t("Choose a vision-capable OCR model in Settings.")
            statusMessage = t("Failed")
            return
        }

        currentRunTask?.cancel()
        cancelScheduledModelUnload()
        runRevision += 1
        let revision = runRevision
        let mode = ocrMode
        isRunning = true
        validationError = nil
        outputText = ""
        rawOutputText = ""
        showsRawOutput = false
        statusMessage = "\(t("Running")) \(L10n.ocrModeName(mode, language: preferences.appLanguage))..."
        currentRunTask = Task {
            do {
                let result = try await engine.runOCR(
                    image: image,
                    mode: mode,
                    modelID: modelID
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    outputText = result.text
                    rawOutputText = result.rawText
                    showsRawOutput = false
                    statusMessage = finishedStatusMessage(for: result)
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
                await reloadSnapshot()
            } catch is CancellationError {
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    statusMessage = t("Cancelled")
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            } catch {
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    validationError = error.localizedDescription
                    statusMessage = t("Failed")
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            }
        }
    }

    func runCurrentMediaSubtitles() {
        guard let url = mediaSubtitleFileURL else {
            validationError = t("Choose an audio or video file first.")
            return
        }
        guard preferences.mediaSubtitles.isEnabled else {
            validationError = t("Media subtitles are disabled.")
            statusMessage = t("Failed")
            return
        }
        guard selectedFileASRModel != nil else {
            validationError = t("Choose a local speech ASR model in Settings.")
            statusMessage = t("Failed")
            return
        }

        currentRunTask?.cancel()
        cancelScheduledModelUnload()
        runRevision += 1
        let revision = runRevision
        let asrModelID = preferences.mediaSubtitles.fileASRModelID
        isRunning = true
        validationError = nil
        outputText = ""
        rawOutputText = ""
        showsRawOutput = false
        mediaSubtitleDiagnostics = nil
        let speakerDiarizationEnabled = preferences.speakerDiarization.enabledForFileSubtitles
        statusMessage = speakerDiarizationEnabled ? t("Transcribing and separating speakers") : t("Transcribing media")
        currentRunTask = Task {
            do {
                let resourceAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if resourceAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let result = try await engine.transcribeMediaFile(
                    at: url,
                    modelID: asrModelID
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    mediaSubtitleDescriptor = result.descriptor
                    mediaSubtitleSegments = result.segments
                    mediaSubtitleDiagnostics = result.diagnostics
                    statusMessage = t("Translating subtitles")
                }
                let translated = try await engine.translateSubtitleSegments(
                    result.segments,
                    targetLanguage: preferences.mediaSubtitles.defaultTargetLanguage
                )
                try Task.checkCancellation()
                let preview = try SubtitleExporter.render(
                    segments: translated,
                    format: .markdown,
                    mode: mediaSubtitleMode
                )
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    mediaSubtitleSegments = translated
                    outputText = preview
                    rawOutputText = preview
                    showsRawOutput = false
                    statusMessage = mediaSubtitleFinishedStatus(diagnostics: result.diagnostics)
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
                await reloadSnapshot()
            } catch is CancellationError {
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    statusMessage = t("Cancelled")
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            } catch {
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    validationError = error.localizedDescription
                    statusMessage = t("Failed")
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            }
        }
    }

    func translateCurrentMediaSubtitles() {
        guard !mediaSubtitleSegments.isEmpty else {
            validationError = t("Generate transcript segments first.")
            return
        }
        currentRunTask?.cancel()
        cancelScheduledModelUnload()
        runRevision += 1
        let revision = runRevision
        let existing = mediaSubtitleSegments
        isRunning = true
        validationError = nil
        statusMessage = t("Translating subtitles")
        currentRunTask = Task {
            do {
                let translated = try await engine.translateSubtitleSegments(
                    existing,
                    targetLanguage: preferences.mediaSubtitles.defaultTargetLanguage
                )
                let preview = try SubtitleExporter.render(segments: translated, format: .markdown, mode: mediaSubtitleMode)
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    mediaSubtitleSegments = translated
                    outputText = preview
                    rawOutputText = preview
                    showsRawOutput = false
                    statusMessage = mediaSubtitleFinishedStatus(diagnostics: mediaSubtitleDiagnostics)
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    statusMessage = t("Cancelled")
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            } catch {
                await MainActor.run {
                    guard revision == runRevision else {
                        return
                    }
                    validationError = error.localizedDescription
                    statusMessage = t("Failed")
                    isRunning = false
                    currentRunTask = nil
                    scheduleModelUnloadIfIdle()
                }
            }
        }
    }

    func exportCurrentMediaSubtitles(format: SubtitleExportFormat) {
        guard !mediaSubtitleSegments.isEmpty else {
            validationError = t("No subtitle segments to export.")
            return
        }
        do {
            let content = try SubtitleExporter.render(
                segments: mediaSubtitleSegments,
                format: format,
                mode: mediaSubtitleMode
            )
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
            panel.canCreateDirectories = true
            let base = mediaSubtitleDescriptor?.fileName
                .split(separator: ".")
                .dropLast()
                .joined(separator: ".")
            panel.nameFieldStringValue = "\(base?.isEmpty == false ? base! : "subtitles").\(format.fileExtension)"
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else {
                return
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            validationError = nil
            statusMessage = "\(t("Exported")) \(url.lastPathComponent)"
        } catch {
            validationError = error.localizedDescription
            statusMessage = t("Failed")
        }
    }

    func refreshMediaSubtitlePreview() {
        guard !mediaSubtitleSegments.isEmpty else {
            return
        }
        do {
            let preview = try SubtitleExporter.render(
                segments: mediaSubtitleSegments,
                format: .markdown,
                mode: mediaSubtitleMode
            )
            outputText = preview
            rawOutputText = preview
            showsRawOutput = false
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func mediaSubtitleFinishedStatus(diagnostics: MediaSubtitleDiagnostics?) -> String {
        guard preferences.speakerDiarization.enabledForFileSubtitles else {
            return t("Finished")
        }
        if diagnostics?.diarizationErrorCode != nil {
            return "\(t("Finished")) · \(t("Speaker diarization failed"))"
        }
        let speakerCount = diagnostics?.speakerCount ?? SpeakerTurnMapper.speakerCount(in: mediaSubtitleSegments)
        if speakerCount > 0 {
            return "\(t("Finished")) · \(speakerCount) \(t(speakerCount == 1 ? "speaker" : "speakers"))"
        }
        return "\(t("Finished")) · \(t("No speaker labels"))"
    }

    func checkMediaSubtitleASRHealth(mode: SpeechRuntimeMode) {
        guard mediaSubtitleHealthCheckMode == nil else {
            return
        }
        mediaSubtitleHealthCheckMode = mode
        validationError = nil
        statusMessage = t("Checking ASR")
        let modelID = mode == .realtime
            ? preferences.mediaSubtitles.realtimeASRModelID
            : preferences.mediaSubtitles.fileASRModelID
        Task {
            do {
                let report = try await engine.checkASRHealth(modelID: modelID, mode: mode)
                await reloadSnapshot()
                await MainActor.run {
                    mediaSubtitleHealthReport = report
                    mediaSubtitleHealthCheckMode = nil
                    validationError = report.status == .ready ? nil : report.message
                    statusMessage = report.status == .ready ? t("ASR ready") : t("ASR check failed")
                }
            } catch {
                await reloadSnapshot()
                await MainActor.run {
                    mediaSubtitleHealthCheckMode = nil
                    validationError = error.localizedDescription
                    statusMessage = t("ASR check failed")
                }
            }
        }
    }

    func canRepairMediaSubtitleASRRuntime(report: ASRHealthReport) -> Bool {
        guard report.status == .runtimeMissing,
              let modelID = report.modelID,
              let model = models.first(where: { $0.id == modelID }),
              let family = model.capabilities.speech?.family,
              Self.supportsASRRepair(family) else {
            return false
        }
        let modelURL = model.resolvedPath ?? model.sourcePath
        if family == .vibeVoiceASR {
            return FileManager.default.fileExists(atPath: modelURL.path)
        }
        return FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("model.safetensors").path)
    }

    func checkLanguageDetectionHealth() {
        guard !languageDetectionHealthCheckInProgress else {
            return
        }
        languageDetectionHealthCheckInProgress = true
        validationError = nil
        statusMessage = t("Checking language routing")
        let preferences = preferences.languageRouting
        let sampleText = languageDetectionSampleText
        Task {
            let health = await LanguageDetectionService().health(
                preferences: preferences,
                sampleText: sampleText
            )
            await MainActor.run {
                languageDetectionHealthReport = health
                languageDetectionHealthCheckInProgress = false
                validationError = health.status == .ready || health.status == .disabled ? nil : health.message
                statusMessage = health.status == .ready ? t("Language routing ready") : t("Language routing check finished")
            }
        }
    }

    func canRepairLanguageDetectionRuntime(report: LanguageDetectionHealth) -> Bool {
        guard preferences.languageRouting.enabled else {
            return false
        }
        switch report.status {
        case .modelMissing, .runtimeMissing, .failed:
            return report.source != .settingsCommand
        case .ready, .disabled, .skippedShortText:
            return false
        }
    }

    func repairLanguageDetectionRuntime() {
        guard !languageDetectionRuntimeRepairInProgress else {
            return
        }
        languageDetectionRuntimeRepairInProgress = true
        validationError = nil
        statusMessage = t("Repairing language routing runtime")
        Task {
            do {
                try await Task.detached {
                    let installerPath = try Self.languageDetectionInstallerPath()
                    try Self.runLanguageDetectionInstaller(at: installerPath)
                }.value
                await MainActor.run {
                    languageDetectionRuntimeRepairInProgress = false
                    validationError = nil
                    statusMessage = t("Language routing runtime repaired")
                    checkLanguageDetectionHealth()
                }
            } catch {
                await MainActor.run {
                    languageDetectionRuntimeRepairInProgress = false
                    validationError = error.localizedDescription
                    statusMessage = t("Language routing runtime repair failed")
                }
            }
        }
    }

    func checkSpeakerDiarizationHealth() {
        guard !speakerDiarizationHealthCheckInProgress else {
            return
        }
        speakerDiarizationHealthCheckInProgress = true
        validationError = nil
        statusMessage = t("Checking speaker diarization")
        Task {
            let health = await engine.checkSpeakerDiarizationHealth()
            await MainActor.run {
                speakerDiarizationHealthReport = health
                speakerDiarizationHealthCheckInProgress = false
                validationError = health.status == .ready || health.status == .disabled ? nil : health.message
                statusMessage = health.status == .ready ? t("Speaker diarization runtime configured") : t("Speaker diarization check finished")
            }
        }
    }

    func saveSpeakerDiarizationHFToken(_ token: String) {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            validationError = t("Paste a Hugging Face token first.")
            statusMessage = t("Speaker diarization token not saved")
            return
        }
        do {
            try SpeakerDiarizationTokenStore.save(normalizedToken)
            validationError = nil
            statusMessage = t("HF token saved")
            refreshSpeakerDiarizationHealth(preferences: preferences.speakerDiarization)
        } catch {
            validationError = error.localizedDescription
            statusMessage = t("Failed to save HF token")
        }
    }

    func deleteSpeakerDiarizationHFToken() {
        do {
            try SpeakerDiarizationTokenStore.delete()
            validationError = nil
            statusMessage = t("HF token removed")
            refreshSpeakerDiarizationHealth(preferences: preferences.speakerDiarization)
        } catch {
            validationError = error.localizedDescription
            statusMessage = t("Failed to remove HF token")
        }
    }

    func canRepairSpeakerDiarizationRuntime(report: SpeakerDiarizationHealth) -> Bool {
        guard preferences.speakerDiarization.enabledForFileSubtitles else {
            return false
        }
        switch report.status {
        case .runtimeMissing, .failed:
            return report.source != .settingsCommand
        case .ready, .disabled, .requiresUserToken:
            return false
        }
    }

    func repairSpeakerDiarizationRuntime() {
        guard !speakerDiarizationRuntimeRepairInProgress else {
            return
        }
        speakerDiarizationRuntimeRepairInProgress = true
        validationError = nil
        statusMessage = t("Repairing speaker diarization runtime")
        Task {
            do {
                try await Task.detached {
                    let installerPath = try Self.speakerDiarizationInstallerPath()
                    try Self.runSpeakerDiarizationInstaller(at: installerPath)
                }.value
                await MainActor.run {
                    speakerDiarizationRuntimeRepairInProgress = false
                    validationError = nil
                    statusMessage = t("Speaker diarization runtime repaired")
                    checkSpeakerDiarizationHealth()
                }
            } catch {
                await MainActor.run {
                    speakerDiarizationRuntimeRepairInProgress = false
                    validationError = error.localizedDescription
                    statusMessage = t("Speaker diarization runtime repair failed")
                }
            }
        }
    }

    private func refreshSpeakerDiarizationHealth(preferences: SpeakerDiarizationPreferences) {
        speakerDiarizationHealthCheckInProgress = true
        Task {
            let health = await SpeakerDiarizationService().health(preferences: preferences)
            await MainActor.run {
                speakerDiarizationHealthReport = health
                speakerDiarizationHealthCheckInProgress = false
                validationError = health.status == .ready || health.status == .disabled ? nil : health.message
                statusMessage = health.status == .ready ? t("Speaker diarization runtime configured") : t("Speaker diarization check finished")
            }
        }
    }

    func checkFastTranslationHealth() {
        guard !fastTranslationHealthCheckInProgress else {
            return
        }
        fastTranslationHealthCheckInProgress = true
        validationError = nil
        statusMessage = t("Checking fast translation")
        Task {
            let health = await engine.checkFastTranslationHealth()
            await MainActor.run {
                fastTranslationHealthReport = health
                fastTranslationHealthCheckInProgress = false
                validationError = health.status == .ready || health.status == .disabled ? nil : health.message
                statusMessage = health.status == .ready ? t("Fast translation ready") : t("Fast translation check finished")
            }
        }
    }

    func canRepairFastTranslationRuntime(report: FastTranslationHealth) -> Bool {
        guard !preferences.fastTranslation.forceLLM else {
            return false
        }
        switch report.status {
        case .runtimeMissing, .unsupportedLanguagePair, .failed:
            return report.source != .settingsCommand
        case .ready, .disabled:
            return false
        }
    }

    func repairFastTranslationRuntime() {
        guard !fastTranslationRuntimeRepairInProgress else {
            return
        }
        fastTranslationRuntimeRepairInProgress = true
        validationError = nil
        statusMessage = t("Repairing fast translation runtime")
        let modelVariant = preferences.fastTranslation.modelVariant
        Task {
            do {
                try await Task.detached { [modelVariant] in
                    let installerPath = try Self.fastTranslationInstallerPath(for: modelVariant)
                    try Self.runFastTranslationInstaller(at: installerPath)
                }.value
                await MainActor.run {
                    fastTranslationRuntimeRepairInProgress = false
                    validationError = nil
                    statusMessage = t("Fast translation runtime repaired")
                    checkFastTranslationHealth()
                }
            } catch {
                await MainActor.run {
                    fastTranslationRuntimeRepairInProgress = false
                    validationError = error.localizedDescription
                    statusMessage = t("Fast translation runtime repair failed")
                }
            }
        }
    }

    func repairMediaSubtitleASRRuntime(mode: SpeechRuntimeMode) {
        guard mediaSubtitleASRRepairMode == nil else {
            return
        }
        guard let model = mediaSubtitleASRModel(for: mode),
              let family = model.capabilities.speech?.family else {
            validationError = t("Choose a local speech ASR model in Settings.")
            return
        }
        mediaSubtitleASRRepairMode = mode
        validationError = nil
        statusMessage = t("Repairing ASR runtime")
        Task {
            do {
                let commandTemplate = try await Task.detached {
                    try Self.buildASRCommandTemplateForRepair(model: model, family: family)
                }.value
                var updated = preferences
                switch family {
                case .funASRNano, .funASRMLTNano:
                    updated.mediaSubtitles.funASRCommandTemplate = commandTemplate
                case .senseVoiceSmall:
                    updated.mediaSubtitles.senseVoiceCommandTemplate = commandTemplate
                case .qwen3ASR06B:
                    updated.mediaSubtitles.qwen3ASRCommandTemplate = commandTemplate
                case .qwen3ASRSherpaOnnx:
                    updated.mediaSubtitles.genericASRCommandTemplate = commandTemplate
                case .vibeVoiceASR:
                    updated.mediaSubtitles.vibeVoiceASRCommandTemplate = commandTemplate
                case .whisperCppCoreML:
                    updated.mediaSubtitles.whisperCommandTemplate = commandTemplate
                case .customLocal:
                    updated.mediaSubtitles.genericASRCommandTemplate = commandTemplate
                }
                try await engine.setPreferences(updated)
                await reloadSnapshot()
                mediaSubtitleASRRepairMode = nil
                validationError = nil
                statusMessage = t("ASR runtime repaired")
                checkMediaSubtitleASRHealth(mode: mode)
            } catch {
                mediaSubtitleASRRepairMode = nil
                validationError = error.localizedDescription
                statusMessage = t("ASR runtime repair failed")
            }
        }
    }

    private func mediaSubtitleASRModel(for mode: SpeechRuntimeMode) -> ModelDescriptor? {
        switch mode {
        case .realtime:
            return selectedRealtimeASRModel
        case .fileOnly:
            return selectedFileASRModel
        }
    }

    private nonisolated static func supportsASRRepair(_ family: SpeechModelFamily) -> Bool {
        switch family {
        case .funASRNano, .funASRMLTNano, .senseVoiceSmall, .qwen3ASR06B, .vibeVoiceASR:
            return true
        case .qwen3ASRSherpaOnnx, .whisperCppCoreML, .customLocal:
            return false
        }
    }

    private nonisolated static func supportsMLXASRRepair(_ family: SpeechModelFamily) -> Bool {
        switch family {
        case .funASRNano, .funASRMLTNano, .senseVoiceSmall, .qwen3ASR06B:
            return true
        case .qwen3ASRSherpaOnnx, .vibeVoiceASR, .whisperCppCoreML, .customLocal:
            return false
        }
    }

    private nonisolated static func buildASRCommandTemplateForRepair(
        model: ModelDescriptor,
        family: SpeechModelFamily
    ) throws -> String {
        switch family {
        case .vibeVoiceASR:
            return try buildVibeVoiceASRCommandTemplateForRepair(model: model)
        case .funASRNano, .funASRMLTNano, .senseVoiceSmall, .qwen3ASR06B:
            return try buildMLXASRCommandTemplateForRepair(model: model, family: family)
        case .qwen3ASRSherpaOnnx, .whisperCppCoreML, .customLocal:
            throw MediaSubtitleError.asrRuntimeMissing("Automatic repair is not available for this ASR family.")
        }
    }

    private nonisolated static func buildMLXASRCommandTemplateForRepair(
        model: ModelDescriptor,
        family: SpeechModelFamily
    ) throws -> String {
        guard supportsMLXASRRepair(family) else {
            throw MediaSubtitleError.asrRuntimeMissing("Automatic repair is only available for supported safetensors/MLX ASR models.")
        }
        let modelURL = model.resolvedPath ?? model.sourcePath
        guard FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("model.safetensors").path) else {
            throw MediaSubtitleError.asrRuntimeMissing("Automatic repair expects a safetensors/MLX ASR model directory.")
        }
        let runnerPath = try mlxASRRunnerPath()
        let venvPath = mlxASRVenvPath(for: family)
        if !mlxASRVenvIsReady(venvPath, family: family) {
            let installerPath = try mlxASRInstallerPath(for: family)
            try runMLXASRInstaller(at: installerPath)
        }
        guard mlxASRVenvIsReady(venvPath, family: family) else {
            throw MediaSubtitleError.asrRuntimeFailed("Matching MLX ASR runtime was not found after installation.")
        }
        let envName = mlxASRVenvEnvironmentName(for: family)
        return "\(envName)=\(shellEscape(venvPath)) \(shellEscape(runnerPath)) --model {model} --audio {audio} --language {language}"
    }

    private nonisolated static func mlxASRRunnerPath() throws -> String {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("asr", isDirectory: true)
                .appendingPathComponent("llmtools-mlx-asr-runner.sh")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-mlx-asr-runner.sh")
                .path
        ].compactMap { $0 }
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw MediaSubtitleError.asrRuntimeMissing("Bundled llmTools MLX ASR runner was not found.")
    }

    private nonisolated static func buildVibeVoiceASRCommandTemplateForRepair(
        model: ModelDescriptor
    ) throws -> String {
        let modelURL = model.resolvedPath ?? model.sourcePath
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw MediaSubtitleError.asrModelMissing("VibeVoice-ASR model path is missing.")
        }
        let runnerPath = try vibeVoiceASRRunnerPath()
        let venvPath = vibeVoiceASRVenvPath()
        if !vibeVoiceASRVenvIsReady(venvPath) {
            let installerPath = try vibeVoiceASRInstallerPath()
            try runMLXASRInstaller(at: installerPath)
        }
        guard vibeVoiceASRVenvIsReady(venvPath) else {
            throw MediaSubtitleError.asrRuntimeFailed("VibeVoice-ASR runtime was not found after installation.")
        }
        let pythonPath = URL(fileURLWithPath: venvPath).appendingPathComponent("bin/python").path
        return "\(shellEscape(pythonPath)) \(shellEscape(runnerPath)) --model {model} --audio {audio} --language {language}"
    }

    private nonisolated static func vibeVoiceASRRunnerPath() throws -> String {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("asr", isDirectory: true)
                .appendingPathComponent("llmtools-vibevoice-asr-runner.py")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-vibevoice-asr-runner.py")
                .path
        ].compactMap { $0 }
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw MediaSubtitleError.asrRuntimeMissing("Bundled VibeVoice-ASR runner was not found.")
    }

    private nonisolated static func vibeVoiceASRInstallerPath() throws -> String {
        let fileManager = FileManager.default
        let scriptName = "install-phase4-vibevoice-asr-runtime.sh"
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("asr", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path
        ].compactMap { $0 }
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw MediaSubtitleError.asrRuntimeMissing("Bundled VibeVoice-ASR installer was not found.")
    }

    private nonisolated static func vibeVoiceASRVenvPath() -> String {
        if let envPath = ProcessInfo.processInfo.environment["LLMTOOLS_VIBEVOICE_ASR_VENV"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envPath.isEmpty {
            return envPath
        }
        return AppPaths.applicationSupportDirectory
            .appendingPathComponent("asr-runtime", isDirectory: true)
            .appendingPathComponent("vibevoice-venv", isDirectory: true)
            .path(percentEncoded: false)
    }

    private nonisolated static func vibeVoiceASRVenvIsReady(_ venvPath: String) -> Bool {
        let pythonPath = URL(fileURLWithPath: venvPath).appendingPathComponent("bin/python").path
        return FileManager.default.isExecutableFile(atPath: pythonPath)
            && pythonModuleExists(in: venvPath, moduleName: "vibevoice")
    }

    private nonisolated static func mlxASRInstallerPath(for family: SpeechModelFamily) throws -> String {
        let fileManager = FileManager.default
        let scriptName = mlxASRInstallerScriptName(for: family)
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("asr", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path
        ].compactMap { $0 }
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw MediaSubtitleError.asrRuntimeMissing("Bundled llmTools MLX ASR installer was not found.")
    }

    private nonisolated static func mlxASRVenvPath(for family: SpeechModelFamily) -> String {
        let envKey = mlxASRVenvEnvironmentName(for: family)
        let directoryName = mlxASRVenvDirectoryName(for: family)
        if let envPath = ProcessInfo.processInfo.environment[envKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envPath.isEmpty {
            return envPath
        }
        return AppPaths.applicationSupportDirectory
            .appendingPathComponent("asr-runtime", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .path(percentEncoded: false)
    }

    private nonisolated static func mlxASRVenvIsReady(_ venvPath: String, family: SpeechModelFamily) -> Bool {
        FileManager.default.isExecutableFile(
            atPath: URL(fileURLWithPath: venvPath)
                .appendingPathComponent("bin/mlx_audio.stt.generate")
                .path
        ) && mlxASRModelModuleExists(in: venvPath, family: family)
    }

    private nonisolated static func mlxASRModelModuleExists(in venvPath: String, family: SpeechModelFamily) -> Bool {
        let moduleName: String
        switch family {
        case .funASRMLTNano:
            moduleName = "funasr"
        case .funASRNano:
            moduleName = "fun_asr_nano"
        case .senseVoiceSmall:
            moduleName = "sensevoice"
        case .qwen3ASR06B:
            moduleName = "qwen3_asr"
        case .qwen3ASRSherpaOnnx, .vibeVoiceASR, .whisperCppCoreML, .customLocal:
            return false
        }
        let fileManager = FileManager.default
        let libURL = URL(fileURLWithPath: venvPath).appendingPathComponent("lib", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: libURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        let suffix = "/site-packages/mlx_audio/stt/models/\(moduleName)"
        while let element = enumerator.nextObject() {
            guard let url = element as? URL else {
                continue
            }
            if url.path.hasSuffix(suffix) {
                return true
            }
        }
        return false
    }

    private nonisolated static func pythonModuleExists(in venvPath: String, moduleName: String) -> Bool {
        let fileManager = FileManager.default
        let libURL = URL(fileURLWithPath: venvPath).appendingPathComponent("lib", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: libURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        let suffix = "/site-packages/\(moduleName)"
        while let element = enumerator.nextObject() {
            guard let url = element as? URL else {
                continue
            }
            if url.path.hasSuffix(suffix) {
                return true
            }
        }
        return false
    }

    private nonisolated static func mlxASRInstallerScriptName(for family: SpeechModelFamily) -> String {
        switch family {
        case .funASRMLTNano:
            return "install-phase4-funasr-mlx-runtime.sh"
        case .funASRNano:
            return "install-phase4-funasr-nano-mlx-runtime.sh"
        case .senseVoiceSmall:
            return "install-phase4-sensevoice-mlx-runtime.sh"
        case .qwen3ASR06B:
            return "install-phase4-mlx-asr-runtime.sh"
        case .qwen3ASRSherpaOnnx:
            return "install-phase4-mlx-asr-runtime.sh"
        case .vibeVoiceASR:
            return "install-phase4-vibevoice-asr-runtime.sh"
        case .whisperCppCoreML:
            return "install-phase4-whisper-coreml-runtime.sh"
        case .customLocal:
            return "install-phase4-mlx-asr-runtime.sh"
        }
    }

    private nonisolated static func mlxASRVenvEnvironmentName(for family: SpeechModelFamily) -> String {
        switch family {
        case .funASRMLTNano:
            return "LLMTOOLS_FUN_ASR_VENV"
        case .funASRNano:
            return "LLMTOOLS_FUN_ASR_NANO_VENV"
        case .senseVoiceSmall:
            return "LLMTOOLS_SENSEVOICE_ASR_VENV"
        case .qwen3ASR06B, .qwen3ASRSherpaOnnx:
            return "LLMTOOLS_ASR_VENV"
        case .vibeVoiceASR:
            return "LLMTOOLS_VIBEVOICE_ASR_VENV"
        case .whisperCppCoreML:
            return "LLMTOOLS_WHISPER_CPP_ROOT"
        case .customLocal:
            return "LLMTOOLS_ASR_VENV"
        }
    }

    private nonisolated static func mlxASRVenvDirectoryName(for family: SpeechModelFamily) -> String {
        switch family {
        case .funASRMLTNano:
            return "funasr-venv"
        case .funASRNano:
            return "funasr-nano-venv"
        case .senseVoiceSmall:
            return "sensevoice-venv"
        case .qwen3ASR06B, .qwen3ASRSherpaOnnx:
            return "venv"
        case .vibeVoiceASR:
            return "vibevoice-venv"
        case .whisperCppCoreML:
            return "whisper-cpp"
        case .customLocal:
            return "venv"
        }
    }

    private nonisolated static func runMLXASRInstaller(at installerPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installerPath)
        var environment = ProcessInfo.processInfo.environment
        let defaultPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPATH = environment["PATH"], !currentPATH.isEmpty {
            environment["PATH"] = "\(defaultPATH):\(currentPATH)"
        } else {
            environment["PATH"] = defaultPATH
        }
        process.environment = environment
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw MediaSubtitleError.asrRuntimeFailed(error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = [
                String(data: errorOutput, encoding: .utf8),
                String(data: output, encoding: .utf8)
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "exit \(process.terminationStatus)"
            throw MediaSubtitleError.asrRuntimeFailed(message)
        }
    }

    private nonisolated static func fastTranslationInstallerPath(for modelVariant: FastTranslationModelVariant) throws -> String {
        let fileManager = FileManager.default
        let scriptName: String
        switch modelVariant {
        case .opusMTEnZh:
            scriptName = "install-phase4x-ctranslate2-en-zh.sh"
        case .nllb200Distilled600M:
            scriptName = "install-phase4x-nllb-200-distilled-600m.sh"
        }
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("fastmt", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path
        ].compactMap { $0 }
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw FastTranslationError.runtimeMissing("Bundled fast translation installer was not found.")
    }

    private nonisolated static func runFastTranslationInstaller(at installerPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installerPath)
        process.currentDirectoryURL = URL(fileURLWithPath: installerPath).deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        let defaultPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPATH = environment["PATH"], !currentPATH.isEmpty {
            environment["PATH"] = "\(defaultPATH):\(currentPATH)"
        } else {
            environment["PATH"] = defaultPATH
        }
        process.environment = environment
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw FastTranslationError.runtimeFailed(error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = [
                String(data: errorOutput, encoding: .utf8),
                String(data: output, encoding: .utf8)
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "exit \(process.terminationStatus)"
            throw FastTranslationError.runtimeFailed(message)
        }
    }

    private nonisolated static func speakerDiarizationInstallerPath() throws -> String {
        let fileManager = FileManager.default
        let scriptName = "install-phase4x-pyannote-diarization.sh"
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("diarization", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path
        ].compactMap { $0 }
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw SpeakerDiarizationError.runtimeMissing("Bundled speaker diarization installer was not found.")
    }

    private nonisolated static func runSpeakerDiarizationInstaller(at installerPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installerPath)
        process.currentDirectoryURL = URL(fileURLWithPath: installerPath).deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        let defaultPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPATH = environment["PATH"], !currentPATH.isEmpty {
            environment["PATH"] = "\(defaultPATH):\(currentPATH)"
        } else {
            environment["PATH"] = defaultPATH
        }
        process.environment = environment
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SpeakerDiarizationError.runtimeFailed(error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = [
                String(data: errorOutput, encoding: .utf8),
                String(data: output, encoding: .utf8)
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "exit \(process.terminationStatus)"
            throw SpeakerDiarizationError.runtimeFailed(message)
        }
    }

    private nonisolated static func languageDetectionInstallerPath() throws -> String {
        let fileManager = FileManager.default
        let scriptName = "install-phase4x-fasttext-lid.sh"
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("lid", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent(scriptName)
                .path
        ].compactMap { $0 }
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw LanguageDetectionError.runtimeMissing("Bundled language routing installer was not found.")
    }

    private nonisolated static func runLanguageDetectionInstaller(at installerPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installerPath)
        process.currentDirectoryURL = URL(fileURLWithPath: installerPath).deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        let defaultPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPATH = environment["PATH"], !currentPATH.isEmpty {
            environment["PATH"] = "\(defaultPATH):\(currentPATH)"
        } else {
            environment["PATH"] = defaultPATH
        }
        process.environment = environment
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LanguageDetectionError.runtimeFailed(error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = [
                String(data: errorOutput, encoding: .utf8),
                String(data: output, encoding: .utf8)
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "exit \(process.terminationStatus)"
            throw LanguageDetectionError.runtimeFailed(message)
        }
    }

    private nonisolated static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var appLiveSubtitlesAreRunning: Bool {
        appLiveSubtitleRunState == .starting || appLiveSubtitleRunState == .running
    }

    func startAppLiveSubtitles(
        payload: StartAppLiveSubtitlePayload = StartAppLiveSubtitlePayload()
    ) async throws -> AppLiveSubtitleStatusPayload {
        if appLiveSubtitleRunState == .starting || appLiveSubtitleRunState == .running {
            return appLiveSubtitleStatusPayload()
        }
        guard preferences.mediaSubtitles.isEnabled else {
            throw MediaSubtitleError.disabled
        }

        let audioSource = payload.audioSource ?? preferences.mediaSubtitles.liveAudioSource
        let targetLanguage = payload.targetLanguage?.isEmpty == false
            ? payload.targetLanguage!
            : preferences.mediaSubtitles.defaultTargetLanguage
        let displayMode = payload.displayMode ?? preferences.mediaSubtitles.defaultSubtitleMode

        appLiveSubtitleRunState = .starting
        appLiveSubtitleSessionID = nil
        appLiveSubtitleSequence = -1
        appLiveSubtitleAudioSource = audioSource
        appLiveSubtitleTargetLanguage = targetLanguage
        appLiveSubtitleDisplayMode = displayMode
        appLiveSubtitleModelName = selectedRealtimeASRModel?.name
        appLiveSubtitleOriginalText = ""
        appLiveSubtitleTranslatedText = ""
        appLiveSubtitleHistory = []
        appLiveSubtitleIsPartial = false
        appLiveSubtitleMessage = nil
        resetAppLiveSubtitleRuntimeMeters()
        validationError = nil
        statusMessage = t("Starting live subtitles")

        do {
            let session = try await createLiveSubtitleSession(payload: CreateLiveSubtitleSessionPayload(
                targetLanguage: targetLanguage,
                displayMode: displayMode,
                sampleRate: 16_000,
                channelCount: 1
            ))
            appLiveSubtitleSessionID = session.sessionID
            appLiveSubtitleModelName = session.asrModelName
            try await liveSubtitleCaptureService.start(source: appLiveSubtitleAudioSource)
            appLiveSubtitleRunState = .running
            statusMessage = t("Live subtitles running")
            return appLiveSubtitleStatusPayload()
        } catch {
            if let sessionID = appLiveSubtitleSessionID {
                _ = stopLiveSubtitleSession(payload: StopLiveSubtitleSessionPayload(sessionID: sessionID, reason: "start_failed"))
            }
            await liveSubtitleCaptureService.stop()
            appLiveSubtitleSessionID = nil
            appLiveSubtitleRunState = .failed
            appLiveSubtitleMessage = error.localizedDescription
            resetAppLiveSubtitleRuntimeMeters(keepASRMessage: true)
            validationError = error.localizedDescription
            statusMessage = t("Live subtitles failed")
            throw error
        }
    }

    func stopAppLiveSubtitles(
        payload: StopAppLiveSubtitlePayload = StopAppLiveSubtitlePayload()
    ) async -> AppLiveSubtitleStatusPayload {
        guard appLiveSubtitleRunState != .stopped else {
            return appLiveSubtitleStatusPayload()
        }
        if isPassiveAppLiveSubtitleStopReason(payload.reason) {
            statusMessage = t("Live subtitles running")
            appLiveSubtitleMessage = nil
            return appLiveSubtitleStatusPayload()
        }
        appLiveSubtitleRunState = .stopping
        statusMessage = t("Stopping live subtitles")
        await liveSubtitleCaptureService.stop()
        if let sessionID = appLiveSubtitleSessionID {
            let response = stopLiveSubtitleSession(payload: StopLiveSubtitleSessionPayload(
                sessionID: sessionID,
                reason: payload.reason ?? "app_stop"
            ))
            applyAppLiveSubtitleEvents(response.events)
        }
        appLiveSubtitleSessionID = nil
        appLiveSubtitleRunState = .stopped
        appLiveSubtitleIsPartial = false
        appLiveSubtitleMessage = payload.reason
        resetAppLiveSubtitleRuntimeMeters(keepASRMessage: true)
        statusMessage = t("Live subtitles stopped")
        appLiveSubtitleIsImmersive = false
        return appLiveSubtitleStatusPayload()
    }

    private func isPassiveAppLiveSubtitleStopReason(_ reason: String?) -> Bool {
        let normalized = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "navigation", "tab_removed", "capture_stopped", "capture_ended", "track_ended":
            return appLiveSubtitlesAreRunning
        default:
            return false
        }
    }

    func stopAppLiveSubtitlesForShutdown() {
        liveSubtitleCaptureService.stopImmediately()
        if let sessionID = appLiveSubtitleSessionID {
            _ = stopLiveSubtitleSession(payload: StopLiveSubtitleSessionPayload(sessionID: sessionID, reason: "app_shutdown"))
        }
        appLiveSubtitleSessionID = nil
        appLiveSubtitleRunState = .stopped
        resetAppLiveSubtitleRuntimeMeters()
        appLiveSubtitleIsImmersive = false
    }

    func appLiveSubtitleStatusPayload() -> AppLiveSubtitleStatusPayload {
        AppLiveSubtitleStatusPayload(
            isRunning: appLiveSubtitlesAreRunning,
            sessionID: appLiveSubtitleSessionID,
            audioSource: appLiveSubtitleAudioSource,
            targetLanguage: appLiveSubtitleTargetLanguage,
            displayMode: appLiveSubtitleDisplayMode,
            windowOpacity: preferences.mediaSubtitles.liveWindowOpacity,
            modelName: appLiveSubtitleModelName,
            originalText: appLiveSubtitleOriginalText,
            translatedText: appLiveSubtitleTranslatedText,
            isPartial: appLiveSubtitleIsPartial,
            status: appLiveSubtitleRunState.rawValue,
            message: appLiveSubtitleMessage,
            audioLevel: appLiveSubtitleAudioLevel,
            bufferedMilliseconds: appLiveSubtitleBufferedMilliseconds,
            speechDetected: appLiveSubtitleSpeechDetected,
            asrInFlight: appLiveSubtitleASRInFlight
        )
    }

    private func handleAppLiveAudioChunk(_ data: Data) async {
        guard appLiveSubtitleRunState == .running,
              let sessionID = appLiveSubtitleSessionID else {
            return
        }
        let stats = pcm16Stats(data)
        appLiveSubtitleAudioLevel = min(1, stats.rms / 2_000)
        appLiveSubtitleSequence += 1
        let payload = LiveAudioChunkPayload(
            sessionID: sessionID,
            sequence: appLiveSubtitleSequence,
            sampleRate: 16_000,
            channelCount: 1,
            pcm16Base64: data.base64EncodedString(),
            capturedAt: Date()
        )
        do {
            let response = try await appendLiveAudioChunk(payload: payload)
            guard appLiveSubtitleRunState == .running,
                  appLiveSubtitleSessionID == sessionID else {
                return
            }
            appLiveSubtitleBufferedMilliseconds = response.bufferedMilliseconds
            appLiveSubtitleSpeechDetected = response.speechDetected
            applyAppLiveSubtitleEvents(response.events)
        } catch {
            guard appLiveSubtitleRunState == .running,
                  appLiveSubtitleSessionID == sessionID else {
                return
            }
            appLiveSubtitleRunState = .failed
            appLiveSubtitleMessage = error.localizedDescription
            resetAppLiveSubtitleRuntimeMeters(keepASRMessage: true)
            validationError = error.localizedDescription
            statusMessage = t("Live subtitles failed")
            await liveSubtitleCaptureService.stop()
            if let sessionID = appLiveSubtitleSessionID {
                _ = stopLiveSubtitleSession(payload: StopLiveSubtitleSessionPayload(sessionID: sessionID, reason: "chunk_failed"))
            }
            appLiveSubtitleSessionID = nil
        }
    }

    private func applyAppLiveSubtitleEvents(_ events: [LiveSubtitleEvent]) {
        for event in events {
            switch event.type {
            case .partialTranscript:
                if let segment = event.segment {
                    appLiveSubtitleOriginalText = segment.originalText
                    appLiveSubtitleTranslatedText = segment.translatedText ?? ""
                    appLiveSubtitleIsPartial = true
                    appLiveSubtitleMessage = nil
                }
            case .finalTranscript:
                if let segment = event.segment {
                    appLiveSubtitleOriginalText = segment.originalText
                    appLiveSubtitleTranslatedText = segment.translatedText ?? ""
                    upsertAppLiveSubtitleHistory(segment)
                    appLiveSubtitleIsPartial = false
                    appLiveSubtitleMessage = nil
                }
            case .partialTranslation:
                if let segment = event.segment {
                    appLiveSubtitleOriginalText = segment.originalText
                    appLiveSubtitleTranslatedText = segment.translatedText ?? segment.originalText
                    appLiveSubtitleIsPartial = true
                }
            case .finalTranslation:
                if let segment = event.segment {
                    appLiveSubtitleOriginalText = segment.originalText
                    appLiveSubtitleTranslatedText = segment.translatedText ?? segment.originalText
                    upsertAppLiveSubtitleHistory(segment)
                    appLiveSubtitleIsPartial = false
                }
            case .languageDetected, .warning:
                appLiveSubtitleMessage = event.message
            case .error:
                appLiveSubtitleMessage = event.message
                validationError = event.message
            case .stopped:
                appLiveSubtitleMessage = event.message
                appLiveSubtitleIsPartial = false
            }
        }
    }

    private func upsertAppLiveSubtitleHistory(_ segment: SubtitleSegment) {
        let hasOriginal = !segment.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTranslation = !(translatedText?.isEmpty ?? true)
        guard hasOriginal || hasTranslation else {
            return
        }
        var history = appLiveSubtitleHistory
        if let index = history.firstIndex(where: { $0.id == segment.id }) {
            history[index] = segment
        } else {
            history.append(segment)
            if history.count > Self.maxLiveSubtitleHistoryCount {
                history.removeFirst(history.count - Self.maxLiveSubtitleHistoryCount)
            }
        }
        appLiveSubtitleHistory = history
    }

    private func resetAppLiveSubtitleRuntimeMeters(keepASRMessage: Bool = false) {
        appLiveSubtitleAudioLevel = 0
        appLiveSubtitleBufferedMilliseconds = 0
        appLiveSubtitleSpeechDetected = false
        appLiveSubtitleASRInFlight = false
        if !keepASRMessage {
            appLiveSubtitleMessage = nil
        }
    }

    private func setAppLiveSubtitleASRInFlight(_ inFlight: Bool, sessionID: String) {
        guard appLiveSubtitleSessionID == sessionID else {
            return
        }
        appLiveSubtitleASRInFlight = inFlight
    }

    func cancelCurrentTask(unloadModel: Bool = false) {
        currentRunTask?.cancel()
        currentRunTask = nil
        runRevision += 1
        if isRunning {
            isRunning = false
            statusMessage = t("Cancelled")
        }
        if unloadModel {
            cancelScheduledModelUnload()
            Task {
                await engine.unloadAll()
            }
        } else {
            scheduleModelUnloadIfIdle()
        }
    }

    func beginExternalModelUse() {
        activeExternalModelUseCount += 1
        cancelScheduledModelUnload()
    }

    func endExternalModelUse() {
        activeExternalModelUseCount = max(activeExternalModelUseCount - 1, 0)
        scheduleModelUnloadIfIdle()
    }

    func createLiveSubtitleSession(
        payload: CreateLiveSubtitleSessionPayload
    ) async throws -> LiveSubtitleSessionResponse {
        guard preferences.mediaSubtitles.isEnabled else {
            throw MediaSubtitleError.disabled
        }
        guard let model = selectedRealtimeASRModel else {
            throw MediaSubtitleError.missingASRModel
        }
        let health = LocalASRProcessRunner().health(for: model, preferences: preferences.mediaSubtitles, mode: .realtime)
        guard health.status == .ready else {
            throw MediaSubtitleError.asrRuntimeMissing(health.message)
        }
        let sessionID = UUID().uuidString
        let targetLanguage = payload.targetLanguage.isEmpty
            ? preferences.mediaSubtitles.defaultTargetLanguage
            : payload.targetLanguage
        let displayMode = payload.displayMode
        let streamingASR = try await createStreamingASRSessionIfNeeded(
            for: model,
            sourceLanguageHint: preferences.mediaSubtitles.sourceLanguageHint
        )
        liveSubtitleSessions[sessionID] = LiveSubtitleRuntimeSession(
            id: sessionID,
            asrModel: model,
            targetLanguage: targetLanguage,
            sourceLanguageHint: preferences.mediaSubtitles.sourceLanguageHint,
            displayMode: displayMode,
            sampleRate: payload.sampleRate,
            streamingASR: streamingASR
        )
        beginExternalModelUse()
        return LiveSubtitleSessionResponse(
            sessionID: sessionID,
            sampleRate: 16_000,
            asrModelName: model.name,
            asrModelID: model.id.uuidString,
            targetLanguage: targetLanguage,
            displayMode: displayMode
        )
    }

    private func createStreamingASRSessionIfNeeded(
        for model: ModelDescriptor,
        sourceLanguageHint: ASRSourceLanguageHint
    ) async throws -> StreamingASRProcessSession? {
        let fixturePath = ProcessInfo.processInfo.environment["LLMTOOLS_ASR_FIXTURE_JSON"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fixturePath.isEmpty {
            return nil
        }
        return try await StreamingASRProcessSession.start(
            model: model,
            preferences: preferences.mediaSubtitles,
            sourceLanguageHint: sourceLanguageHint
        )
    }

    private func liveSubtitleASRStrategy(for model: ModelDescriptor) -> LiveSubtitleASRStrategy {
        let override = preferences.mediaSubtitles.liveASRPartialMillisecondsOverride(for: model.id)
        return LiveSubtitleASRStrategy.strategy(for: model).applying(partialMilliseconds: override)
    }

    private func switchActiveLiveSubtitleASRModel(
        to modelID: UUID?,
        previousModelID: UUID?
    ) async {
        guard appLiveSubtitleRunState == .running,
              let sessionID = appLiveSubtitleSessionID,
              var session = liveSubtitleSessions[sessionID] else {
            return
        }
        guard let modelID,
              let model = models.first(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsRealtimeSpeech }) else {
            appLiveSubtitleMessage = t("Choose a local speech ASR model first.")
            if let previousModelID {
                updatePreferences { $0.mediaSubtitles.realtimeASRModelID = previousModelID }
            }
            return
        }
        guard session.asrModel.id != model.id else {
            appLiveSubtitleModelName = model.name
            appLiveSubtitleMessage = nil
            return
        }

        let oldStreamingASR = session.streamingASR
        session.asrRevision += 1
        let switchRevision = session.asrRevision
        session.asrInFlight = true
        session.audioBuffer.removeAll(keepingCapacity: false)
        session.speechFrameCount = 0
        session.silenceFrameCount = 0
        session.lastPartialASRMilliseconds = session.bufferedMilliseconds
        liveSubtitleSessions[sessionID] = session

        appLiveSubtitleModelName = model.name
        appLiveSubtitleOriginalText = ""
        appLiveSubtitleTranslatedText = ""
        appLiveSubtitleHistory = []
        appLiveSubtitleIsPartial = false
        appLiveSubtitleMessage = t("Switching ASR model")
        statusMessage = t("Switching ASR model")

        do {
            let newStreamingASR = try await createStreamingASRSessionIfNeeded(
                for: model,
                sourceLanguageHint: session.sourceLanguageHint
            )
            guard var latest = liveSubtitleSessions[sessionID],
                  latest.asrRevision == switchRevision else {
                newStreamingASR?.stop()
                return
            }
            oldStreamingASR?.stop()
            latest.asrModel = model
            latest.streamingASR = newStreamingASR
            latest.asrInFlight = false
            latest.audioBuffer.removeAll(keepingCapacity: false)
            latest.speechFrameCount = 0
            latest.silenceFrameCount = 0
            latest.lastPartialASRMilliseconds = latest.bufferedMilliseconds
            liveSubtitleSessions[sessionID] = latest
            appLiveSubtitleModelName = model.name
            appLiveSubtitleMessage = nil
            statusMessage = t("Live subtitles running")
        } catch {
            if var latest = liveSubtitleSessions[sessionID],
               latest.asrRevision == switchRevision {
                latest.asrInFlight = false
                latest.asrRevision += 1
                liveSubtitleSessions[sessionID] = latest
                appLiveSubtitleModelName = latest.asrModel.name
                updatePreferences { $0.mediaSubtitles.realtimeASRModelID = latest.asrModel.id }
            }
            appLiveSubtitleMessage = error.localizedDescription
            validationError = error.localizedDescription
            statusMessage = t("Live subtitles running")
        }
    }

    func appendLiveAudioChunk(
        payload: LiveAudioChunkPayload
    ) async throws -> LiveAudioChunkResponse {
        func stoppedResponse() -> LiveAudioChunkResponse {
            LiveAudioChunkResponse(
                sessionID: payload.sessionID,
                acceptedSequence: payload.sequence,
                bufferedMilliseconds: 0,
                speechDetected: false,
                events: []
            )
        }

        guard var session = liveSubtitleSessions[payload.sessionID] else {
            throw MediaSubtitleError.asrRuntimeFailed("Live subtitle session not found.")
        }
        guard payload.sequence > session.sequence else {
            return LiveAudioChunkResponse(
                sessionID: payload.sessionID,
                acceptedSequence: session.sequence,
                bufferedMilliseconds: session.bufferedMilliseconds,
                speechDetected: false,
                events: []
            )
        }
        guard let data = Data(base64Encoded: payload.pcm16Base64) else {
            throw MediaSubtitleError.asrRuntimeFailed("Invalid PCM chunk payload.")
        }
        let speechDetected = pcm16HasSpeech(data)
        session.sequence = payload.sequence
        session.bufferedMilliseconds += chunkMilliseconds(data: data, sampleRate: payload.sampleRate)
        if speechDetected {
            session.speechFrameCount += 1
            session.silenceFrameCount = 0
            session.audioBuffer.append(data)
        } else {
            session.silenceFrameCount += 1
        }

        var events: [LiveSubtitleEvent] = []
        if speechDetected, let fixture = nextFixtureSegment(for: session) {
            events.append(LiveSubtitleEvent(
                type: .partialTranscript,
                sessionID: session.id,
                segment: fixture,
                message: nil,
                code: nil
            ))
        }
        let strategy = liveSubtitleASRStrategy(for: session.asrModel)
        var ranASRThisChunk = false
        if speechDetected,
           strategy.emitsPartialTranscripts,
           nextFixtureSegment(for: session) == nil,
           !session.asrInFlight,
           session.bufferedMilliseconds - session.lastPartialASRMilliseconds >= strategy.partialIntervalMilliseconds,
           chunkMilliseconds(data: session.audioBuffer, sampleRate: session.sampleRate) >= strategy.minimumPartialMilliseconds,
           !session.audioBuffer.isEmpty {
            session.asrInFlight = true
            setAppLiveSubtitleASRInFlight(true, sessionID: payload.sessionID)
            session.lastPartialASRMilliseconds = session.bufferedMilliseconds
            liveSubtitleSessions[payload.sessionID] = session

            var partial: SubtitleSegment?
            var asrError: Error?
            do {
                partial = try await transcribeLiveAudioBuffer(for: session, isFinal: false, strategy: strategy).first
            } catch {
                asrError = error
            }
            ranASRThisChunk = true
            guard var latest = liveSubtitleSessions[payload.sessionID] else {
                setAppLiveSubtitleASRInFlight(false, sessionID: payload.sessionID)
                return stoppedResponse()
            }
            guard latest.asrRevision == session.asrRevision else {
                setAppLiveSubtitleASRInFlight(false, sessionID: payload.sessionID)
                return LiveAudioChunkResponse(
                    sessionID: latest.id,
                    acceptedSequence: latest.sequence,
                    bufferedMilliseconds: latest.bufferedMilliseconds,
                    speechDetected: speechDetected,
                    events: events
                )
            }
            latest.asrInFlight = false
            setAppLiveSubtitleASRInFlight(false, sessionID: payload.sessionID)
            if let partial {
                events.append(LiveSubtitleEvent(
                    type: .partialTranscript,
                    sessionID: latest.id,
                    segment: partial
                ))
            } else if let asrError {
                events.append(LiveSubtitleEvent(
                    type: .warning,
                    sessionID: latest.id,
                    message: "ASR: \(asrError.localizedDescription)"
                ))
            }
            session = latest
        }
        let bufferedAudioMilliseconds = chunkMilliseconds(data: session.audioBuffer, sampleRate: session.sampleRate)
        let shouldFinalizeAfterSilence = session.speechFrameCount > 0
            && session.silenceFrameCount >= strategy.silenceFrameThreshold
            && bufferedAudioMilliseconds >= strategy.minimumFinalMilliseconds
        let shouldFinalizeDuringContinuousSpeech = speechDetected
            && strategy.continuousFinalIntervalMilliseconds > 0
            && !ranASRThisChunk
            && !session.asrInFlight
            && bufferedAudioMilliseconds >= strategy.continuousFinalIntervalMilliseconds
        if shouldFinalizeAfterSilence || shouldFinalizeDuringContinuousSpeech {
            if let final = nextFixtureSegment(for: session, advance: true) {
                var finalSegment = final
                finalSegment.isFinal = true
                events.append(LiveSubtitleEvent(type: .finalTranscript, sessionID: session.id, segment: finalSegment))
                if let latest = liveSubtitleSessions[payload.sessionID] {
                    guard latest.asrRevision == session.asrRevision else {
                        return LiveAudioChunkResponse(
                            sessionID: latest.id,
                            acceptedSequence: latest.sequence,
                            bufferedMilliseconds: latest.bufferedMilliseconds,
                            speechDetected: speechDetected,
                            events: events
                        )
                    }
                    copyLiveSubtitlePresentation(from: latest, into: &session)
                }
                if session.displayMode != .original {
                    let requestedTargetLanguage = session.targetLanguage
                    let translatedSegments = try? await engine.translateSubtitleSegments(
                        [finalSegment],
                        targetLanguage: requestedTargetLanguage
                    )
                    guard let latest = liveSubtitleSessions[payload.sessionID] else {
                        return stoppedResponse()
                    }
                    guard latest.asrRevision == session.asrRevision else {
                        return LiveAudioChunkResponse(
                            sessionID: latest.id,
                            acceptedSequence: latest.sequence,
                            bufferedMilliseconds: latest.bufferedMilliseconds,
                            speechDetected: speechDetected,
                            events: events
                        )
                    }
                    copyLiveSubtitlePresentation(from: latest, into: &session)
                    if session.displayMode != .original,
                       session.targetLanguage == requestedTargetLanguage,
                       let translated = translatedSegments?.first {
                        events.append(LiveSubtitleEvent(type: .finalTranslation, sessionID: session.id, segment: translated))
                    }
                }
                session.emittedFixtureSegmentCount += 1
            } else if !session.asrInFlight {
                session.asrInFlight = true
                setAppLiveSubtitleASRInFlight(true, sessionID: payload.sessionID)
                session.lastPartialASRMilliseconds = session.bufferedMilliseconds
                let transcribedByteCount = session.audioBuffer.count
                liveSubtitleSessions[payload.sessionID] = session

                var finalSegments: [SubtitleSegment] = []
                var asrError: Error?
                do {
                    finalSegments = try await transcribeLiveAudioBuffer(for: session, isFinal: true, strategy: strategy)
                } catch {
                    asrError = error
                }
                guard var latest = liveSubtitleSessions[payload.sessionID] else {
                    setAppLiveSubtitleASRInFlight(false, sessionID: payload.sessionID)
                    return stoppedResponse()
                }
                guard latest.asrRevision == session.asrRevision else {
                    setAppLiveSubtitleASRInFlight(false, sessionID: payload.sessionID)
                    return LiveAudioChunkResponse(
                        sessionID: latest.id,
                        acceptedSequence: latest.sequence,
                        bufferedMilliseconds: latest.bufferedMilliseconds,
                        speechDetected: speechDetected,
                        events: events
                    )
                }
                latest.asrInFlight = false
                setAppLiveSubtitleASRInFlight(false, sessionID: payload.sessionID)
                if !finalSegments.isEmpty {
                    for final in finalSegments {
                        events.append(LiveSubtitleEvent(type: .finalTranscript, sessionID: latest.id, segment: final))
                    }
                    copyLiveSubtitlePresentation(from: latest, into: &session)
                    if session.displayMode != .original {
                        let requestedTargetLanguage = session.targetLanguage
                        let translatedSegments = try? await engine.translateSubtitleSegments(
                            finalSegments,
                            targetLanguage: requestedTargetLanguage
                        )
                        guard let latestAfterTranslation = liveSubtitleSessions[payload.sessionID] else {
                            return stoppedResponse()
                        }
                        guard latestAfterTranslation.asrRevision == session.asrRevision else {
                            return LiveAudioChunkResponse(
                                sessionID: latestAfterTranslation.id,
                                acceptedSequence: latestAfterTranslation.sequence,
                                bufferedMilliseconds: latestAfterTranslation.bufferedMilliseconds,
                                speechDetected: speechDetected,
                                events: events
                            )
                        }
                        copyLiveSubtitlePresentation(from: latestAfterTranslation, into: &session)
                        copyLiveSubtitlePresentation(from: latestAfterTranslation, into: &latest)
                        if session.displayMode != .original,
                           session.targetLanguage == requestedTargetLanguage {
                            for translated in translatedSegments ?? [] {
                                events.append(LiveSubtitleEvent(type: .finalTranslation, sessionID: latest.id, segment: translated))
                            }
                        }
                    }
                    latest.emittedLiveSegmentCount += finalSegments.count
                } else if let asrError {
                    events.append(LiveSubtitleEvent(
                        type: .warning,
                        sessionID: latest.id,
                        message: "ASR: \(asrError.localizedDescription)"
                    ))
                } else {
                    events.append(LiveSubtitleEvent(
                        type: .warning,
                        sessionID: latest.id,
                        message: t("ASR returned no text.")
                    ))
                }
                latest.speechFrameCount = 0
                latest.silenceFrameCount = 0
                if transcribedByteCount > 0 {
                    if latest.audioBuffer.count > transcribedByteCount {
                        latest.audioBuffer.removeFirst(transcribedByteCount)
                    } else {
                        latest.audioBuffer.removeAll(keepingCapacity: false)
                    }
                }
                latest.lastPartialASRMilliseconds = max(
                    latest.lastPartialASRMilliseconds,
                    latest.bufferedMilliseconds
                )
                session = latest
            }
        }
        guard liveSubtitleSessions[payload.sessionID] != nil else {
            return stoppedResponse()
        }
        liveSubtitleSessions[payload.sessionID] = session
        return LiveAudioChunkResponse(
            sessionID: session.id,
            acceptedSequence: session.sequence,
            bufferedMilliseconds: session.bufferedMilliseconds,
            speechDetected: speechDetected,
            events: events
        )
    }

    func stopLiveSubtitleSession(
        payload: StopLiveSubtitleSessionPayload
    ) -> LiveAudioChunkResponse {
        let removed = liveSubtitleSessions.removeValue(forKey: payload.sessionID)
        removed?.streamingASR?.stop()
        if removed != nil {
            endExternalModelUse()
        }
        return LiveAudioChunkResponse(
            sessionID: payload.sessionID,
            acceptedSequence: removed?.sequence ?? -1,
            bufferedMilliseconds: removed?.bufferedMilliseconds ?? 0,
            speechDetected: false,
            events: [
                LiveSubtitleEvent(
                    type: .stopped,
                    sessionID: payload.sessionID,
                    message: payload.reason ?? "stopped"
                )
            ]
        )
    }

    private func scheduleModelUnloadIfIdle() {
        guard !isRunning, activeExternalModelUseCount == 0 else {
            return
        }
        cancelScheduledModelUnload()
        scheduledModelUnloadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.modelIdleUnloadDelayNanoseconds)
            } catch {
                return
            }
            guard let self else {
                return
            }
            guard !self.isRunning, self.activeExternalModelUseCount == 0 else {
                self.scheduleModelUnloadIfIdle()
                return
            }
            self.scheduledModelUnloadTask = nil
            await self.engine.unloadAll()
        }
    }

    private func cancelScheduledModelUnload() {
        scheduledModelUnloadTask?.cancel()
        scheduledModelUnloadTask = nil
    }

    private func pcm16HasSpeech(_ data: Data) -> Bool {
        let stats = pcm16Stats(data)
        return stats.rms > 180 || stats.peak > 1_400
    }

    private func pcm16Stats(_ data: Data) -> (rms: Double, peak: Double) {
        guard data.count >= 2 else {
            return (0, 0)
        }
        var sum: Double = 0
        var peak: Double = 0
        var count = 0
        data.withUnsafeBytes { pointer in
            var offset = 0
            while offset + 1 < data.count {
                let sample = Int16(littleEndian: pointer.load(fromByteOffset: offset, as: Int16.self))
                let value = abs(Double(sample))
                sum += value * value
                peak = max(peak, value)
                count += 1
                offset += 2
            }
        }
        guard count > 0 else {
            return (0, 0)
        }
        let rms = sqrt(sum / Double(count))
        return (rms, peak)
    }

    private func chunkMilliseconds(data: Data, sampleRate: Int) -> Int {
        guard sampleRate > 0 else {
            return 0
        }
        let samples = data.count / 2
        return Int((Double(samples) / Double(sampleRate)) * 1000)
    }

    private func transcribeLiveAudioBuffer(
        for session: LiveSubtitleRuntimeSession,
        isFinal: Bool,
        strategy: LiveSubtitleASRStrategy
    ) async throws -> [SubtitleSegment] {
        guard !session.audioBuffer.isEmpty else {
            return []
        }
        let transcriptionBuffer = liveAudioBufferForASR(
            session.audioBuffer,
            sampleRate: session.sampleRate,
            isFinal: isFinal,
            strategy: strategy
        )
        let duration = TimeInterval(chunkMilliseconds(data: transcriptionBuffer, sampleRate: session.sampleRate)) / 1_000
        if let streamingASR = session.streamingASR {
            var segments = try await streamingASR.transcribe(
                pcm16Data: transcriptionBuffer,
                sampleRate: session.sampleRate,
                sessionID: UUID(uuidString: session.id) ?? UUID(),
                duration: duration,
                sourceLanguageHint: session.sourceLanguageHint,
                isFinal: isFinal
            )
            for index in segments.indices {
                segments[index].index = session.emittedLiveSegmentCount + index
                segments[index].isFinal = isFinal
            }
            return segments
        }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-live-asr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let audioURL = temporaryDirectory.appendingPathComponent("live-16k-mono.wav")
        try writePCM16WAV(data: transcriptionBuffer, sampleRate: session.sampleRate, url: audioURL)
        var segments = try await LocalASRProcessRunner().transcribe(
            audioURL: audioURL,
            model: session.asrModel,
            sessionID: UUID(uuidString: session.id) ?? UUID(),
            duration: duration,
            preferences: preferences.mediaSubtitles,
            context: ASRTranscriptionContext(
                mode: .realtime,
                sourceLanguageHint: session.sourceLanguageHint,
                isFinal: isFinal
            )
        )
        for index in segments.indices {
            segments[index].index = session.emittedLiveSegmentCount + index
            segments[index].isFinal = isFinal
        }
        return segments
    }

    private func liveAudioBufferForASR(
        _ data: Data,
        sampleRate: Int,
        isFinal: Bool,
        strategy: LiveSubtitleASRStrategy
    ) -> Data {
        guard !isFinal,
              let maximumPartialMilliseconds = strategy.maximumPartialMilliseconds,
              maximumPartialMilliseconds > 0,
              sampleRate > 0 else {
            return data
        }
        let bytesPerSample = 2
        let maximumSamples = max(1, Int((Double(maximumPartialMilliseconds) / 1_000) * Double(sampleRate)))
        let maximumBytes = maximumSamples * bytesPerSample
        guard data.count > maximumBytes else {
            return data
        }
        let start = data.count - maximumBytes
        return Data(data[start..<data.count])
    }

    private func writePCM16WAV(data: Data, sampleRate: Int, url: URL) throws {
        let safeSampleRate = max(sampleRate, 1)
        let byteRate = safeSampleRate * 2
        let blockAlign = 2
        let dataSize = UInt32(min(data.count, Int(UInt32.max)))
        var wav = Data()
        wav.append(Data("RIFF".utf8))
        appendLittleEndianUInt32(36 + dataSize, to: &wav)
        wav.append(Data("WAVE".utf8))
        wav.append(Data("fmt ".utf8))
        appendLittleEndianUInt32(16, to: &wav)
        appendLittleEndianUInt16(1, to: &wav)
        appendLittleEndianUInt16(1, to: &wav)
        appendLittleEndianUInt32(UInt32(safeSampleRate), to: &wav)
        appendLittleEndianUInt32(UInt32(byteRate), to: &wav)
        appendLittleEndianUInt16(UInt16(blockAlign), to: &wav)
        appendLittleEndianUInt16(16, to: &wav)
        wav.append(Data("data".utf8))
        appendLittleEndianUInt32(dataSize, to: &wav)
        wav.append(data.prefix(Int(dataSize)))
        try wav.write(to: url, options: .atomic)
    }

    private func appendLittleEndianUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func appendLittleEndianUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func nextFixtureSegment(
        for session: LiveSubtitleRuntimeSession,
        advance: Bool = false
    ) -> SubtitleSegment? {
        guard let fixturePath = ProcessInfo.processInfo.environment["LLMTOOLS_ASR_FIXTURE_JSON"],
              let data = try? Data(contentsOf: URL(fileURLWithPath: fixturePath)),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let rawSegments: [[String: Any]]
        if let dictionary = object as? [String: Any],
           let segments = dictionary["segments"] as? [[String: Any]] {
            rawSegments = segments
        } else if let segments = object as? [[String: Any]] {
            rawSegments = segments
        } else {
            return nil
        }
        let index = min(session.emittedFixtureSegmentCount, max(rawSegments.count - 1, 0))
        guard rawSegments.indices.contains(index) else {
            return nil
        }
        let raw = rawSegments[index]
        let text = (raw["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return nil
        }
        return SubtitleSegment(
            sessionID: UUID(uuidString: session.id) ?? UUID(),
            index: index,
            startTime: raw["start"] as? TimeInterval ?? TimeInterval(index) * 2,
            endTime: raw["end"] as? TimeInterval ?? TimeInterval(index + 1) * 2,
            originalText: advance ? text : String(text.prefix(max(1, min(text.count, 18)))),
            sourceLanguage: raw["language"] as? String,
            languageConfidence: raw["confidence"] as? Double,
            isFinal: advance,
            asrModelID: session.asrModel.id.uuidString
        )
    }

    var displayedOutputText: String {
        showsRawOutput ? rawOutputText : outputText
    }

    var hasDifferentRawOutput: Bool {
        !rawOutputText.isEmpty && rawOutputText != outputText
    }

    func clearHistory() {
        Task {
            do {
                try await engine.clearHistory()
                await reloadSnapshot()
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func replaceOriginalTextIfNeeded(_ text: String) async {
        guard preferences.replaceOriginalText else {
            return
        }
        guard inputOrigin == .selection else {
            return
        }
        guard SelectedTextService.isAccessibilityTrusted else {
            SelectedTextService.requestAccessibilityPermission()
            validationError = t("Replace original text requires Accessibility permission.")
            statusMessage = t("Result copied; replacement unavailable")
            return
        }

        let replaced = await SelectedTextService.replaceSelectedText(with: text)
        if replaced {
            statusMessage = t("Result pasted back")
        } else {
            validationError = t("Could not replace the original text from the current selection.")
            statusMessage = t("Result copied")
        }
    }

    private func t(_ key: String) -> String {
        L10n.text(key, language: preferences.appLanguage)
    }

    private func finishedStatusMessage(for result: TaskResult) -> String {
        guard let sourceLanguage = result.sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceLanguage.isEmpty,
              sourceLanguage.lowercased() != "auto" else {
            return t("Finished")
        }
        return "\(t("Finished")) · \(t("Source")) \(sourceLanguage)"
    }

    private func clearMissingWebPageModelPreference(
        _ preferences: inout AppPreferences,
        models: [ModelDescriptor]
    ) {
        guard let modelID = preferences.webPageTranslation.modelID else {
            return
        }
        if !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsText }) {
            preferences.webPageTranslation.modelID = nil
        }
    }

    private func clearMissingOCRModelPreference(
        _ preferences: inout AppPreferences,
        models: [ModelDescriptor]
    ) {
        guard let modelID = preferences.ocr.modelID else {
            return
        }
        if !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsImage }) {
            preferences.ocr.modelID = nil
        }
    }

    private func switchQuickActionOutputState(from previousMode: QuickActionMode, to nextMode: QuickActionMode) {
        storeCurrentOutputState(for: previousMode)
        restoreOutputState(for: nextMode)
    }

    private func storeCurrentOutputState(for mode: QuickActionMode) {
        let state = QuickActionOutputState(
            outputText: outputText,
            rawOutputText: rawOutputText,
            showsRawOutput: showsRawOutput
        )
        switch mode {
        case .text:
            textOutputState = state
        case .image:
            imageOutputState = state
        case .media:
            mediaOutputState = state
        }
    }

    private func restoreOutputState(for mode: QuickActionMode) {
        let state: QuickActionOutputState
        switch mode {
        case .text:
            state = textOutputState
        case .image:
            state = imageOutputState
        case .media:
            state = mediaOutputState
        }
        outputText = state.outputText
        rawOutputText = state.rawOutputText
        showsRawOutput = state.showsRawOutput
    }

    private func setOCRImage(_ image: OCRImageInput) {
        quickActionMode = .image
        ocrImageInput = image
        ocrPreviewImage = NSImage(data: image.data)
        outputText = ""
        rawOutputText = ""
        showsRawOutput = false
        validationError = nil
        if preferences.ocr.useModelRecognitionByDefault {
            ocrMode = preferences.ocr.defaultMode
        }
    }

    private func clearMissingMediaSubtitlePreferences(
        _ preferences: inout AppPreferences,
        models: [ModelDescriptor]
    ) {
        if let modelID = preferences.mediaSubtitles.realtimeASRModelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsRealtimeSpeech }) {
            preferences.mediaSubtitles.realtimeASRModelID = preferredRealtimeSpeechModel(in: models)?.id
        }
        if let modelID = preferences.mediaSubtitles.fileASRModelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsFileSpeech }) {
            preferences.mediaSubtitles.fileASRModelID = models.first(where: { $0.enabled && $0.capabilities.supportsFileSpeech })?.id
        }
        if preferences.mediaSubtitles.realtimeASRModelID == nil {
            preferences.mediaSubtitles.realtimeASRModelID = preferredRealtimeSpeechModel(in: models)?.id
        }
        if preferences.mediaSubtitles.fileASRModelID == nil {
            preferences.mediaSubtitles.fileASRModelID = models.first(where: { $0.enabled && $0.capabilities.supportsFileSpeech })?.id
        }
    }

    private func finishLoadingOCRImage(_ image: OCRImageInput, statusMessage loadedStatusMessage: String) {
        setOCRImage(image)
        statusMessage = loadedStatusMessage
        runCurrentOCRIfDefaultRecognitionIsEnabled()
    }

    private func runCurrentOCRIfDefaultRecognitionIsEnabled() {
        guard preferences.ocr.useModelRecognitionByDefault else {
            return
        }
        guard !isRunning, !isPreparingOCRImage else {
            return
        }
        runCurrentOCR()
    }

    private var selectedModelContextLength: Int? {
        if let selectedModelID,
           let model = models.first(where: { $0.id == selectedModelID && $0.enabled && $0.capabilities.supportsText }) {
            return model.contextLength
        }
        if let defaultModelID = preferences.defaultModelID,
           let model = models.first(where: { $0.id == defaultModelID && $0.enabled && $0.capabilities.supportsText }) {
            return model.contextLength
        }
        return models.first(where: { $0.enabled && $0.capabilities.supportsText })?.contextLength
    }

    private var inputCharacterLimit: Int {
        InputSizePolicy.maximumInputCharacters(forContextLength: selectedModelContextLength)
    }

    private var automaticSelectionCharacterLimit: Int {
        InputSizePolicy.maximumAutomaticSelectionCharacters(forContextLength: selectedModelContextLength)
    }

    private func validateInputLength(_ text: String) -> Bool {
        let characterCount = text.count
        let limit = inputCharacterLimit
        guard characterCount <= limit else {
            outputText = ""
            rawOutputText = ""
            showsRawOutput = false
            validationError = "\(t("Input is too long for the selected model.")) \(characterCount)/\(limit)"
            statusMessage = t("Failed")
            if inputOrigin == .selection {
                selectionInlineResultVisible = true
            }
            return false
        }
        return true
    }

    func selectedModelDisplayName(limit: Int = 18) -> String {
        let resolvedName = models.first(where: { $0.id == selectedModelID })?.name
            ?? models.first?.name
            ?? t("No model configured")
        return Self.condensedModelName(resolvedName, limit: limit)
    }

    var webPageTranslationModelID: UUID? {
        webPageTranslationModel?.id
    }

    var webPageTranslationModelIsRemote: Bool {
        webPageTranslationModel?.isRemoteProvider ?? false
    }

    var webPageTranslationConcurrencyLimit: Int {
        let engine = preferences.fastTranslation.engine(for: .webPageTranslate)
        if engine == .fastMT || engine == .auto {
            return preferences.fastTranslation.maxConcurrentBatches
        }
        if webPageTranslationModelIsRemote {
            return 4
        }
        return 1
    }

    private var webPageTranslationModel: ModelDescriptor? {
        if let modelID = preferences.webPageTranslation.modelID,
           let model = models.first(where: { $0.id == modelID && $0.enabled }) {
            return model
        }
        if let selectedModelID,
           let selectedModel = models.first(where: { $0.id == selectedModelID && $0.enabled && $0.capabilities.supportsText }) {
            return selectedModel
        }
        if let defaultModelID = preferences.defaultModelID,
           let defaultModel = models.first(where: { $0.id == defaultModelID && $0.enabled && $0.capabilities.supportsText }) {
            return defaultModel
        }
        return models.first(where: { $0.enabled && $0.capabilities.supportsText })
    }

    func webPageTranslationModelDisplayName(limit: Int = 18) -> String {
        let resolvedName = webPageTranslationModelID.flatMap { modelID in
            models.first(where: { $0.id == modelID })?.name
        } ?? t("No model configured")
        return Self.condensedModelName(resolvedName, limit: limit)
    }

    var visionCapableModels: [ModelDescriptor] {
        models.filter { $0.enabled && $0.capabilities.supportsImage }
    }

    var textCapableModels: [ModelDescriptor] {
        models.filter { $0.enabled && $0.capabilities.supportsText }
    }

    var speechCapableModels: [ModelDescriptor] {
        models.filter { $0.enabled && $0.capabilities.supportsSpeech }
    }

    var realtimeSpeechModels: [ModelDescriptor] {
        models.filter { $0.enabled && $0.capabilities.supportsRealtimeSpeech }
    }

    var fileSpeechModels: [ModelDescriptor] {
        models.filter { $0.enabled && $0.capabilities.supportsFileSpeech }
    }

    var selectedOCRModel: ModelDescriptor? {
        guard let modelID = preferences.ocr.modelID else {
            return nil
        }
        return models.first { $0.id == modelID && $0.enabled && $0.capabilities.supportsImage }
    }

    var selectedRealtimeASRModel: ModelDescriptor? {
        guard let modelID = preferences.mediaSubtitles.realtimeASRModelID else {
            return nil
        }
        return models.first { $0.id == modelID && $0.enabled && $0.capabilities.supportsRealtimeSpeech }
    }

    var selectedFileASRModel: ModelDescriptor? {
        guard let modelID = preferences.mediaSubtitles.fileASRModelID else {
            return nil
        }
        return models.first { $0.id == modelID && $0.enabled && $0.capabilities.supportsFileSpeech }
    }

    private func preferredRealtimeSpeechModel(in models: [ModelDescriptor]) -> ModelDescriptor? {
        models
            .filter { $0.enabled && $0.capabilities.supportsRealtimeSpeech }
            .min { lhs, rhs in
                let lhsPriority = realtimeSpeechPriority(lhs)
                let rhsPriority = realtimeSpeechPriority(rhs)
                if lhsPriority == rhsPriority {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhsPriority < rhsPriority
            }
    }

    private func realtimeSpeechPriority(_ model: ModelDescriptor) -> Int {
        switch model.capabilities.speech?.family {
        case .funASRMLTNano:
            return 0
        case .funASRNano:
            return 1
        case .senseVoiceSmall:
            return 2
        case .qwen3ASR06B:
            return 3
        case .qwen3ASRSherpaOnnx, .vibeVoiceASR, .whisperCppCoreML, .customLocal, .none:
            return 4
        }
    }

    func ocrModelDisplayName(limit: Int = 18) -> String {
        let resolvedName = selectedOCRModel?.name ?? t("No model configured")
        return Self.condensedModelName(resolvedName, limit: limit)
    }

    static func condensedModelName(_ name: String, limit: Int = 18) -> String {
        let trimmed = name
            .replacingOccurrences(of: "-MLX-4bit", with: "")
            .replacingOccurrences(of: "-MLX-8bit", with: "")
            .replacingOccurrences(of: "-GGUF", with: "")
            .replacingOccurrences(of: "Qwen3.5-", with: "Q3.5-")
            .replacingOccurrences(of: "Qwen3.6-", with: "Q3.6-")
        guard trimmed.count > limit else {
            return trimmed
        }
        return String(trimmed.prefix(limit - 1)) + "…"
    }
}
