import Foundation
import ServiceManagement
import SwiftUI
import LLMTranslateCore

@MainActor
final class AppState: ObservableObject {
    enum InputOrigin: Equatable {
        case selection
        case manual
        case file
    }

    @Published var models: [ModelDescriptor] = []
    @Published var preferences = AppPreferences()
    @Published var history: [HistoryItem] = []
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
    @Published var validationError: String?

    let engine: TaskEngine
    private var preferenceSaveRevision = 0
    private var currentRunTask: Task<Void, Never>?
    private var runRevision = 0

    init(engine: TaskEngine = TaskEngine()) {
        self.engine = engine
    }

    func bootstrap() async {
        await engine.bootstrap()
        let snapshot = await engine.registry()
        var preferences = snapshot.preferences
        clearMissingWebPageModelPreference(&preferences, models: snapshot.models)
        self.models = snapshot.models
        self.preferences = preferences
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
        models = snapshot.models
        self.preferences = preferences
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

    func prepareAutomaticSelectionText(_ text: String) -> Bool {
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
        runRevision += 1
        let revision = runRevision
        let request = TaskRequest(
            task: selectedTask,
            inputText: text,
            targetLanguage: preferences.defaultTranslationTarget,
            polishStyle: preferences.defaultPolishStyle
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
            Task {
                await engine.unloadAll()
            }
        }
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
        if let modelID = preferences.webPageTranslation.modelID,
           models.contains(where: { $0.id == modelID && $0.enabled }) {
            return modelID
        }
        return selectedModelID
            ?? preferences.defaultModelID
            ?? models.first(where: { $0.enabled })?.id
    }

    func webPageTranslationModelDisplayName(limit: Int = 18) -> String {
        let resolvedName = webPageTranslationModelID.flatMap { modelID in
            models.first(where: { $0.id == modelID })?.name
        } ?? t("No model configured")
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
