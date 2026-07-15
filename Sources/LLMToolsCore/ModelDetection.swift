import Foundation

public enum ModelDetectionError: Error, LocalizedError, Sendable {
    case pathDoesNotExist(URL)
    case unsupported(URL)
    case multipleGGUFFiles(URL)

    public var errorDescription: String? {
        switch self {
        case .pathDoesNotExist(let url):
            return "Model path does not exist: \(url.path)"
        case .unsupported(let url):
            return "Unsupported model location: \(url.path)"
        case .multipleGGUFFiles(let url):
            return "Multiple GGUF files were found in \(url.path). Pick the exact file to use."
        }
    }
}

public enum ModelDetection {
    public static func detect(from url: URL) throws -> (format: ModelFormat, resolvedPath: URL, sizeClass: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw ModelDetectionError.pathDoesNotExist(url)
        }

        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            let ggufFiles = contents.filter { $0.pathExtension.lowercased() == "gguf" }
            if ggufFiles.count == 1 {
                return (.gguf, ggufFiles[0], inferSizeClass(from: ggufFiles[0].lastPathComponent))
            }
            if ggufFiles.count > 1 {
                let primaryGGUFFiles = ggufFiles.filter { !isMMProjFile($0) }
                if primaryGGUFFiles.count == 1 {
                    return (.gguf, primaryGGUFFiles[0], inferSizeClass(from: primaryGGUFFiles[0].lastPathComponent))
                }
                throw ModelDetectionError.multipleGGUFFiles(url)
            }

            if containsMLXFiles(in: contents) {
                return (.mlx, url, inferSizeClass(from: url.lastPathComponent))
            }

            if let nestedGGUF = try firstGGUFFileRecursively(in: url) {
                return (.gguf, nestedGGUF, inferSizeClass(from: nestedGGUF.lastPathComponent))
            }

            throw ModelDetectionError.unsupported(url)
        }

        if url.pathExtension.lowercased() == "gguf" {
            return (.gguf, url, inferSizeClass(from: url.lastPathComponent))
        }

        throw ModelDetectionError.unsupported(url)
    }

    public static func isLocalVisionModel(at url: URL) -> Bool {
        guard let directory = localModelDirectory(for: url) else {
            return false
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ), containsMLXFiles(in: contents) else {
            return false
        }
        guard let config = jsonDictionary(at: directory.appendingPathComponent("config.json")) else {
            return false
        }

        let hasVisionConfig = config["vision_config"] != nil
            || config["image_token_id"] != nil
            || config["vision_start_token_id"] != nil
            || config["vision_end_token_id"] != nil
        guard hasVisionConfig else {
            return false
        }

        let processorFiles = [
            "processor_config.json",
            "preprocessor_config.json",
            "video_preprocessor_config.json"
        ]
        let processorText = processorFiles
            .compactMap { try? String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
            .lowercased()
        if processorText.contains("vlprocessor")
            || processorText.contains("vision")
            || processorText.contains("image_processor")
            || processorText.contains("imageprocessor") {
            return true
        }

        return false
    }

    public static func detectSpeechModel(at url: URL) -> SpeechModelCapabilities? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return nil
        }
        let lowerName = url.lastPathComponent.lowercased()
        let fileNames = localFileNames(for: url)
        let searchable = ([lowerName] + fileNames).joined(separator: "\n")

        if isSherpaQwen3ASRModel(at: url) {
            return nil
        }
        if isWhisperCppCoreMLModel(at: url) {
            return .whisperCppCoreML(
                source: .detected,
                confidence: 0.86,
                note: "Detected whisper.cpp ggml model with a compiled Core ML encoder. Uses persistent whisper-server/Core ML for realtime subtitles and whisper-cli for local file transcription."
            )
        }
        if searchable.contains("fun-asr-mlt-nano")
            || searchable.contains("funasr-mlt-nano")
            || searchable.contains("fun_asr_mlt_nano")
            || searchable.contains("mlt-nano") {
            return .funASRMLTNano(
                source: .detected,
                confidence: 0.87,
                note: "Detected Fun-ASR-MLT-Nano-style local ASR files. The current llmTools MLX route provides multilingual ASR only and uses separate speaker processing."
            )
        }
        if searchable.contains("fun-asr-nano")
            || searchable.contains("funasr-nano")
            || searchable.contains("fun_asr_nano")
            || searchable.contains("llama-funasr")
            || searchable.contains("funasr-encoder")
            || searchable.contains("fsmn-vad") {
            var capabilities = SpeechModelCapabilities.funASRNano(
                source: .detected,
                confidence: 0.88,
                note: "Detected Fun-ASR-Nano-style local ASR files. The current llmTools MLX/GGUF routes provide ASR only; CAM++ speaker diarization belongs to the separate official FunASR pipeline."
            )
            if isOfficialFunASRNanoModel(at: url) {
                // 同一份原版权重按运行模式分流：实时走常驻 Torch/MPS，文件转写走 VAD + CAM++ 复合管线。
                capabilities.modes = [.realtime, .fileOnly]
                capabilities.note = "Detected the official Fun-ASR-Nano model.pt runtime. Realtime transcription uses the persistent Torch/MPS runner; file transcription can compose Nano with local VAD, CAM++, and punctuation models."
            }
            return capabilities
        }
        if searchable.contains("sensevoice") || searchable.contains("sense-voice") {
            return .senseVoiceSmall(
                source: .detected,
                confidence: 0.78,
                note: "Detected SenseVoiceSmall-style local ASR files. Uses short-window local ASR when a runtime/sidecar is configured."
            )
        }
        if searchable.contains("vibevoice-asr")
            || searchable.contains("vibevoice_asr")
            || searchable.contains("vibevoiceasr")
            || configModelType(at: url)?.lowercased().contains("vibevoice") == true {
            return .vibeVoiceASR(
                source: .detected,
                confidence: 0.82,
                note: "Detected VibeVoice-ASR-style local ASR files. This is a heavy file-only rich transcription model; use it for local media/file transcription, not realtime subtitles."
            )
        }
        if searchable.contains("qwen3-asr") || searchable.contains("qwen-asr") {
            return .qwen3ASR06B(
                source: .detected,
                confidence: 0.82,
                note: "Detected Qwen3-ASR-style local ASR files. Supports file transcription and experimental realtime through a local vLLM/streaming sidecar."
            )
        }
        if fileNames.contains(where: { $0.hasSuffix(".onnx") })
            && (fileNames.contains("tokens.txt") || fileNames.contains("tokens.json")) {
            return .senseVoiceSmall(
                source: .inferred,
                confidence: 0.55,
                note: "Found ONNX ASR-style files. Confirm this is a SenseVoiceSmall model before using realtime subtitles."
            )
        }
        return nil
    }

    private static func isSherpaQwen3ASRModel(at url: URL) -> Bool {
        guard let directory = localModelDirectory(for: url) else {
            return false
        }
        let fm = FileManager.default
        let hasRequiredFiles = fm.fileExists(atPath: directory.appendingPathComponent("conv_frontend.onnx").path)
            && sherpaQwen3ModelPairExists(in: directory)
        guard hasRequiredFiles else {
            return false
        }
        let tokenizer = directory.appendingPathComponent("tokenizer", isDirectory: true)
        return fm.fileExists(atPath: tokenizer.appendingPathComponent("vocab.json").path)
            && fm.fileExists(atPath: tokenizer.appendingPathComponent("merges.txt").path)
            && fm.fileExists(atPath: tokenizer.appendingPathComponent("tokenizer_config.json").path)
    }

    public static func isOfficialFunASRNanoModel(at url: URL) -> Bool {
        guard let directory = localModelDirectory(for: url) else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appendingPathComponent("model.pt").path)
            && fm.fileExists(atPath: directory.appendingPathComponent("config.yaml").path)
    }

    private static func sherpaQwen3ModelPairExists(in directory: URL) -> Bool {
        let fm = FileManager.default
        let hasInt8Pair = fm.fileExists(atPath: directory.appendingPathComponent("encoder.int8.onnx").path)
            && fm.fileExists(atPath: directory.appendingPathComponent("decoder.int8.onnx").path)
        if hasInt8Pair {
            return true
        }
        let hasONNXPair = fm.fileExists(atPath: directory.appendingPathComponent("encoder.onnx").path)
            && fm.fileExists(atPath: directory.appendingPathComponent("decoder.onnx").path)
        guard hasONNXPair else {
            return false
        }
        let encoderDataExists = fm.fileExists(atPath: directory.appendingPathComponent("encoder.onnx.data").path)
        let decoderDataExists = fm.fileExists(atPath: directory.appendingPathComponent("decoder.onnx.data").path)
        return encoderDataExists == decoderDataExists
    }

    private static func isWhisperCppCoreMLModel(at url: URL) -> Bool {
        guard let modelURL = whisperCppModelBin(at: url) else {
            return false
        }
        return whisperCppCoreMLDirectory(for: modelURL) != nil
    }

    private static func whisperCppModelBin(at url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            let fileName = url.lastPathComponent.lowercased()
            return url.pathExtension.lowercased() == "bin" && fileName.hasPrefix("ggml-") ? url : nil
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
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

    private static func whisperCppCoreMLDirectory(for modelURL: URL) -> URL? {
        let modelStem = modelURL.deletingPathExtension().lastPathComponent
        let compiled = modelURL.deletingLastPathComponent().appendingPathComponent("\(modelStem)-encoder.mlmodelc", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: compiled.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return compiled
        }
        return nil
    }

    private static func containsMLXFiles(in contents: [URL]) -> Bool {
        let names = Set(contents.map { $0.lastPathComponent.lowercased() })
        let hasConfig = names.contains("config.json")
        let hasTokenizer = names.contains("tokenizer.json") || names.contains("tokenizer.model") || names.contains("tokenizer_config.json")
        let hasWeights = contents.contains { $0.pathExtension.lowercased() == "safetensors" || $0.pathExtension.lowercased() == "npz" }
        return hasConfig && hasTokenizer && hasWeights
    }

    private static func firstGGUFFileRecursively(in directory: URL) throws -> URL? {
        let fm = FileManager.default
        var fallback: URL?
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        while let element = enumerator.nextObject() {
            if let url = element as? URL, url.pathExtension.lowercased() == "gguf" {
                if isMMProjFile(url) {
                    fallback = fallback ?? url
                } else {
                    return url
                }
            }
        }
        return fallback
    }

    private static func inferSizeClass(from name: String) -> String {
        let lower = name.lowercased()
        for token in ["35b", "30b", "27b", "14b", "9b", "7b", "4b", "1.5b", "0.8b", "0.5b"] {
            if containsBoundedToken(token, in: lower) {
                return token
            }
        }
        return "custom"
    }

    private static func isMMProjFile(_ url: URL) -> Bool {
        url.deletingPathExtension().lastPathComponent.lowercased().contains("mmproj")
    }

    private static func localModelDirectory(for url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }

    private static func localFileNames(for url: URL) -> [String] {
        let directory: URL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            directory = url
        } else {
            directory = url.deletingLastPathComponent()
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var names: [String] = []
        while let element = enumerator.nextObject() {
            guard let itemURL = element as? URL else {
                continue
            }
            names.append(itemURL.lastPathComponent.lowercased())
            if names.count >= 80 {
                break
            }
        }
        return names
    }

    private static func configModelType(at url: URL) -> String? {
        guard let directory = localModelDirectory(for: url),
              let config = jsonDictionary(at: directory.appendingPathComponent("config.json")),
              let modelType = config["model_type"] as? String else {
            return nil
        }
        return modelType
    }

    private static func jsonDictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private static func containsBoundedToken(_ token: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: token, range: searchStart..<text.endIndex) {
            let beforeIsBoundary = range.lowerBound == text.startIndex || isBoundary(text[text.index(before: range.lowerBound)])
            let afterIsBoundary = range.upperBound == text.endIndex || isBoundary(text[range.upperBound])
            if beforeIsBoundary && afterIsBoundary {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isBoundary(_ character: Character) -> Bool {
        !(character.isLetter || character.isNumber)
    }
}
