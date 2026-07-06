import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import LLMToolsCore

@MainActor
final class AppState: ObservableObject {
    private static let modelIdleUnloadDelayNanoseconds: UInt64 = 30 * 1_000_000_000

    enum InputOrigin: Equatable {
        case selection
        case manual
        case file
    }

    enum QuickActionMode: String, Equatable {
        case text
        case image
    }

    private struct QuickActionOutputState {
        var outputText: String = ""
        var rawOutputText: String = ""
        var showsRawOutput: Bool = false
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

    let engine: TaskEngine
    private var preferenceSaveRevision = 0
    private var currentRunTask: Task<Void, Never>?
    private var runRevision = 0
    private var activeExternalModelUseCount = 0
    private var scheduledModelUnloadTask: Task<Void, Never>?
    private var textOutputState = QuickActionOutputState()
    private var imageOutputState = QuickActionOutputState()

    init(engine: TaskEngine = TaskEngine()) {
        self.engine = engine
    }

    func bootstrap() async {
        await engine.bootstrap()
        let snapshot = await engine.registry()
        var preferences = snapshot.preferences
        clearMissingWebPageModelPreference(&preferences, models: snapshot.models)
        clearMissingOCRModelPreference(&preferences, models: snapshot.models)
        self.models = snapshot.models
        self.preferences = preferences
        self.ocrMode = preferences.ocr.defaultMode
        self.selectedModelID = preferences.defaultModelID ?? snapshot.models.first?.id
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
        models = snapshot.models
        self.preferences = preferences
        if !OCRMode.allCases.contains(ocrMode) {
            ocrMode = preferences.ocr.defaultMode
        }
        if let currentModelID, snapshot.models.contains(where: { $0.id == currentModelID }) {
            selectedModelID = currentModelID
        } else {
            selectedModelID = preferences.defaultModelID ?? snapshot.models.first?.id
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
        guard models.contains(where: { $0.id == id }) else {
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
                    statusMessage = t("Finished")
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
                    statusMessage = t("Finished")
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

    private func clearMissingWebPageModelPreference(
        _ preferences: inout AppPreferences,
        models: [ModelDescriptor]
    ) {
        guard let modelID = preferences.webPageTranslation.modelID else {
            return
        }
        if !models.contains(where: { $0.id == modelID && $0.enabled }) {
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
        }
    }

    private func restoreOutputState(for mode: QuickActionMode) {
        let state: QuickActionOutputState
        switch mode {
        case .text:
            state = textOutputState
        case .image:
            state = imageOutputState
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
           let model = models.first(where: { $0.id == selectedModelID && $0.enabled }) {
            return model.contextLength
        }
        if let defaultModelID = preferences.defaultModelID,
           let model = models.first(where: { $0.id == defaultModelID && $0.enabled }) {
            return model.contextLength
        }
        return models.first(where: { $0.enabled })?.contextLength
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
           let selectedModel = models.first(where: { $0.id == selectedModelID && $0.enabled }) {
            return selectedModel
        }
        if let defaultModelID = preferences.defaultModelID,
           let defaultModel = models.first(where: { $0.id == defaultModelID && $0.enabled }) {
            return defaultModel
        }
        return models.first(where: { $0.enabled })
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

    var selectedOCRModel: ModelDescriptor? {
        guard let modelID = preferences.ocr.modelID else {
            return nil
        }
        return models.first { $0.id == modelID && $0.enabled && $0.capabilities.supportsImage }
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
