import Foundation
import LLMToolsCore

@main
struct LLMToolsTTSSmoke {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let baseText = value(for: "--text", arguments: arguments) ?? "你好，这是 llmTools 本地语音合成测试。"
        let repeatCount = max(1, value(for: "--repeat", arguments: arguments).flatMap(Int.init) ?? 1)
        let text = Array(repeating: baseText, count: repeatCount).joined(separator: "\n")
        let variant = TTSModelVariant(rawValue: value(for: "--variant", arguments: arguments) ?? "voxCPM2BF16")
            ?? .voxCPM2BF16
        let outputURL = value(for: "--output", arguments: arguments).map(URL.init(fileURLWithPath:))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("llmtools-tts-smoke.wav")
        let instruction = value(for: "--instruction", arguments: arguments)
        let referenceAudioURL = value(for: "--reference-audio", arguments: arguments).map(URL.init(fileURLWithPath:))
        let referenceText = value(for: "--reference-text", arguments: arguments)
        let cancelAfterMilliseconds = value(for: "--cancel-after-ms", arguments: arguments).flatMap(Int.init)
        if arguments.contains("--analyze-only") {
            let engine = TaskEngine()
            await engine.bootstrap()
            let modelID = value(for: "--analysis-model-id", arguments: arguments).flatMap(UUID.init(uuidString:))
            let availableVoices = arguments.contains("--use-recent-voices")
                ? (try TTSProjectStore().loadMostRecent()?.voices ?? [])
                : []
            let analysis: TTSScriptAnalysis
            do {
                analysis = try await engine.analyzeTTSScript(
                    source: text,
                    modelID: modelID,
                    availableVoices: availableVoices
                )
            } catch {
                await engine.unloadAll()
                throw error
            }
            await engine.unloadAll()
            print("TTS role analysis smoke passed")
            print("voices=\(analysis.voices.map(\.name).joined(separator: ",")) segments=\(analysis.segments.count)")
            for segment in analysis.segments {
                let voice = analysis.voices.first(where: { $0.id == segment.roleID })?.name ?? "旁白"
                let deliveryStyle = segment.deliveryStyle ?? "自然表达"
                print("[\(segment.speakerName ?? "旁白") -> \(voice) | \(deliveryStyle) | \(segment.pauseAfterMilliseconds)ms] \(segment.sourceText)")
            }
            return
        }
        let service = LocalTTSService()
        let health = await service.health(for: variant)
        guard health.status == .ready else { throw SmokeError(health.message) }
        let request = TTSGenerationRequest(
            text: text,
            instruction: instruction,
            referenceAudioURL: referenceAudioURL,
            referenceText: referenceText,
            outputURL: outputURL
        )
        if let cancelAfterMilliseconds {
            let task = Task {
                try await service.generate(request, variant: variant)
            }
            try await Task.sleep(for: .milliseconds(cancelAfterMilliseconds))
            task.cancel()
            do {
                _ = try await task.value
                throw SmokeError("TTS generation completed before cancellation could be verified.")
            } catch let error as SmokeError {
                await service.stopAndWait()
                throw error
            } catch {
                await service.stopAndWait()
                print("TTS cancellation smoke passed")
                return
            }
        }
        let result = try await service.generate(request, variant: variant)
        await service.stopAndWait()
        guard FileManager.default.fileExists(atPath: result.outputPath), result.duration > 0 else {
            throw SmokeError("VoxCPM2 did not create a usable WAV file.")
        }
        print("TTS smoke passed")
        print("model=\(variant.displayName) duration=\(String(format: "%.2f", result.duration))s sampleRate=\(result.sampleRate) processing=\(String(format: "%.2f", result.processingTime))s")
        print("output=\(result.outputPath)")
    }

    private static func value(for flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private struct SmokeError: Error, LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
