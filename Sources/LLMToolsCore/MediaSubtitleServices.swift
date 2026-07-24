import Foundation
import UniformTypeIdentifiers

public enum MediaSubtitleError: Error, LocalizedError, Sendable {
    case disabled
    case unsupportedFileFormat(String)
    case extractionFailed(String)
    case missingASRModel
    case asrRuntimeMissing(String)
    case asrModelMissing(String)
    case asrRuntimeFailed(String)
    case translationFailed(String)
    case exportFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Media subtitles are disabled."
        case .unsupportedFileFormat(let message):
            return message
        case .extractionFailed(let message):
            return "Audio extraction failed: \(message)"
        case .missingASRModel:
            return "Choose a local speech ASR model first."
        case .asrRuntimeMissing(let message):
            return message
        case .asrModelMissing(let message):
            return message
        case .asrRuntimeFailed(let message):
            return "ASR runtime failed: \(message)"
        case .translationFailed(let message):
            return "Subtitle translation failed: \(message)"
        case .exportFailed(let message):
            return "Subtitle export failed: \(message)"
        case .cancelled:
            return "Media subtitle task cancelled."
        }
    }
}

public struct MediaSubtitleFileResult: Sendable, Hashable {
    public var descriptor: MediaFileDescriptor
    public var normalizedAudioURL: URL
    public var segments: [SubtitleSegment]
    public var diagnostics: MediaSubtitleDiagnostics

    public init(
        descriptor: MediaFileDescriptor,
        normalizedAudioURL: URL,
        segments: [SubtitleSegment],
        diagnostics: MediaSubtitleDiagnostics
    ) {
        self.descriptor = descriptor
        self.normalizedAudioURL = normalizedAudioURL
        self.segments = segments
        self.diagnostics = diagnostics
    }
}

public enum MediaIntakeService {
    public static func descriptor(for url: URL) throws -> MediaFileDescriptor {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaSubtitleError.unsupportedFileFormat("File does not exist: \(url.lastPathComponent)")
        }
        let type = UTType(filenameExtension: url.pathExtension)
        let isAudio = type?.conforms(to: .audio) == true
        let isVideo = type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true
        guard isAudio || isVideo else {
            throw MediaSubtitleError.unsupportedFileFormat("Unsupported media file: \(url.lastPathComponent)")
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int64
        return MediaFileDescriptor(
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            mediaKind: isVideo ? "video" : "audio",
            duration: nil,
            sizeBytes: size,
            redactedPathHash: redactedHash(url.path)
        )
    }

    public static func isSupportedMediaFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .video)
    }

    public static func redactedHash(_ value: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for scalar in value.unicodeScalars {
            hash ^= UInt32(scalar.value)
            hash = hash &* 0x01000193
        }
        return "h" + String(hash, radix: 16)
    }
}

public struct NormalizedAudioFile: Sendable, Hashable {
    public var url: URL
    public var duration: TimeInterval?
    public var sampleRate: Int
    public var channelCount: Int
}

public struct ASRTranscriptionContext: Sendable, Hashable {
    public var mode: SpeechRuntimeMode
    public var sourceLanguageHint: ASRSourceLanguageHint
    public var isFinal: Bool
    public var maximumTokens: Int?
    public var chunkDurationSeconds: Int?

    public init(
        mode: SpeechRuntimeMode = .fileOnly,
        sourceLanguageHint: ASRSourceLanguageHint = .auto,
        isFinal: Bool = true,
        maximumTokens: Int? = nil,
        chunkDurationSeconds: Int? = nil
    ) {
        self.mode = mode
        self.sourceLanguageHint = sourceLanguageHint
        self.isFinal = isFinal
        self.maximumTokens = maximumTokens.map { max(1, $0) }
        self.chunkDurationSeconds = chunkDurationSeconds.map { max(1, $0) }
    }
}

public enum AudioExtractionService {
    public static func normalizeMediaFile(
        at url: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        audioConverterPath: String = "/usr/bin/afconvert",
        videoConverterPath: String = "/usr/bin/avconvert"
    ) async throws -> NormalizedAudioFile {
        try Task.checkCancellation()
        let descriptor = try MediaIntakeService.descriptor(for: url)
        let workingDirectory = temporaryDirectory
            .appendingPathComponent("llmtools-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workingDirectory.path)
        var transferredToCaller = false
        defer {
            if !transferredToCaller {
                try? FileManager.default.removeItem(at: workingDirectory)
            }
        }
        let audioInputURL: URL

        if descriptor.mediaKind == "video" {
            let extracted = workingDirectory.appendingPathComponent("extracted.m4a")
            try await runProcess(
                executablePath: videoConverterPath,
                arguments: [
                    "--source", url.path,
                    "--preset", "PresetAppleM4A",
                    "--output", extracted.path,
                    "--replace"
                ]
            )
            try Task.checkCancellation()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: extracted.path)
            audioInputURL = extracted
        } else {
            audioInputURL = url
        }

        let wavURL = workingDirectory.appendingPathComponent("normalized-16k-mono.wav")
        try await runProcess(
            executablePath: audioConverterPath,
            arguments: [
                audioInputURL.path,
                wavURL.path,
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1"
            ]
        )
        try Task.checkCancellation()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: wavURL.path)
        let duration = wavDuration(url: wavURL)
        let normalized = NormalizedAudioFile(
            url: wavURL,
            duration: duration,
            sampleRate: 16_000,
            channelCount: 1
        )
        transferredToCaller = true
        return normalized
    }

    private static func runProcess(executablePath: String, arguments: [String]) async throws {
        try Task.checkCancellation()
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw MediaSubtitleError.extractionFailed("\(executablePath) is not available.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        let processHandle = CancellableProcessHandle(process: process)
        try await withTaskCancellationHandler {
            do {
                try processHandle.run()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MediaSubtitleError.extractionFailed(error.localizedDescription)
            }
            async let errorData = readPipeToEnd(errorPipe)
            process.waitUntilExit()
            let capturedError = await errorData
            try Task.checkCancellation()
            if process.terminationStatus != 0 {
                let message = String(data: capturedError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw MediaSubtitleError.extractionFailed(message?.isEmpty == false ? message! : "exit \(process.terminationStatus)")
            }
        } onCancel: {
            processHandle.cancel()
        }
    }

    private static func readPipeToEnd(_ pipe: Pipe) async -> Data {
        await Task.detached(priority: .utility) {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }

    private static func wavDuration(url: URL) -> TimeInterval? {
        guard let data = try? Data(contentsOf: url),
              data.count >= 44 else {
            return nil
        }
        let sampleRate = littleEndianUInt32(data, offset: 24)
        let byteRate = littleEndianUInt32(data, offset: 28)
        guard sampleRate > 0, byteRate > 0 else {
            return nil
        }
        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let chunkSize = littleEndianUInt32(data, offset: offset + 4)
            offset += 8
            if chunkID == "data" {
                return TimeInterval(chunkSize) / TimeInterval(byteRate)
            }
            offset += Int(chunkSize)
        }
        return nil
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else {
            return 0
        }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

public struct LocalASRProcessRunner: Sendable {
    public init() {}

    public func health(
        for model: ModelDescriptor,
        preferences: MediaSubtitlePreferences = MediaSubtitlePreferences(),
        mode: SpeechRuntimeMode = .fileOnly
    ) -> ASRHealthReport {
        guard model.enabled, model.capabilities.supportsSpeech, let speech = model.capabilities.speech else {
            return ASRHealthReport(
                modelID: model.id,
                modelName: model.name,
                family: model.capabilities.speech?.family,
                status: .incompatibleModel,
                isRealtimeCapable: false,
                isFileCapable: false,
                runtimeSource: .unavailable,
                message: "\(model.name) is not marked speech-capable."
            )
        }
        guard FileManager.default.fileExists(atPath: model.sourcePath.path) else {
            return ASRHealthReport(
                modelID: model.id,
                modelName: model.name,
                family: speech.family,
                status: .modelMissing,
                isRealtimeCapable: speech.supports(.realtime),
                isFileCapable: speech.supports(.fileOnly),
                runtimeSource: .unavailable,
                message: "ASR model path is missing: \(model.sourcePath.lastPathComponent)"
            )
        }
        if fixtureTranscriptURL() != nil {
            return ASRHealthReport(
                modelID: model.id,
                modelName: model.name,
                family: speech.family,
                status: .ready,
                isRealtimeCapable: speech.supports(.realtime),
                isFileCapable: speech.supports(.fileOnly),
                runtimeSource: .fixtureTranscript,
                message: "Local ASR fixture transcript is configured for verification."
            )
        }
        if mode == .realtime {
            guard speech.supports(.realtime) else {
                return ASRHealthReport(
                    modelID: model.id,
                    modelName: model.name,
                    family: speech.family,
                    status: .incompatibleModel,
                    isRealtimeCapable: false,
                    isFileCapable: speech.supports(.fileOnly),
                    runtimeSource: .unavailable,
                    message: "\(model.name) is not marked realtime-capable."
                )
            }
            if speech.family == .nemotron35ASRStreaming06B,
               ModelDetection.isNemotronStreamingCoreMLModel(at: model.resolvedPath ?? model.sourcePath) {
                return ASRHealthReport(
                    modelID: model.id,
                    modelName: model.name,
                    family: speech.family,
                    status: .ready,
                    isRealtimeCapable: true,
                    isFileCapable: false,
                    runtimeSource: .fluidAudioNemotronCoreML,
                    message: "Local FluidAudio/Core ML Nemotron streaming session is available."
                )
            }
            if let streamingHealth = StreamingASRProcessSession.realtimeHealth(for: model, family: speech.family) {
                return ASRHealthReport(
                    modelID: model.id,
                    modelName: model.name,
                    family: speech.family,
                    status: .ready,
                    isRealtimeCapable: true,
                    isFileCapable: speech.supports(.fileOnly),
                    runtimeSource: streamingHealth.source,
                    message: streamingHealth.message
                )
            }
            return ASRHealthReport(
                modelID: model.id,
                modelName: model.name,
                family: speech.family,
                status: .runtimeMissing,
                isRealtimeCapable: true,
                isFileCapable: speech.supports(.fileOnly),
                runtimeSource: .unavailable,
                message: "Local streaming ASR sidecar is not available for \(model.name). \(runtimeMissingMessage(for: model, family: speech.family))"
            )
        }
        guard let resolution = commandResolution(
            for: model,
            family: speech.family,
            preferences: preferences,
            mode: mode
        ) else {
            return ASRHealthReport(
                modelID: model.id,
                modelName: model.name,
                family: speech.family,
                status: .runtimeMissing,
                isRealtimeCapable: speech.supports(.realtime),
                isFileCapable: speech.supports(.fileOnly),
                runtimeSource: .unavailable,
                message: runtimeMissingMessage(for: model, family: speech.family)
            )
        }
        return ASRHealthReport(
            modelID: model.id,
            modelName: model.name,
            family: speech.family,
            status: .ready,
            isRealtimeCapable: speech.supports(.realtime),
            isFileCapable: speech.supports(.fileOnly),
            runtimeSource: resolution.source,
            message: resolution.readyMessage
        )
    }

    public func transcribe(
        audioURL: URL,
        model: ModelDescriptor,
        sessionID: UUID,
        duration: TimeInterval?,
        preferences: MediaSubtitlePreferences = MediaSubtitlePreferences(),
        context: ASRTranscriptionContext = ASRTranscriptionContext()
    ) async throws -> [SubtitleSegment] {
        try Task.checkCancellation()
        var effectiveContext = context
        if effectiveContext.sourceLanguageHint == .auto {
            effectiveContext.sourceLanguageHint = preferences.sourceLanguageHint
        }
        guard let speech = model.capabilities.speech else {
            throw MediaSubtitleError.asrModelMissing("\(model.name) is not speech-capable.")
        }
        if let fixtureURL = fixtureTranscriptURL() {
            return try parseTranscript(data: Data(contentsOf: fixtureURL), model: model, sessionID: sessionID, duration: duration)
        }
        guard let resolution = commandResolution(
            for: model,
            family: speech.family,
            preferences: preferences,
            mode: effectiveContext.mode
        ) else {
            throw MediaSubtitleError.asrRuntimeMissing("No local ASR command is configured for \(model.name).")
        }
        let command = renderCommandTemplate(
            resolution.template,
            audioURL: audioURL,
            model: model,
            family: speech.family,
            context: effectiveContext
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let processHandle = CancellableProcessHandle(process: process)
        return try await withTaskCancellationHandler {
            do {
                try processHandle.run()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MediaSubtitleError.asrRuntimeFailed(error.localizedDescription)
            }
            async let output = Self.readPipeToEnd(outputPipe)
            async let errorOutput = Self.readPipeToEnd(errorPipe)
            process.waitUntilExit()
            let capturedOutput = await output
            let capturedError = await errorOutput
            try Task.checkCancellation()
            if process.terminationStatus != 0 {
                let message = String(data: capturedError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw MediaSubtitleError.asrRuntimeFailed(message?.isEmpty == false ? message! : "exit \(process.terminationStatus)")
            }
            return try parseTranscript(data: capturedOutput, model: model, sessionID: sessionID, duration: duration)
        } onCancel: {
            processHandle.cancel()
        }
    }

    private static func readPipeToEnd(_ pipe: Pipe) async -> Data {
        await Task.detached(priority: .utility) {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }

    private struct ASRCommandResolution: Sendable {
        var template: String
        var source: ASRRuntimeSource

        var readyMessage: String {
            switch source {
            case .settingsCommand:
                return "Local ASR runtime is configured from Media Subtitle settings."
            case .environmentCommand:
                return "Local ASR runtime is configured from llmTools ASR environment variables."
            case .fixtureTranscript:
                return "Local ASR fixture transcript is configured for verification."
            case .mlxAudioRunner:
                return "Local MLX ASR command runtime is available."
            case .sherpaOnnxAuto:
                return "Local sherpa-onnx runtime is available for this ONNX model directory."
            case .sherpaOnnxQwen3Runner:
                return "sherpa-onnx Qwen3-ASR has been removed; use MLX Qwen3-ASR on Apple Silicon."
            case .whisperCppCoreMLRunner:
                return "Local whisper.cpp Core ML runtime is available."
            case .fluidAudioNemotronCoreML:
                return "Local FluidAudio Nemotron Core ML streaming runtime is available."
            case .funASRGGUFAuto:
                return "Local Fun-ASR llama.cpp/GGUF runtime is available."
            case .funASRTorchStreaming:
                return "Official local Fun-ASR-Nano Torch/MPS streaming runtime is available."
            case .funASRCompositePipeline:
                return "Official local FunASR Nano + VAD + CAM++ pipeline is available for file transcription."
            case .vibeVoiceASRRunner:
                return "Local VibeVoice-ASR rich transcription runtime is available."
            case .unavailable:
                return "Local ASR runtime is not configured."
            }
        }
    }

    private func commandResolution(
        for model: ModelDescriptor,
        family: SpeechModelFamily,
        preferences: MediaSubtitlePreferences,
        mode: SpeechRuntimeMode
    ) -> ASRCommandResolution? {
        if let command = preferences.commandTemplate(for: family) {
            return ASRCommandResolution(template: command, source: .settingsCommand)
        }
        let env = ProcessInfo.processInfo.environment
        switch family {
        case .funASRNano, .funASRMLTNano:
            if let value = nonEmpty(env["LLMTOOLS_FUN_ASR_COMMAND"]) {
                return ASRCommandResolution(template: value, source: .environmentCommand)
            }
        case .senseVoiceSmall:
            if let value = nonEmpty(env["LLMTOOLS_SENSEVOICE_COMMAND"]) {
                return ASRCommandResolution(template: value, source: .environmentCommand)
            }
        case .qwen3ASR06B:
            if let value = nonEmpty(env["LLMTOOLS_QWEN3_ASR_COMMAND"]) {
                return ASRCommandResolution(template: value, source: .environmentCommand)
            }
        case .nemotron35ASRStreaming06B:
            break
        case .qwen3ASRSherpaOnnx:
            return nil
        case .vibeVoiceASR:
            if let value = nonEmpty(env["LLMTOOLS_VIBEVOICE_ASR_COMMAND"]) {
                return ASRCommandResolution(template: value, source: .environmentCommand)
            }
        case .whisperCppCoreML:
            if let value = nonEmpty(env["LLMTOOLS_WHISPER_CPP_COMMAND"]) {
                return ASRCommandResolution(template: value, source: .environmentCommand)
            }
        case .customLocal:
            break
        }
        if let value = nonEmpty(env["LLMTOOLS_ASR_COMMAND"]) {
            return ASRCommandResolution(template: value, source: .environmentCommand)
        }
        let modelURL = model.resolvedPath ?? model.sourcePath
        if mode == .fileOnly,
           family == .funASRNano,
           let pipelineTemplate = funASRCompositeCommandTemplate(modelURL: modelURL) {
            return ASRCommandResolution(template: pipelineTemplate, source: .funASRCompositePipeline)
        }
        if (family == .funASRNano || family == .funASRMLTNano),
           let funASRTemplate = funASRGGUFCommandTemplate(modelURL: modelURL) {
            return ASRCommandResolution(template: funASRTemplate, source: .funASRGGUFAuto)
        }
        if family == .whisperCppCoreML,
           let whisperTemplate = whisperCppCoreMLCommandTemplate(modelURL: modelURL) {
            return ASRCommandResolution(template: whisperTemplate, source: .whisperCppCoreMLRunner)
        }
        if (family == .funASRNano || family == .funASRMLTNano || family == .senseVoiceSmall || family == .qwen3ASR06B || family == .vibeVoiceASR),
           safetensorsModelFilesExist(at: modelURL),
           (family != .vibeVoiceASR || vibeVoiceTokenizerFilesExist(for: modelURL)),
           let mlxAudioTemplate = mlxAudioCommandTemplate(for: family) {
            return ASRCommandResolution(template: mlxAudioTemplate, source: .mlxAudioRunner)
        }
        if family == .senseVoiceSmall,
           FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("model.onnx").path),
           FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("tokens.txt").path),
           let sherpaPath = executableInPATH("sherpa-onnx-offline") {
            return ASRCommandResolution(
                template: "\(shellEscape(sherpaPath)) --tokens {model}/tokens.txt --sense-voice-model {model}/model.onnx --input-wav {audio}",
                source: .sherpaOnnxAuto
            )
        }
        return nil
    }

    private func funASRCompositeCommandTemplate(modelURL: URL) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelURL.appendingPathComponent("model.pt").path),
              fileManager.fileExists(atPath: modelURL.appendingPathComponent("config.yaml").path) else {
            return nil
        }
        let root = AppPaths.funASRPipelineRuntimeDirectory
        let venvPath = root.appendingPathComponent("venv", isDirectory: true).path
        let pythonPath = URL(fileURLWithPath: venvPath).appendingPathComponent("bin/python").path
        let requiredModels = [
            (directory: "fsmn-vad", checkpoint: "model.pt"),
            (directory: "campp", checkpoint: "campplus_cn_common.bin"),
            (directory: "ct-punc", checkpoint: "model.pt")
        ]
        guard fileManager.isExecutableFile(atPath: pythonPath),
              pythonModuleExists(in: venvPath, moduleName: "funasr"),
              requiredModels.allSatisfy({ model in
                  let directory = root
                      .appendingPathComponent("models", isDirectory: true)
                      .appendingPathComponent(model.directory, isDirectory: true)
                  return fileManager.fileExists(atPath: directory.appendingPathComponent("config.yaml").path)
                      && fileManager.fileExists(atPath: directory.appendingPathComponent(model.checkpoint).path)
              }),
              let sidecarPath = funASRCompositeSidecarPath() else {
            return nil
        }
        return "LLMTOOLS_FUNASR_PIPELINE_ROOT=\(shellEscape(root.path)) \(shellEscape(pythonPath)) \(shellEscape(sidecarPath)) --model {model} --audio {audio} --language {language}"
    }

    private func funASRCompositeSidecarPath() -> String? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("asr", isDirectory: true)
                .appendingPathComponent("llmtools-funasr-pipeline.py")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-funasr-pipeline.py")
                .path
        ].compactMap { $0 }
        return candidates.first { fileManager.fileExists(atPath: $0) }
    }

    private func whisperCppCoreMLCommandTemplate(modelURL: URL) -> String? {
        guard whisperCppModelBin(for: modelURL) != nil,
              let runnerPath = whisperCppCoreMLRunnerPath(),
              let rootPath = whisperCppRuntimeRootPath(),
              whisperCppRuntimeIsReady(rootPath: rootPath, modelURL: modelURL) else {
            return nil
        }
        return "LLMTOOLS_WHISPER_CPP_ROOT=\(shellEscape(rootPath)) \(shellEscape(runnerPath)) --model {model} --audio {audio} --language {language}"
    }

    private func whisperCppCoreMLRunnerPath() -> String? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("asr", isDirectory: true)
                .appendingPathComponent("llmtools-whisper-coreml-runner.sh")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-whisper-coreml-runner.sh")
                .path
        ].compactMap { $0 }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private func whisperCppRuntimeRootPath() -> String? {
        let candidates = [
            nonEmpty(ProcessInfo.processInfo.environment["LLMTOOLS_WHISPER_CPP_ROOT"]),
            AppPaths.asrRuntimeDirectory
                .appendingPathComponent("whisper-cpp", isDirectory: true)
                .path(percentEncoded: false)
        ].compactMap { $0 }
        return candidates.first
    }

    private func whisperCppRuntimeIsReady(rootPath: String, modelURL: URL) -> Bool {
        let fileManager = FileManager.default
        let cliCandidates = [
            URL(fileURLWithPath: rootPath).appendingPathComponent("whisper.cpp/build/bin/whisper-cli").path,
            URL(fileURLWithPath: rootPath).appendingPathComponent("bin/whisper-cli").path
        ]
        guard cliCandidates.contains(where: { fileManager.isExecutableFile(atPath: $0) }),
              let modelBin = whisperCppModelBin(for: modelURL) else {
            return false
        }
        return whisperCppCoreMLDirectory(for: modelBin) != nil
    }

    private func whisperCppModelBin(for modelURL: URL) -> URL? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            let name = modelURL.lastPathComponent.lowercased()
            return modelURL.pathExtension.lowercased() == "bin" && name.hasPrefix("ggml-") ? modelURL : nil
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents
            .filter { $0.pathExtension.lowercased() == "bin" && $0.lastPathComponent.lowercased().hasPrefix("ggml-") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }

    private func whisperCppCoreMLDirectory(for modelBin: URL) -> URL? {
        let stem = modelBin.deletingPathExtension().lastPathComponent
        let compiled = modelBin.deletingLastPathComponent().appendingPathComponent("\(stem)-encoder.mlmodelc", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: compiled.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return compiled
        }
        return nil
    }

    private func funASRGGUFCommandTemplate(modelURL: URL) -> String? {
        guard let cliPath = executableInPATH("llama-funasr-cli") else {
            return nil
        }
        let encoder = firstExistingGGUF(
            in: modelURL,
            preferredNames: [
                "funasr-encoder-f16.gguf",
                "funasr-encoder-q8_0.gguf",
                "funasr-encoder.gguf",
                "fun-asr-mlt-encoder-f16.gguf",
                "fun-asr-mlt-encoder.gguf"
            ],
            requiredTokens: ["encoder"]
        )
        let decoder = firstExistingGGUF(
            in: modelURL,
            preferredNames: [
                "qwen3-0.6b-q8_0.gguf",
                "qwen3-0.6b-q4km.gguf",
                "qwen3-0.6b-f16.gguf",
                "qwen3-0.6b.gguf"
            ],
            requiredTokens: ["qwen3", "0.6b"]
        )
        let vad = firstExistingGGUF(
            in: modelURL,
            preferredNames: [
                "fsmn-vad.gguf",
                "fsmn-vad-q8_0.gguf",
                "fsmn-vad-f16.gguf"
            ],
            requiredTokens: ["fsmn", "vad"]
        )
        guard let encoder, let decoder else {
            return nil
        }
        var parts = [
            shellEscape(cliPath),
            "--enc",
            shellEscape(encoder.path),
            "-m",
            shellEscape(decoder.path),
            "-a",
            "{audio}"
        ]
        if let vad {
            parts.append("--vad")
            parts.append(shellEscape(vad.path))
        }
        return parts.joined(separator: " ")
    }

    private func firstExistingGGUF(
        in directory: URL,
        preferredNames: [String],
        requiredTokens: [String]
    ) -> URL? {
        let fileManager = FileManager.default
        for name in preferredNames {
            let candidate = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let tokens = requiredTokens.map { $0.lowercased() }
        while let element = enumerator.nextObject() {
            guard let url = element as? URL,
                  url.pathExtension.lowercased() == "gguf" else {
                continue
            }
            let name = url.lastPathComponent.lowercased()
            if tokens.allSatisfy({ name.contains($0) }) {
                return url
            }
        }
        return nil
    }

    private func mlxAudioCommandTemplate(for family: SpeechModelFamily) -> String? {
        guard let runnerPath = mlxAudioRunnerPath(),
              let venvPath = mlxAudioVenvPath(for: family) else {
            return nil
        }
        let envName = mlxAudioVenvEnvironmentName(for: family)
        return "LLMTOOLS_ASR_MAX_TOKENS={max_tokens} LLMTOOLS_ASR_CHUNK_DURATION={chunk_duration} \(envName)=\(shellEscape(venvPath)) \(shellEscape(runnerPath)) --model {model} --audio {audio} --language {language}"
    }

    private func mlxAudioRunnerPath() -> String? {
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
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private func mlxAudioVenvPath(for family: SpeechModelFamily) -> String? {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let envKey = mlxAudioVenvEnvironmentName(for: family)
        let directoryName = mlxAudioVenvDirectoryName(for: family)
        let candidates = [
            nonEmpty(env[envKey]),
            AppPaths.asrRuntimeDirectory
                .appendingPathComponent(directoryName, isDirectory: true)
                .path(percentEncoded: false)
        ].compactMap { $0 }
        return candidates.first {
            fileManager.isExecutableFile(atPath: URL(fileURLWithPath: $0).appendingPathComponent("bin/mlx_audio.stt.generate").path)
                && mlxAudioModelModuleExists(in: $0, family: family)
        }
    }

    private func mlxAudioVenvEnvironmentName(for family: SpeechModelFamily) -> String {
        switch family {
        case .funASRMLTNano:
            return "LLMTOOLS_FUN_ASR_VENV"
        case .funASRNano:
            return "LLMTOOLS_FUN_ASR_NANO_VENV"
        case .senseVoiceSmall:
            return "LLMTOOLS_SENSEVOICE_ASR_VENV"
        case .qwen3ASR06B, .nemotron35ASRStreaming06B, .qwen3ASRSherpaOnnx, .vibeVoiceASR:
            return "LLMTOOLS_ASR_VENV"
        case .whisperCppCoreML:
            return "LLMTOOLS_WHISPER_CPP_ROOT"
        case .customLocal:
            return "LLMTOOLS_ASR_VENV"
        }
    }

    private func mlxAudioVenvDirectoryName(for family: SpeechModelFamily) -> String {
        switch family {
        case .funASRMLTNano:
            return "funasr-venv"
        case .funASRNano:
            return "funasr-nano-venv"
        case .senseVoiceSmall:
            return "sensevoice-venv"
        case .qwen3ASR06B, .nemotron35ASRStreaming06B, .qwen3ASRSherpaOnnx, .vibeVoiceASR:
            return "venv"
        case .whisperCppCoreML:
            return "whisper-cpp"
        case .customLocal:
            return "venv"
        }
    }

    private func mlxAudioModelModuleExists(in venvPath: String, family: SpeechModelFamily) -> Bool {
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
        case .nemotron35ASRStreaming06B:
            return false
        case .qwen3ASRSherpaOnnx:
            return false
        case .vibeVoiceASR:
            moduleName = "vibevoice_asr"
        case .whisperCppCoreML:
            return false
        case .customLocal:
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

    private func pythonModuleExists(in venvPath: String, moduleName: String) -> Bool {
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

    private func runtimeMissingMessage(for model: ModelDescriptor, family: SpeechModelFamily) -> String {
        let modelURL = model.resolvedPath ?? model.sourcePath
        var parts = [
            "Configure a local ASR command in Media Subtitle settings, or set LLMTOOLS_FUN_ASR_COMMAND, LLMTOOLS_SENSEVOICE_COMMAND, LLMTOOLS_QWEN3_ASR_COMMAND, LLMTOOLS_VIBEVOICE_ASR_COMMAND, LLMTOOLS_WHISPER_CPP_COMMAND, or LLMTOOLS_ASR_COMMAND."
        ]
        if family == .funASRMLTNano {
            parts.append("Fun-ASR-MLT-Nano covers broad-language realtime transcription; safetensors/MLX directories require the bundled runner plus the isolated Fun-ASR mlx-audio-plus runtime. This route performs ASR only and uses a separate speaker-processing pipeline.")
        } else if family == .funASRNano {
            parts.append("Fun-ASR-Nano covers low-latency Chinese/English/Japanese transcription; safetensors/MLX directories can use the bundled mlx-audio runner, while automatic GGUF detection requires llama-funasr-cli plus Fun-ASR encoder, Qwen3 decoder, and optionally FSMN-VAD GGUF files. Official FunASR speaker diarization additionally composes a CAM++ speaker model and is not enabled by these ASR-only routes.")
        }
        if safetensorsModelFilesExist(at: modelURL) {
            parts.append("This model directory uses safetensors/MLX weights; install the matching local MLX ASR runtime or configure an ASR command for \(family.displayName).")
        }
        if family == .senseVoiceSmall {
            parts.append("SenseVoiceSmall safetensors/MLX directories can use the bundled runner with the isolated SenseVoice mlx-audio runtime. Automatic sherpa-onnx detection requires model.onnx, tokens.txt, and sherpa-onnx-offline in PATH.")
        }
        if family == .qwen3ASR06B {
            parts.append("Official Qwen3-ASR streaming requires the local vLLM backend; configure a vLLM/streaming sidecar for realtime use or use it for file transcription.")
        }
        if family == .nemotron35ASRStreaming06B {
            parts.append("Nemotron 3.5 ASR Streaming requires multilingual FluidAudio Core ML assets on Apple Silicon: metadata.json, tokenizer.json, encoder.mlmodelc, and a decoder/joint bundle.")
        }
        if family == .qwen3ASRSherpaOnnx {
            parts.append("The sherpa-onnx Qwen3-ASR backend has been removed because MLX Qwen3-ASR is faster on Apple Silicon.")
        }
        if family == .vibeVoiceASR {
            parts.append("VibeVoice-ASR is file-only in llmTools. The mlx-community converted model uses the bundled MLX ASR runner with the shared mlx-audio runtime and a local Qwen2.5 tokenizer sidecar; original PyTorch VibeVoice-ASR runtimes can still be configured with a custom command that returns rich JSON segments with text, start/end timestamps, and speaker labels.")
        }
        if family == .whisperCppCoreML {
            parts.append("whisper.cpp Core ML directories require scripts/install-phase4-whisper-coreml-runtime.sh, whisper-cli built with WHISPER_COREML=1, a ggml model file, and its adjacent compiled encoder .mlmodelc directory.")
        }
        return parts.joined(separator: " ")
    }

    private func safetensorsModelFilesExist(at modelURL: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: modelURL.appendingPathComponent("model.safetensors").path)
            || fileManager.fileExists(atPath: modelURL.appendingPathComponent("model.safetensors.index.json").path) {
            return true
        }
        guard let contents = try? fileManager.contentsOfDirectory(at: modelURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return false
        }
        return contents.contains { $0.pathExtension.lowercased() == "safetensors" }
    }

    private func vibeVoiceTokenizerFilesExist(for modelURL: URL) -> Bool {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [modelURL]
        if let configuredTokenizer = nonEmpty(env["LLMTOOLS_VIBEVOICE_TOKENIZER_DIR"]) {
            candidates.append(URL(fileURLWithPath: configuredTokenizer))
        }
        candidates.append(contentsOf: [
            AppPaths.asrRuntimeDirectory
                .appendingPathComponent("qwen2.5-tokenizer", isDirectory: true),
            homeURL
                .appendingPathComponent("code/models/lmstudio-community/Qwen2.5-0.5B-Instruct-MLX-4bit", isDirectory: true),
            homeURL
                .appendingPathComponent("code/models/mlx-community/Qwen3-ASR-0.6B-4bit", isDirectory: true),
            homeURL
                .appendingPathComponent("code/models/mlx-community/Qwen3-ASR-0.6B-bf16", isDirectory: true),
            homeURL
                .appendingPathComponent("code/models/mlx-community/Qwen3-ASR-1.7B-bf16", isDirectory: true)
        ])
        return candidates.contains { url in
            fileManager.fileExists(atPath: url.appendingPathComponent("tokenizer_config.json").path)
                && (fileManager.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path)
                    || fileManager.fileExists(atPath: url.appendingPathComponent("vocab.json").path))
        }
    }

    private func fixtureTranscriptURL() -> URL? {
        guard let value = nonEmpty(ProcessInfo.processInfo.environment["LLMTOOLS_ASR_FIXTURE_JSON"]) else {
            return nil
        }
        let url = URL(fileURLWithPath: value)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func renderCommandTemplate(
        _ template: String,
        audioURL: URL,
        model: ModelDescriptor,
        family: SpeechModelFamily,
        context: ASRTranscriptionContext
    ) -> String {
        template
            .replacingOccurrences(of: "{audio}", with: shellEscape(audioURL.path))
            .replacingOccurrences(of: "{model}", with: shellEscape((model.resolvedPath ?? model.sourcePath).path))
            .replacingOccurrences(of: "{family}", with: family.rawValue)
            .replacingOccurrences(of: "{language}", with: shellEscape(context.sourceLanguageHint.rawValue))
            .replacingOccurrences(of: "{mode}", with: context.mode.rawValue)
            .replacingOccurrences(of: "{isFinal}", with: context.isFinal ? "true" : "false")
            .replacingOccurrences(of: "{max_tokens}", with: String(context.maximumTokens ?? 512))
            .replacingOccurrences(of: "{chunk_duration}", with: String(context.chunkDurationSeconds ?? 30))
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func executableInPATH(_ name: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map(String.init)
        for path in paths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func parseTranscript(
        data: Data,
        model: ModelDescriptor,
        sessionID: UUID,
        duration: TimeInterval?
    ) throws -> [SubtitleSegment] {
        if let envelope = try? JSONDecoder().decode(ASRSidecarEnvelope.self, from: data) {
            return normalizeSidecarSegments(envelope.segments, model: model, sessionID: sessionID, duration: duration)
        }
        if let segments = try? JSONDecoder().decode([ASRSidecarSegment].self, from: data) {
            return normalizeSidecarSegments(segments, model: model, sessionID: sessionID, duration: duration)
        }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw MediaSubtitleError.asrRuntimeFailed("ASR returned an empty transcript.")
        }
        return [
            SubtitleSegment(
                sessionID: sessionID,
                index: 0,
                startTime: 0,
                endTime: duration ?? 2,
                originalText: text,
                sourceLanguage: nil,
                languageConfidence: nil,
                isFinal: true,
                asrModelID: model.id.uuidString
            )
        ]
    }

    private func normalizeSidecarSegments(
        _ rawSegments: [ASRSidecarSegment],
        model: ModelDescriptor,
        sessionID: UUID,
        duration: TimeInterval?
    ) -> [SubtitleSegment] {
        var fallbackStart: TimeInterval = 0
        return rawSegments.enumerated().compactMap { offset, raw in
            let text = raw.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            let start = raw.start ?? fallbackStart
            let end = raw.end ?? min((duration ?? start + 2), start + 2.5)
            fallbackStart = max(end, start + 0.1)
            return SubtitleSegment(
                sessionID: sessionID,
                index: raw.index ?? offset,
                startTime: start,
                endTime: end,
                originalText: text,
                sourceLanguage: raw.sourceLanguage ?? raw.language,
                languageConfidence: raw.languageConfidence ?? raw.confidence,
                speakerID: raw.speakerID ?? raw.speaker,
                speakerLabel: raw.speakerLabel ?? raw.speaker.map(Self.defaultSpeakerLabel(for:)),
                speakerConfidence: raw.speakerConfidence,
                isFinal: raw.isFinal ?? true,
                asrModelID: model.id.uuidString
            )
        }
    }

    private static func defaultSpeakerLabel(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Speaker"
        }
        if let number = Int(trimmed) {
            return "Speaker \(number + 1)"
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("speaker") {
            return trimmed
        }
        return trimmed
    }
}

private struct ASRSidecarEnvelope: Decodable {
    var segments: [ASRSidecarSegment]
}

private struct ASRSidecarSegment: Decodable {
    var index: Int?
    var start: TimeInterval?
    var end: TimeInterval?
    var text: String
    var language: String?
    var sourceLanguage: String?
    var confidence: Double?
    var languageConfidence: Double?
    var speaker: String?
    var speakerID: String?
    var speakerLabel: String?
    var speakerConfidence: Double?
    var isFinal: Bool?

    private enum CodingKeys: String, CodingKey {
        case index
        case start
        case startTime
        case start_time
        case begin
        case begin_time
        case end
        case endTime
        case end_time
        case stop
        case stop_time
        case text
        case content
        case transcript
        case language
        case sourceLanguage
        case source_language
        case confidence
        case languageConfidence
        case language_confidence
        case speaker
        case Speaker
        case speakerID
        case speaker_id
        case speakerLabel
        case speaker_label
        case label
        case speakerConfidence
        case speaker_confidence
        case isFinal
        case is_final
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        start = Self.decodeTime(
            from: container,
            keys: [.start, .startTime, .start_time, .begin, .begin_time]
        )
        end = Self.decodeTime(
            from: container,
            keys: [.end, .endTime, .end_time, .stop, .stop_time]
        )
        text = Self.decodeString(
            from: container,
            keys: [.text, .content, .transcript]
        ) ?? ""
        language = Self.decodeString(from: container, keys: [.language])
        sourceLanguage = Self.decodeString(from: container, keys: [.sourceLanguage, .source_language])
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        languageConfidence = try container.decodeIfPresent(Double.self, forKey: .languageConfidence)
            ?? (try container.decodeIfPresent(Double.self, forKey: .language_confidence))
        speaker = Self.decodeString(from: container, keys: [.speaker, .Speaker])
        speakerID = Self.decodeString(from: container, keys: [.speakerID, .speaker_id])
        speakerLabel = Self.decodeString(from: container, keys: [.speakerLabel, .speaker_label, .label])
        speakerConfidence = try container.decodeIfPresent(Double.self, forKey: .speakerConfidence)
            ?? (try container.decodeIfPresent(Double.self, forKey: .speaker_confidence))
        isFinal = try container.decodeIfPresent(Bool.self, forKey: .isFinal)
            ?? (try container.decodeIfPresent(Bool.self, forKey: .is_final))
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
                return String(intValue)
            }
            if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key) {
                return String(doubleValue)
            }
        }
        return nil
    }

    private static func decodeTime(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> TimeInterval? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return max(0, value)
            }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return max(0, TimeInterval(value))
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               let parsed = parseTimestamp(value) {
                return max(0, parsed)
            }
        }
        return nil
    }

    private static func parseTimestamp(_ rawValue: String) -> TimeInterval? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(value) {
            return seconds
        }
        let parts = value.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else {
            return nil
        }
        var multiplier: TimeInterval = 1
        var total: TimeInterval = 0
        for part in parts.reversed() {
            guard let component = Double(part) else {
                return nil
            }
            total += component * multiplier
            multiplier *= 60
        }
        return total
    }
}

public final class StreamingASRProcessSession: @unchecked Sendable, RealtimeASRSession {
    private let model: ModelDescriptor
    private let process: Process
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private let requestLock = NSLock()
    private let processLifecycle = PersistentProcessLifecycle()
    private let stderrLock = NSLock()
    private var stderrData = Data()

    private init(
        model: ModelDescriptor,
        preferences: MediaSubtitlePreferences,
        sourceLanguageHint: ASRSourceLanguageHint
    ) throws {
        guard let speech = model.capabilities.speech else {
            throw MediaSubtitleError.asrModelMissing("\(model.name) is not speech-capable.")
        }
        guard let resolution = Self.sidecarResolution(for: model, family: speech.family) else {
            throw MediaSubtitleError.asrRuntimeMissing(
                "Local streaming ASR sidecar is not available for \(model.name). Install the matching local ASR runtime."
            )
        }

        self.model = model
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolution.pythonPath)
        process.arguments = [
            resolution.sidecarPath,
            "--model",
            (model.resolvedPath ?? model.sourcePath).path,
            "--family",
            speech.family.rawValue,
            "--language",
            sourceLanguageHint == .auto ? preferences.sourceLanguageHint.rawValue : sourceLanguageHint.rawValue
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process
        self.inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputPipe.fileHandleForReading
        self.errorHandle = errorPipe.fileHandleForReading
        self.errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.appendStderr(data)
        }

        do {
            try process.run()
        } catch {
            self.errorHandle.readabilityHandler = nil
            throw MediaSubtitleError.asrRuntimeFailed(error.localizedDescription)
        }
    }

    deinit {
        stop()
    }

    public static func start(
        model: ModelDescriptor,
        preferences: MediaSubtitlePreferences = MediaSubtitlePreferences(),
        sourceLanguageHint: ASRSourceLanguageHint = .auto
    ) async throws -> StreamingASRProcessSession {
        let session = try StreamingASRProcessSession(
            model: model,
            preferences: preferences,
            sourceLanguageHint: sourceLanguageHint
        )
        try await session.waitUntilReady()
        return session
    }

    static func realtimeHealth(
        for model: ModelDescriptor,
        family: SpeechModelFamily
    ) -> (source: ASRRuntimeSource, message: String)? {
        guard sidecarResolution(for: model, family: family) != nil else {
            return nil
        }
        switch family {
        case .funASRNano where ModelDetection.isOfficialFunASRNanoModel(at: model.resolvedPath ?? model.sourcePath):
            return (.funASRTorchStreaming, "Official persistent Fun-ASR-Nano Torch/MPS streaming sidecar is available.")
        case .funASRNano, .funASRMLTNano, .senseVoiceSmall, .qwen3ASR06B:
            return (.mlxAudioRunner, "Local persistent MLX ASR streaming sidecar is available.")
        case .nemotron35ASRStreaming06B:
            return nil
        case .qwen3ASRSherpaOnnx:
            return nil
        case .vibeVoiceASR:
            return nil
        case .whisperCppCoreML:
            return (.whisperCppCoreMLRunner, "Local persistent whisper.cpp Core ML server sidecar is available.")
        case .customLocal:
            return nil
        }
    }

    public func transcribe(
        pcm16Data: Data,
        sampleRate: Int,
        sessionID: UUID,
        duration: TimeInterval?,
        sourceLanguageHint: ASRSourceLanguageHint,
        isFinal: Bool
    ) async throws -> [SubtitleSegment] {
        guard !pcm16Data.isEmpty else {
            return []
        }
        return try await Task.detached(priority: .userInitiated) { [self] in
            try transcribeSync(
                pcm16Data: pcm16Data,
                sampleRate: sampleRate,
                sessionID: sessionID,
                duration: duration,
                sourceLanguageHint: sourceLanguageHint,
                isFinal: isFinal
            )
        }.value
    }

    private func transcribeSync(
        pcm16Data: Data,
        sampleRate: Int,
        sessionID: UUID,
        duration: TimeInterval?,
        sourceLanguageHint: ASRSourceLanguageHint,
        isFinal: Bool
    ) throws -> [SubtitleSegment] {
        requestLock.lock()
        defer {
            requestLock.unlock()
        }
        guard !processLifecycle.isStopped, process.isRunning else {
            throw MediaSubtitleError.asrRuntimeFailed("Streaming ASR sidecar is not running.")
        }

        let requestID = UUID().uuidString
        let request = StreamingASRCommand(
            command: "transcribe",
            requestID: requestID,
            sampleRate: sampleRate,
            language: sourceLanguageHint.rawValue,
            isFinal: isFinal,
            pcm16Base64: pcm16Data.base64EncodedString()
        )
        try writeJSONLine(request)

        while true {
            let line = try readLineSync()
            guard let data = line.data(using: .utf8) else {
                continue
            }
            let event = try JSONDecoder().decode(StreamingASREvent.self, from: data)
            if event.type == "error" {
                throw MediaSubtitleError.asrRuntimeFailed(event.message ?? "Streaming ASR sidecar failed.")
            }
            guard event.requestID == nil || event.requestID == requestID else {
                continue
            }
            if event.type == "result" {
                return normalizeSegments(
                    event.segments ?? [],
                    sessionID: sessionID,
                    duration: duration,
                    isFinal: isFinal
                )
            }
        }
    }

    public func stop() {
        processLifecycle.stop(
            process: process,
            inputHandle: inputHandle,
            errorHandle: errorHandle
        )
    }

    private func waitUntilReady() async throws {
        try await Task.detached(priority: .userInitiated) { [self] in
            while true {
                let line = try readLineSync()
                guard let data = line.data(using: .utf8) else {
                    continue
                }
                let event = try JSONDecoder().decode(StreamingASREvent.self, from: data)
                switch event.type {
                case "ready":
                    return
                case "error":
                    throw MediaSubtitleError.asrRuntimeFailed(event.message ?? "Streaming ASR sidecar failed to start.")
                default:
                    continue
                }
            }
        }.value
    }

    private func writeJSONLine<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        var line = data
        line.append(0x0A)
        try inputHandle.write(contentsOf: line)
    }

    private func readLineSync() throws -> String {
        var data = Data()
        while true {
            let byte = outputHandle.readData(ofLength: 1)
            if byte.isEmpty {
                let message = lastStderr()
                throw MediaSubtitleError.asrRuntimeFailed(
                    message.isEmpty ? "Streaming ASR sidecar exited unexpectedly." : message
                )
            }
            if byte.first == 0x0A {
                break
            }
            data.append(byte)
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func normalizeSegments(
        _ rawSegments: [ASRSidecarSegment],
        sessionID: UUID,
        duration: TimeInterval?,
        isFinal: Bool
    ) -> [SubtitleSegment] {
        var fallbackStart: TimeInterval = 0
        return rawSegments.enumerated().compactMap { offset, raw in
            let text = raw.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            let start = raw.start ?? fallbackStart
            let end = raw.end ?? min((duration ?? start + 2), start + 2.5)
            fallbackStart = max(end, start + 0.1)
            return SubtitleSegment(
                sessionID: sessionID,
                index: raw.index ?? offset,
                startTime: start,
                endTime: end,
                originalText: text,
                sourceLanguage: raw.sourceLanguage ?? raw.language,
                languageConfidence: raw.languageConfidence ?? raw.confidence,
                speakerID: raw.speakerID ?? raw.speaker,
                speakerLabel: raw.speakerLabel ?? raw.speaker.map(Self.defaultSpeakerLabel(for:)),
                speakerConfidence: raw.speakerConfidence,
                isFinal: raw.isFinal ?? isFinal,
                asrModelID: model.id.uuidString
            )
        }
    }

    private static func defaultSpeakerLabel(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Speaker"
        }
        if let number = Int(trimmed) {
            return "Speaker \(number + 1)"
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("speaker") {
            return trimmed
        }
        return trimmed
    }

    private func appendStderr(_ data: Data) {
        stderrLock.lock()
        stderrData.append(data)
        if stderrData.count > 16_384 {
            stderrData.removeFirst(stderrData.count - 16_384)
        }
        stderrLock.unlock()
    }

    private func lastStderr() -> String {
        stderrLock.lock()
        defer {
            stderrLock.unlock()
        }
        let suffix = Data(stderrData.suffix(4_096))
        return String(data: suffix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private struct SidecarResolution {
        var pythonPath: String
        var sidecarPath: String
    }

    private static func sidecarResolution(
        for model: ModelDescriptor,
        family: SpeechModelFamily
    ) -> SidecarResolution? {
        let modelURL = model.resolvedPath ?? model.sourcePath
        guard let sidecarPath = streamingSidecarPath() else {
            return nil
        }
        switch family {
        case .funASRNano where ModelDetection.isOfficialFunASRNanoModel(at: modelURL):
            guard let runtimeRoot = officialFunASRRuntimeRoot(),
                  let pythonPath = pythonExecutable(in: runtimeRoot.appendingPathComponent("venv", isDirectory: true).path),
                  pythonPackageExists(in: runtimeRoot.appendingPathComponent("venv", isDirectory: true).path, moduleName: "funasr") else {
                return nil
            }
            return SidecarResolution(pythonPath: pythonPath, sidecarPath: sidecarPath)
        case .funASRNano, .funASRMLTNano, .senseVoiceSmall, .qwen3ASR06B:
            guard FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("model.safetensors").path),
                  let venvPath = mlxAudioVenvPath(for: family),
                  let pythonPath = pythonExecutable(in: venvPath) else {
                return nil
            }
            return SidecarResolution(pythonPath: pythonPath, sidecarPath: sidecarPath)
        case .nemotron35ASRStreaming06B:
            return nil
        case .qwen3ASRSherpaOnnx:
            return nil
        case .vibeVoiceASR:
            return nil
        case .whisperCppCoreML:
            guard streamingWhisperCppModelBin(for: modelURL) != nil,
                  let rootPath = streamingWhisperCppRuntimeRootPath(),
                  streamingWhisperCppRuntimeIsReady(rootPath: rootPath, modelURL: modelURL),
                  let pythonPath = streamingWhisperCppPythonPath(rootPath: rootPath) else {
                return nil
            }
            return SidecarResolution(pythonPath: pythonPath, sidecarPath: sidecarPath)
        case .customLocal:
            return nil
        }
    }

    private static func streamingWhisperCppRuntimeRootPath() -> String? {
        let candidates = [
            nonEmpty(ProcessInfo.processInfo.environment["LLMTOOLS_WHISPER_CPP_ROOT"]),
            AppPaths.asrRuntimeDirectory
                .appendingPathComponent("whisper-cpp", isDirectory: true)
                .path(percentEncoded: false)
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func streamingWhisperCppRuntimeIsReady(rootPath: String, modelURL: URL) -> Bool {
        let fileManager = FileManager.default
        let serverCandidates = [
            URL(fileURLWithPath: rootPath).appendingPathComponent("whisper.cpp/build/bin/whisper-server").path,
            URL(fileURLWithPath: rootPath).appendingPathComponent("bin/whisper-server").path
        ]
        guard serverCandidates.contains(where: { fileManager.isExecutableFile(atPath: $0) }),
              let modelBin = streamingWhisperCppModelBin(for: modelURL) else {
            return false
        }
        return streamingWhisperCppCoreMLDirectory(for: modelBin) != nil
    }

    private static func streamingWhisperCppPythonPath(rootPath: String) -> String? {
        let fileManager = FileManager.default
        let candidates = [
            nonEmpty(ProcessInfo.processInfo.environment["LLMTOOLS_WHISPER_CPP_PYTHON"]),
            URL(fileURLWithPath: rootPath)
                .appendingPathComponent("coreml-venv", isDirectory: true)
                .appendingPathComponent("bin/python3")
                .path,
            URL(fileURLWithPath: rootPath)
                .appendingPathComponent("coreml-venv", isDirectory: true)
                .appendingPathComponent("bin/python")
                .path,
            "/usr/bin/python3"
        ].compactMap { $0 }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private static func streamingWhisperCppModelBin(for modelURL: URL) -> URL? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            let name = modelURL.lastPathComponent.lowercased()
            return modelURL.pathExtension.lowercased() == "bin" && name.hasPrefix("ggml-") ? modelURL : nil
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents
            .filter { $0.pathExtension.lowercased() == "bin" && $0.lastPathComponent.lowercased().hasPrefix("ggml-") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }

    private static func streamingWhisperCppCoreMLDirectory(for modelBin: URL) -> URL? {
        let stem = modelBin.deletingPathExtension().lastPathComponent
        let compiled = modelBin.deletingLastPathComponent().appendingPathComponent("\(stem)-encoder.mlmodelc", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: compiled.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return compiled
        }
        return nil
    }

    private static func streamingSidecarPath() -> String? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("asr", isDirectory: true)
                .appendingPathComponent("llmtools-streaming-asr-sidecar.py")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-streaming-asr-sidecar.py")
                .path
        ].compactMap { $0 }
        return candidates.first { fileManager.isReadableFile(atPath: $0) }
    }

    private static func officialFunASRRuntimeRoot() -> URL? {
        let candidates = [
            nonEmpty(ProcessInfo.processInfo.environment["LLMTOOLS_FUNASR_PIPELINE_ROOT"])
                .map { URL(fileURLWithPath: $0, isDirectory: true) },
            AppPaths.funASRPipelineRuntimeDirectory
        ].compactMap { $0 }
        return candidates.first { root in
            FileManager.default.fileExists(atPath: root.appendingPathComponent("venv", isDirectory: true).path)
        }
    }

    private static func pythonExecutable(in venvPath: String) -> String? {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: venvPath)
        let candidates = [
            root.appendingPathComponent("bin/python3").path,
            root.appendingPathComponent("bin/python").path
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private static func mlxAudioVenvPath(for family: SpeechModelFamily) -> String? {
        let env = ProcessInfo.processInfo.environment
        let envKey = mlxAudioVenvEnvironmentName(for: family)
        let directoryName = mlxAudioVenvDirectoryName(for: family)
        let candidates = [
            nonEmpty(env[envKey]),
            AppPaths.asrRuntimeDirectory
                .appendingPathComponent(directoryName, isDirectory: true)
                .path(percentEncoded: false)
        ].compactMap { $0 }
        return candidates.first {
            pythonExecutable(in: $0) != nil && mlxAudioModelModuleExists(in: $0, family: family)
        }
    }

    private static func mlxAudioVenvEnvironmentName(for family: SpeechModelFamily) -> String {
        switch family {
        case .funASRMLTNano:
            return "LLMTOOLS_FUN_ASR_VENV"
        case .funASRNano:
            return "LLMTOOLS_FUN_ASR_NANO_VENV"
        case .senseVoiceSmall:
            return "LLMTOOLS_SENSEVOICE_ASR_VENV"
        case .qwen3ASR06B, .nemotron35ASRStreaming06B, .qwen3ASRSherpaOnnx, .vibeVoiceASR, .customLocal:
            return "LLMTOOLS_ASR_VENV"
        case .whisperCppCoreML:
            return "LLMTOOLS_WHISPER_CPP_ROOT"
        }
    }

    private static func mlxAudioVenvDirectoryName(for family: SpeechModelFamily) -> String {
        switch family {
        case .funASRMLTNano:
            return "funasr-venv"
        case .funASRNano:
            return "funasr-nano-venv"
        case .senseVoiceSmall:
            return "sensevoice-venv"
        case .qwen3ASR06B, .nemotron35ASRStreaming06B, .qwen3ASRSherpaOnnx, .vibeVoiceASR, .customLocal:
            return "venv"
        case .whisperCppCoreML:
            return "whisper-cpp"
        }
    }

    private static func mlxAudioModelModuleExists(in venvPath: String, family: SpeechModelFamily) -> Bool {
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
        case .nemotron35ASRStreaming06B:
            return false
        case .qwen3ASRSherpaOnnx:
            return false
        case .vibeVoiceASR:
            return false
        case .whisperCppCoreML:
            return false
        case .customLocal:
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

    private static func pythonPackageExists(in venvPath: String, moduleName: String) -> Bool {
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

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct StreamingASRCommand: Encodable {
    var command: String
    var requestID: String
    var sampleRate: Int
    var language: String
    var isFinal: Bool
    var pcm16Base64: String
}

private struct StreamingASREvent: Decodable {
    var type: String
    var requestID: String?
    var segments: [ASRSidecarSegment]?
    var message: String?
}

public enum SubtitleExporter {
    public static func render(
        segments: [SubtitleSegment],
        format: SubtitleExportFormat,
        mode: SubtitleDisplayMode,
        options: SubtitleExportOptions = SubtitleExportOptions()
    ) throws -> String {
        guard !segments.isEmpty else {
            throw MediaSubtitleError.exportFailed("No subtitle segments to export.")
        }
        switch format {
        case .srt:
            return renderSRT(segments: segments, mode: mode, options: options)
        case .vtt:
            return renderVTT(segments: segments, mode: mode, options: options)
        case .txt:
            return renderText(segments: segments, mode: mode, options: options)
        case .markdown:
            return renderMarkdown(segments: segments, mode: mode, options: options)
        }
    }

    private static func text(
        for segment: SubtitleSegment,
        mode: SubtitleDisplayMode,
        options: SubtitleExportOptions
    ) -> String {
        let original = segment.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body: String
        switch mode {
        case .original:
            body = original
        case .translated:
            body = translated.isEmpty ? original : translated
        case .bilingual:
            guard !translated.isEmpty, translated != original else {
                body = original
                return prefixedSpeakerText(body, segment: segment, options: options)
            }
            body = "\(original)\n\(translated)"
        }
        return prefixedSpeakerText(body, segment: segment, options: options)
    }

    private static func renderSRT(
        segments: [SubtitleSegment],
        mode: SubtitleDisplayMode,
        options: SubtitleExportOptions
    ) -> String {
        let body = segments.enumerated().map { offset, segment in
            let end = segment.endTime ?? (segment.startTime + 2)
            return """
            \(offset + 1)
            \(srtTime(segment.startTime)) --> \(srtTime(end))
            \(text(for: segment, mode: mode, options: options))
            """
        }.joined(separator: "\n\n") + "\n"
        guard let metadata = translationMetadataLine(segments: segments, options: options) else {
            return body
        }
        return "# \(metadata)\n\n" + body
    }

    private static func renderVTT(
        segments: [SubtitleSegment],
        mode: SubtitleDisplayMode,
        options: SubtitleExportOptions
    ) -> String {
        let metadata = translationMetadataLine(segments: segments, options: options)
            .map { "NOTE \($0)\n\n" } ?? ""
        return "WEBVTT\n\n" + metadata + segments.map { segment in
            let end = segment.endTime ?? (segment.startTime + 2)
            return """
            \(vttTime(segment.startTime)) --> \(vttTime(end))
            \(text(for: segment, mode: mode, options: options))
            """
        }.joined(separator: "\n\n") + "\n"
    }

    private static func renderText(
        segments: [SubtitleSegment],
        mode: SubtitleDisplayMode,
        options: SubtitleExportOptions
    ) -> String {
        let body = segments.map { text(for: $0, mode: mode, options: options) }.joined(separator: "\n\n") + "\n"
        guard let metadata = translationMetadataLine(segments: segments, options: options) else {
            return body
        }
        return "# \(metadata)\n\n" + body
    }

    private static func renderMarkdown(
        segments: [SubtitleSegment],
        mode: SubtitleDisplayMode,
        options: SubtitleExportOptions
    ) -> String {
        let hasSpeakerLabels = options.includeSpeakerLabels
            && segments.contains { nonEmpty($0.speakerLabel) != nil || nonEmpty($0.speakerID) != nil }
        var lines = hasSpeakerLabels
            ? ["| Time | Speaker | Subtitle |", "| --- | --- | --- |"]
            : ["| Time | Subtitle |", "| --- | --- |"]
        var bodyOptions = options
        if hasSpeakerLabels {
            bodyOptions.includeSpeakerLabels = false
        }
        for segment in segments {
            let end = segment.endTime ?? (segment.startTime + 2)
            let body = markdownCell(text(for: segment, mode: mode, options: bodyOptions))
            let time = "\(vttTime(segment.startTime)) - \(vttTime(end))"
            if hasSpeakerLabels {
                let speaker = markdownCell(nonEmpty(segment.speakerLabel) ?? nonEmpty(segment.speakerID) ?? "")
                lines.append("| \(time) | \(speaker) | \(body) |")
            } else {
                lines.append("| \(time) | \(body) |")
            }
        }
        let body = lines.joined(separator: "\n") + "\n"
        guard let metadata = translationMetadata(segments: segments, options: options) else {
            return body
        }
        return """
        ---
        translationEngine: \(metadata.engine)
        translationModel: \(metadata.model ?? "")
        ---

        \(body)
        """
    }

    private static func markdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private static func translationMetadataLine(
        segments: [SubtitleSegment],
        options: SubtitleExportOptions
    ) -> String? {
        guard let metadata = translationMetadata(segments: segments, options: options) else {
            return nil
        }
        if let model = metadata.model {
            return "Translation engine: \(metadata.engine); model: \(model)"
        }
        return "Translation engine: \(metadata.engine)"
    }

    private static func translationMetadata(
        segments: [SubtitleSegment],
        options: SubtitleExportOptions
    ) -> (engine: String, model: String?)? {
        guard options.includeTranslationMetadata else {
            return nil
        }
        guard let engine = segments.compactMap({ nonEmpty($0.translationEngineID) }).first else {
            return nil
        }
        let model = segments.compactMap { nonEmpty($0.translationModelID) }.first
        return (engine, model)
    }

    private static func prefixedSpeakerText(
        _ text: String,
        segment: SubtitleSegment,
        options: SubtitleExportOptions
    ) -> String {
        guard options.includeSpeakerLabels,
              let label = segment.speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              !text.isEmpty else {
            return text
        }
        let prefix: String
        switch options.speakerFormat {
        case .colon:
            prefix = "\(label): "
        case .bracketed:
            prefix = "[\(label)] "
        }
        guard let newlineRange = text.range(of: "\n") else {
            return prefix + text
        }
        return prefix + text[..<newlineRange.lowerBound] + text[newlineRange.lowerBound...]
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func srtTime(_ value: TimeInterval) -> String {
        let clamped = max(0, value)
        let hours = Int(clamped / 3600)
        let minutes = Int(clamped.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(clamped.truncatingRemainder(dividingBy: 60))
        let millis = Int((clamped - floor(clamped)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private static func vttTime(_ value: TimeInterval) -> String {
        srtTime(value).replacingOccurrences(of: ",", with: ".")
    }
}
