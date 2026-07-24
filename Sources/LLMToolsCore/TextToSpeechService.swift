import Foundation
import Darwin

public actor LocalTTSService {
    private var session: TTSProcessSession?
    private var activeVariant: TTSModelVariant?

    public init() {}

    public func health(for variant: TTSModelVariant) -> TTSRuntimeHealth {
        let pythonURL = Self.pythonURL()
        let modelURL = Self.modelURL(for: variant)
        let runtimeReady = FileManager.default.isExecutableFile(atPath: pythonURL.path)
            && Self.voxCPM2ModuleExists(venvURL: pythonURL.deletingLastPathComponent().deletingLastPathComponent())
        let modelReady = Self.modelFilesAreComplete(at: modelURL)
        let status: TTSRuntimeStatus
        let message: String
        if !runtimeReady {
            status = .runtimeMissing
            message = "需要安装独立的 mlx-audio TTS runtime。"
        } else if !modelReady {
            status = .modelMissing
            message = "\(variant.displayName) 权重缺失或仍在下载。"
        } else {
            status = .ready
            message = "\(variant.displayName) 与本地 TTS runtime 已就绪。"
        }
        return TTSRuntimeHealth(
            status: status,
            modelVariant: variant,
            runtimePath: pythonURL.path,
            modelPath: modelURL.path,
            message: message
        )
    }

    public func generate(
        _ request: TTSGenerationRequest,
        variant: TTSModelVariant
    ) async throws -> TTSGenerationResult {
        let health = health(for: variant)
        switch health.status {
        case .runtimeMissing:
            throw TTSError.runtimeMissing(health.message)
        case .modelMissing:
            throw TTSError.modelMissing(health.message)
        case .failed:
            throw TTSError.generationFailed(health.message)
        case .ready:
            break
        }
        return try await withTaskCancellationHandler {
            let activeSession = try await ensureSession(for: variant)
            return try await activeSession.generate(request)
        } onCancel: {
            Task { [weak self] in
                await self?.stop()
            }
        }
    }

    public func stop() {
        session?.stop()
    }

    public func stopAndWait() async {
        let activeSession = session
        session = nil
        activeVariant = nil
        await activeSession?.stopAndWait()
    }

    private func ensureSession(for variant: TTSModelVariant) async throws -> TTSProcessSession {
        if activeVariant == variant, let session, session.isRunning {
            return session
        }
        await stopAndWait()
        let newSession = try TTSProcessSession(
            pythonURL: Self.pythonURL(),
            sidecarURL: try Self.sidecarURL(),
            modelURL: Self.modelURL(for: variant)
        )
        session = newSession
        activeVariant = variant
        do {
            try await newSession.waitUntilReady()
        } catch {
            newSession.stop()
            if session === newSession {
                session = nil
                activeVariant = nil
            }
            throw error
        }
        return newSession
    }

    public nonisolated static func modelURL(for variant: TTSModelVariant) -> URL {
        if let configured = ProcessInfo.processInfo.environment["LLMTOOLS_TTS_MODEL_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath, isDirectory: true)
        }
        let candidates = [
            AppPaths.ttsModelsDirectory.appendingPathComponent(variant.modelDirectoryName, isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("code/models/mlx-community", isDirectory: true)
                .appendingPathComponent(variant.modelDirectoryName, isDirectory: true)
        ]
        return candidates.first(where: { modelFilesAreComplete(at: $0) })
            ?? candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            ?? candidates[0]
    }

    public nonisolated static func modelFilesAreComplete(at modelURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelURL.appendingPathComponent("config.json").path) else {
            return false
        }
        let indexURL = modelURL.appendingPathComponent("model.safetensors.index.json")
        if let data = try? Data(contentsOf: indexURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weightMap = root["weight_map"] as? [String: String] {
            let files = Set(weightMap.values)
            return !files.isEmpty && files.allSatisfy {
                fileManager.fileExists(atPath: modelURL.appendingPathComponent($0).path)
            }
        }
        return fileManager.fileExists(atPath: modelURL.appendingPathComponent("model.safetensors").path)
    }

    private nonisolated static func pythonURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["LLMTOOLS_TTS_PYTHON"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        return AppPaths.ttsRuntimeDirectory
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin/python", isDirectory: false)
    }

    private nonisolated static func sidecarURL() throws -> URL {
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("tts", isDirectory: true)
                .appendingPathComponent("llmtools-tts-sidecar.py"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-tts-sidecar.py")
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw TTSError.runtimeMissing("TTS sidecar 未包含在 app 中。")
        }
        return url
    }

    private nonisolated static func voxCPM2ModuleExists(venvURL: URL) -> Bool {
        let libURL = venvURL.appendingPathComponent("lib", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: libURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        let suffix = "/site-packages/mlx_audio/tts/models/voxcpm2"
        while let item = enumerator.nextObject() as? URL {
            if item.path.hasSuffix(suffix) { return true }
        }
        return false
    }
}

private final class TTSProcessSession: @unchecked Sendable {
    private let process: Process
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private let requestLock = NSLock()
    private let processLifecycle = PersistentProcessLifecycle()
    private let stderrLock = NSLock()
    private var stderrData = Data()

    var isRunning: Bool {
        process.isRunning && !processLifecycle.isStopped
    }

    init(pythonURL: URL, sidecarURL: URL, modelURL: URL) throws {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [sidecarURL.path, "--model", modelURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading
        errorHandle = errorPipe.fileHandleForReading
        errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.appendStderr(data) }
        }
        do {
            try process.run()
        } catch {
            errorHandle.readabilityHandler = nil
            throw TTSError.runtimeMissing(error.localizedDescription)
        }
    }

    deinit { stop() }

    func waitUntilReady() async throws {
        try await Task.detached(priority: .userInitiated) { [self] in
            while true {
                let event = try readEvent()
                if event.type == "ready", event.available != false { return }
                if event.type == "error" {
                    throw TTSError.runtimeMissing(event.message ?? "TTS sidecar 启动失败。")
                }
            }
        }.value
    }

    func generate(_ request: TTSGenerationRequest) async throws -> TTSGenerationResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            try generateSync(request)
        }.value
    }

    func stop() {
        processLifecycle.stop(process: process, inputHandle: inputHandle, errorHandle: errorHandle)
    }

    func stopAndWait() async {
        stop()
        await Task.detached(priority: .utility) { [process] in
            for _ in 0..<30 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning { process.terminate() }
            for _ in 0..<10 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }.value
    }

    private func generateSync(_ request: TTSGenerationRequest) throws -> TTSGenerationResult {
        requestLock.lock()
        defer { requestLock.unlock() }
        guard isRunning else { throw TTSError.generationFailed("TTS sidecar 已停止。") }
        let requestID = UUID().uuidString
        try writeJSONLine(TTSSidecarCommand(requestID: requestID, request: request))
        while true {
            let event = try readEvent()
            guard event.requestID == nil || event.requestID == requestID else { continue }
            if event.type == "error" {
                throw TTSError.generationFailed(event.message ?? "VoxCPM2 生成失败。")
            }
            if event.type == "generated",
               let outputPath = event.outputPath,
               let duration = event.duration,
               let sampleRate = event.sampleRate,
               let processingTime = event.processingTime {
                return TTSGenerationResult(
                    outputPath: outputPath,
                    duration: duration,
                    sampleRate: sampleRate,
                    processingTime: processingTime,
                    peakMemoryGB: event.peakMemoryGB
                )
            }
        }
    }

    private func writeJSONLine<T: Encodable>(_ value: T) throws {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func readEvent() throws -> TTSSidecarEvent {
        let line = try readLineSync()
        guard let data = line.data(using: .utf8) else {
            throw TTSError.generationFailed("TTS sidecar 返回了无效文本。")
        }
        do { return try JSONDecoder().decode(TTSSidecarEvent.self, from: data) }
        catch { throw TTSError.generationFailed("TTS sidecar 返回格式错误：\(line)") }
    }

    private func readLineSync() throws -> String {
        var data = Data()
        while true {
            let byte = outputHandle.readData(ofLength: 1)
            if byte.isEmpty {
                let message = lastStderr()
                throw TTSError.generationFailed(message.isEmpty ? "TTS sidecar 意外退出。" : message)
            }
            if byte.first == 0x0A { break }
            data.append(byte)
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func appendStderr(_ data: Data) {
        stderrLock.lock()
        stderrData.append(data)
        if stderrData.count > 32_768 { stderrData.removeFirst(stderrData.count - 32_768) }
        stderrLock.unlock()
    }

    private func lastStderr() -> String {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        return String(data: Data(stderrData.suffix(8_192)), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct TTSSidecarCommand: Encodable {
    var protocolName = "llmtools.tts/v1"
    var command = "generate"
    var requestID: String
    var text: String
    var instruction: String?
    var referenceAudioPath: String?
    var referenceText: String?
    var outputPath: String
    var inferenceTimesteps: Int
    var guidance: Double
    var seed: UInt64

    init(requestID: String, request: TTSGenerationRequest) {
        self.requestID = requestID
        text = request.text
        instruction = request.instruction
        referenceAudioPath = request.referenceAudioURL?.path
        referenceText = request.referenceText
        outputPath = request.outputURL.path
        inferenceTimesteps = request.inferenceTimesteps
        guidance = request.guidance
        seed = request.seed
    }

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case command, requestID, text, instruction, referenceAudioPath, referenceText
        case outputPath, inferenceTimesteps, guidance, seed
    }
}

private struct TTSSidecarEvent: Decodable {
    var type: String
    var requestID: String?
    var available: Bool?
    var outputPath: String?
    var duration: TimeInterval?
    var sampleRate: Int?
    var processingTime: TimeInterval?
    var peakMemoryGB: Double?
    var message: String?
}
