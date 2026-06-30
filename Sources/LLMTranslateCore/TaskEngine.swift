import Foundation

public actor TaskEngine {
    private let registryStore: RegistryStore
    private let historyStore: HistoryStore
    private var snapshot: RegistrySnapshot
    private var history: [HistoryItem]
    private var runners: [ModelFormat: any ModelRunner]

    public init(
        registryStore: RegistryStore = RegistryStore(),
        historyStore: HistoryStore = HistoryStore(),
        runners: [ModelFormat: any ModelRunner] = [:]
    ) {
        self.registryStore = registryStore
        self.historyStore = historyStore
        self.snapshot = .init()
        self.history = []
        self.runners = runners
    }

    public func bootstrap() async {
        do {
            snapshot = try await registryStore.load()
        } catch {
            snapshot = .init()
        }

        do {
            history = try await historyStore.load()
        } catch {
            history = []
        }
    }

    public func registry() -> RegistrySnapshot {
        snapshot
    }

    public func recentHistory() -> [HistoryItem] {
        history
    }

    public func addModel(from url: URL, name: String? = nil, role: ModelRole? = nil) async throws -> ModelDescriptor {
        let detection = try ModelDetection.detect(from: url)
        let displayName = name ?? inferDisplayName(from: url)
        let inferredRole: ModelRole = role ?? inferRole(format: detection.format, sizeClass: detection.sizeClass)
        let inferredContext = inferContextLength(format: detection.format, sizeClass: detection.sizeClass)
        let descriptor = ModelDescriptor(
            name: displayName,
            sourcePath: url,
            resolvedPath: detection.resolvedPath,
            format: detection.format,
            sizeClass: detection.sizeClass,
            role: inferredRole,
            contextLength: inferredContext,
            enabled: true,
            validationState: .valid,
            lastErrorMessage: nil
        )
        snapshot.models.append(descriptor)
        if snapshot.preferences.defaultModelID == nil {
            snapshot.preferences.defaultModelID = descriptor.id
        }
        try await registryStore.save(snapshot)
        return descriptor
    }

    public func removeModel(id: UUID) async throws {
        snapshot.models.removeAll { $0.id == id }
        if snapshot.preferences.defaultModelID == id {
            snapshot.preferences.defaultModelID = snapshot.models.first?.id
        }
        try await registryStore.save(snapshot)
    }

    public func updatePreferences(_ transform: (inout AppPreferences) -> Void) async throws {
        transform(&snapshot.preferences)
        try await registryStore.save(snapshot)
    }

    public func setPreferences(_ preferences: AppPreferences) async throws {
        snapshot.preferences = preferences
        try await registryStore.save(snapshot)
    }

    public func setRunner(_ runner: any ModelRunner, for format: ModelFormat) {
        runners[format] = runner
    }

    public func warmUpModel(id: UUID) async throws {
        guard let model = snapshot.models.first(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        let runner = try runner(for: model)
        if await runner.loadedModelID() != model.id {
            await runner.unload()
            try await runner.load(model: model)
        }
    }

    public func run(request: TaskRequest, modelID: UUID? = nil) async throws -> TaskResult {
        let model = try resolveModel(for: modelID)
        try validateInputSize(request, for: model)
        let runner = try runner(for: model)
        if await runner.loadedModelID() != model.id {
            await runner.unload()
            try await runner.load(model: model)
        }
        let result = try await runner.generate(request: request, preferences: snapshot.preferences)
        appendHistory(model: model, result: result, request: request)
        return result
    }

    public func clearHistory() async throws {
        history = []
        try await historyStore.save(history)
    }

    public func unloadAll() async {
        for runner in runners.values {
            await runner.unload()
        }
        runners.removeAll()
    }

    private func resolveModel(for modelID: UUID?) throws -> ModelDescriptor {
        if let modelID, let model = snapshot.models.first(where: { $0.id == modelID && $0.enabled }) {
            return model
        }
        if let preferred = snapshot.preferences.defaultModelID,
           let model = snapshot.models.first(where: { $0.id == preferred && $0.enabled }) {
            return model
        }
        if let firstEnabled = snapshot.models.first(where: { $0.enabled }) {
            return firstEnabled
        }
        throw RunnerError.unsupportedConfiguration("No enabled model is registered.")
    }

    private func validateInputSize(_ request: TaskRequest, for model: ModelDescriptor) throws {
        let limit = InputSizePolicy.maximumInputCharacters(forContextLength: model.contextLength)
        let current = request.inputText.count
        guard current <= limit else {
            throw RunnerError.inputTooLong(current: current, limit: limit)
        }
    }

    private func runner(for model: ModelDescriptor) throws -> any ModelRunner {
        if let runner = runners[model.format] {
            return runner
        }
        switch model.format {
        case .gguf:
            let runner = GGUFRunner()
            runners[.gguf] = runner
            return runner
        case .mlx:
            let runner = MLXRunner()
            runners[.mlx] = runner
            return runner
        case .unknown:
            throw RunnerError.unsupportedFormat(model.format)
        }
    }

    private func appendHistory(model: ModelDescriptor, result: TaskResult, request: TaskRequest) {
        let entry = HistoryItem(
            task: request.task,
            modelName: model.name,
            inputPreview: request.inputText.prefix(160).description,
            outputPreview: result.text.prefix(240).description
        )
        history.insert(entry, at: 0)
        let limit = max(snapshot.preferences.recentHistoryLimit, 0)
        if history.count > limit {
            history = Array(history.prefix(limit))
        }
        let itemsToSave = history
        Task {
            try? await historyStore.save(itemsToSave)
        }
    }

    private func inferRole(format: ModelFormat, sizeClass: String) -> ModelRole {
        if sizeClass == "0.8b" || sizeClass == "1.5b" {
            return .fast
        }
        if sizeClass == "9b" || sizeClass == "14b" || sizeClass == "27b" {
            return .quality
        }
        if format == .gguf {
            return .fast
        }
        return .default
    }

    private func inferContextLength(format: ModelFormat, sizeClass: String) -> Int {
        if format == .gguf && (sizeClass == "0.8b" || sizeClass == "1.5b") {
            return 4096
        }
        return 8192
    }

    private func inferDisplayName(from url: URL) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url.lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
