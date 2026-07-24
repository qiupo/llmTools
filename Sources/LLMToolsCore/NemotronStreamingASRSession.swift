import FluidAudio
import Foundation

public protocol RealtimeASRSession: Sendable {
    func transcribe(
        pcm16Data: Data,
        sampleRate: Int,
        sessionID: UUID,
        duration: TimeInterval?,
        sourceLanguageHint: ASRSourceLanguageHint,
        isFinal: Bool
    ) async throws -> [SubtitleSegment]
    func stop()
}

public final class NemotronStreamingASRSession: @unchecked Sendable, RealtimeASRSession {
    private let state: State

    private init(model: ModelDescriptor) {
        state = State(model: model)
    }

    public static func start(
        model: ModelDescriptor,
        sourceLanguageHint: ASRSourceLanguageHint = .auto
    ) async throws -> NemotronStreamingASRSession {
        let session = NemotronStreamingASRSession(model: model)
        try await session.state.start(sourceLanguageHint: sourceLanguageHint)
        return session
    }

    public func transcribe(
        pcm16Data: Data,
        sampleRate: Int,
        sessionID: UUID,
        duration: TimeInterval?,
        sourceLanguageHint: ASRSourceLanguageHint,
        isFinal: Bool
    ) async throws -> [SubtitleSegment] {
        try await state.transcribe(
            pcm16Data: pcm16Data,
            sampleRate: sampleRate,
            sessionID: sessionID,
            duration: duration,
            sourceLanguageHint: sourceLanguageHint,
            isFinal: isFinal
        )
    }

    public func stop() {
        Task {
            await state.stop()
        }
    }

    private actor State {
        private let model: ModelDescriptor
        private let manager = StreamingNemotronMultilingualAsrManager()
        private var submittedPCMByteCount = 0
        private var configuredLanguage: String?
        private var stopped = false

        init(model: ModelDescriptor) {
            self.model = model
        }

        func start(sourceLanguageHint: ASRSourceLanguageHint) async throws {
            let directory = model.resolvedPath ?? model.sourcePath
            try await manager.loadModels(from: directory)
            let language = Self.fluidLanguage(for: sourceLanguageHint)
            await manager.setLanguage(language)
            configuredLanguage = language
        }

        func transcribe(
            pcm16Data: Data,
            sampleRate: Int,
            sessionID: UUID,
            duration: TimeInterval?,
            sourceLanguageHint: ASRSourceLanguageHint,
            isFinal: Bool
        ) async throws -> [SubtitleSegment] {
            guard !stopped else {
                throw MediaSubtitleError.asrRuntimeFailed("Nemotron streaming session has stopped.")
            }
            guard sampleRate == 16_000 else {
                throw MediaSubtitleError.asrRuntimeFailed("Nemotron streaming expects 16 kHz PCM audio.")
            }

            let language = Self.fluidLanguage(for: sourceLanguageHint)
            if configuredLanguage != language {
                await manager.reset()
                await manager.setLanguage(language)
                configuredLanguage = language
                submittedPCMByteCount = 0
            }

            let newPCM: Data
            if pcm16Data.count >= submittedPCMByteCount {
                newPCM = Data(pcm16Data.dropFirst(submittedPCMByteCount))
            } else {
                // 累计窗口被调用方重置时同步清理模型缓存，禁止把两句话的 RNNT 状态混在一起。
                await manager.reset()
                submittedPCMByteCount = 0
                newPCM = pcm16Data
            }
            if !newPCM.isEmpty {
                _ = try await manager.process(samples: Self.floatSamples(from: newPCM))
                submittedPCMByteCount = pcm16Data.count
            }

            let text: String
            let detectedLanguage: String?
            if isFinal {
                text = try await manager.finish()
                detectedLanguage = await manager.detectedLanguage()
                await manager.reset()
                submittedPCMByteCount = 0
            } else {
                text = await manager.getPartialTranscript()
                detectedLanguage = await manager.detectedLanguage()
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return []
            }
            return [
                SubtitleSegment(
                    sessionID: sessionID,
                    index: 0,
                    startTime: 0,
                    endTime: duration ?? 0,
                    originalText: trimmed,
                    sourceLanguage: detectedLanguage,
                    isFinal: isFinal,
                    asrModelID: model.id.uuidString
                )
            ]
        }

        func stop() async {
            guard !stopped else { return }
            stopped = true
            submittedPCMByteCount = 0
            await manager.cleanup()
        }

        private static func floatSamples(from pcm16Data: Data) -> [Float] {
            pcm16Data.withUnsafeBytes { rawBuffer in
                rawBuffer.bindMemory(to: Int16.self).map {
                    Float(Int16(littleEndian: $0)) / 32_768
                }
            }
        }

        private static func fluidLanguage(for hint: ASRSourceLanguageHint) -> String {
            switch hint {
            case .auto, .yue:
                return "auto"
            case .zh:
                return "zh-CN"
            case .en:
                return "en-US"
            case .ja:
                return "ja-JP"
            case .ko:
                return "ko-KR"
            case .vi:
                return "vi-VN"
            case .id:
                return "id-ID"
            case .th:
                return "th-TH"
            case .ms:
                return "ms-MY"
            case .fil:
                return "auto"
            case .ar:
                return "ar-SA"
            case .hi:
                return "hi-IN"
            case .de:
                return "de-DE"
            case .fr:
                return "fr-FR"
            case .es:
                return "es-ES"
            case .pt:
                return "pt-BR"
            case .it:
                return "it-IT"
            case .ru:
                return "ru-RU"
            }
        }
    }
}
