import Foundation
import LLMToolsCore

@main
struct LLMToolsModelRegister {
    static func main() async throws {
        let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        let engine = TaskEngine()
        await engine.bootstrap()

        let textModel = try await register(path: options.textModelPath, engine: engine)
        let ocrModel = try await register(path: options.ocrModelPath, engine: engine)
        let realtimeASRModel = try await register(path: options.realtimeASRModelPath, engine: engine)

        guard textModel.capabilities.supportsText else {
            throw RegisterError("Text model is not text-capable: \(textModel.name)")
        }
        guard ocrModel.capabilities.supportsImage else {
            throw RegisterError("OCR model is not image-capable: \(ocrModel.name)")
        }
        guard realtimeASRModel.capabilities.supportsRealtimeSpeech else {
            throw RegisterError("Realtime ASR model is not realtime-capable: \(realtimeASRModel.name)")
        }

        var preferences = await engine.registry().preferences
        // 只更新明确指定的 OCR 选择；文本和实时 ASR 默认值始终保留用户当前选择。
        preferences.ocr.modelID = ocrModel.id
        try await engine.setPreferences(preferences)

        let snapshot = await engine.registry()
        print("Registered text model: \(textModel.name) [\(textModel.id.uuidString)]")
        print("Registered OCR model: \(ocrModel.name) [\(ocrModel.id.uuidString)]")
        print("Registered realtime ASR model: \(realtimeASRModel.name) [\(realtimeASRModel.id.uuidString)]")
        print("Selected OCR model: \(snapshot.preferences.ocr.modelID?.uuidString ?? "none")")
        print("Retained realtime ASR model: \(snapshot.preferences.mediaSubtitles.realtimeASRModelID?.uuidString ?? "none")")
    }

    private static func register(path: String, engine: TaskEngine) async throws -> ModelDescriptor {
        let requestedPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let snapshot = await engine.registry()
        if let existing = snapshot.models.first(where: { model in
            let sourcePath = model.sourcePath.standardizedFileURL.resolvingSymlinksInPath()
            let resolvedPath = model.resolvedPath?.standardizedFileURL.resolvingSymlinksInPath()
            return sourcePath == requestedPath || resolvedPath == requestedPath
        }) {
            return existing
        }
        return try await engine.addModel(from: requestedPath)
    }
}

private struct Options {
    var textModelPath: String
    var ocrModelPath: String
    var realtimeASRModelPath: String

    static func parse(_ arguments: [String]) throws -> Options {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            index += 1
            guard index < arguments.count else {
                throw RegisterError("\(flag) requires a model directory.")
            }
            values[flag] = arguments[index]
            index += 1
        }
        guard let textModelPath = values["--text"],
              let ocrModelPath = values["--ocr"],
              let realtimeASRModelPath = values["--realtime-asr"],
              values.count == 3 else {
            throw RegisterError("Usage: LLMToolsModelRegister --text <model-dir> --ocr <model-dir> --realtime-asr <model-dir>")
        }
        return Options(
            textModelPath: textModelPath,
            ocrModelPath: ocrModelPath,
            realtimeASRModelPath: realtimeASRModelPath
        )
    }
}

private struct RegisterError: Error, LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
