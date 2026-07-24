import AppKit
import AVFoundation
import Foundation
import LLMToolsCore
import UniformTypeIdentifiers

@MainActor
extension AppState {
    var ttsVoicePreviewText: String {
        ttsProject.voicePreviewText ?? TTSProject.defaultVoicePreviewText
    }

    var localTTSAnalysisModels: [ModelDescriptor] {
        models.filter {
            $0.enabled
                && $0.capabilities.supportsText
                && !$0.isRemoteProvider
                && ($0.format == .gguf || $0.format == .mlx)
        }
    }

    var ttsVoiceSections: [TTSVoiceSection] {
        TTSVoiceCatalog.sections(for: ttsProject.voices)
    }

    var ttsVoiceGroupNames: [String] {
        ttsVoiceSections.compactMap(\.groupName)
    }

    var quickTTSSelectedVoice: TTSVoiceProfile? {
        let selectedID = quickTTSSelectedVoiceID ?? ttsProject.selectedVoiceID
        return selectedID.flatMap { id in ttsProject.voices.first(where: { $0.id == id }) }
            ?? ttsProject.voices.first
    }

    var quickTranslationSpeechVoice: TTSVoiceProfile? {
        quickTranslationSpeechVoiceID.flatMap { id in
            ttsProject.voices.first(where: { $0.id == id })
        } ?? ttsProject.voices.first
    }

    var quickTTSHasGeneratedAudio: Bool {
        guard let quickTTSOutputURL else { return false }
        return FileManager.default.fileExists(atPath: quickTTSOutputURL.path)
    }

    func bootstrapTTS() async {
        if let restored = try? ttsProjectStore.loadMostRecent() {
            ttsProject = restored
            ttsStatusMessage = "已恢复上次 TTS 项目"
        }
        let persistedVoiceID = ttsProject.selectedVoiceID.flatMap { selected in
            ttsProject.voices.contains(where: { $0.id == selected }) ? selected : nil
        }
        ttsSelectedVoiceID = persistedVoiceID ?? ttsProject.voices.first?.id
        ttsProject.selectedVoiceID = ttsSelectedVoiceID
        quickTTSSelectedVoiceID = ttsSelectedVoiceID ?? ttsProject.voices.first?.id
        // 翻译统一使用中性的已固化旁白，不跟随语音页或角色工作台的临时选择变化。
        quickTranslationSpeechVoiceID = ttsProject.voices.first(where: {
            $0.name == "温柔女旁白" && $0.referenceAudioRelativePath != nil
        })?.id ?? ttsProject.voices.first(where: {
            $0.id == ttsSelectedVoiceID && $0.referenceAudioRelativePath != nil
        })?.id ?? ttsProject.voices.first(where: {
            $0.referenceAudioRelativePath != nil
        })?.id ?? ttsSelectedVoiceID ?? ttsProject.voices.first?.id
        ttsAnalysisModelID = selectedLiveMeetingNotesModel?.id
        if let root = try? quickTranslationSpeechRootDirectory(projectID: ttsProject.id) {
            try? FileManager.default.removeItem(at: root)
        }
        quickTranslationSpeechCache.removeAll()
        await refreshTTSHealth()
    }

    func refreshTTSHealth() async {
        ttsHealth = await ttsService.health(for: ttsProject.modelVariant)
        ttsStatusMessage = ttsHealth?.message ?? "无法读取 TTS 健康状态"
    }

    func updateTTSSourceText(_ text: String) {
        guard text != ttsProject.sourceText else { return }
        ttsProject.sourceText = text
        // 源文案变化后旧脚本不再可信；单人模式生成时会自动重建，多角色模式要求重新识别。
        ttsProject.segments = []
        ttsStatusMessage = "文案已更新"
        scheduleTTSProjectSave()
    }

    func updateTTSProjectName(_ name: String) {
        ttsProject.name = name
        scheduleTTSProjectSave()
    }

    func selectTTSVoice(_ id: UUID) {
        guard ttsProject.voices.contains(where: { $0.id == id }) else { return }
        ttsSelectedVoiceID = id
        ttsProject.selectedVoiceID = id
        if ttsProject.mode == .singleNarrator {
            for index in ttsProject.segments.indices {
                guard ttsProject.segments[index].roleID != id else { continue }
                ttsProject.segments[index].roleID = id
                if ttsProject.segments[index].generationState == .completed {
                    ttsProject.segments[index].generationState = .stale
                }
            }
        }
        saveTTSProject()
    }

    func setTTSMode(_ mode: TTSProjectMode) {
        guard mode != ttsProject.mode else { return }
        ttsProject.mode = mode
        ttsProject.segments = []
        ttsStatusMessage = mode == .multiRole ? "请输入文案后识别角色" : "单人朗读模式"
        saveTTSProject()
    }

    func setTTSModelVariant(_ variant: TTSModelVariant) {
        // 完整工作台与快捷语音共用同一个 TTS sidecar，生成或试听期间不能切换模型。
        guard variant != ttsProject.modelVariant,
              !ttsIsGenerating,
              !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              ttsVoicePreviewInProgressID == nil
        else { return }
        ttsProject.modelVariant = variant
        saveTTSProject()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await ttsService.stopAndWait()
            await refreshTTSHealth()
        }
    }

    func analyzeTTSProject() {
        guard !ttsIsAnalyzing,
              !ttsIsGenerating,
              !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              ttsVoicePreviewInProgressID == nil
        else { return }
        let source = ttsProject.sourceText
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ttsStatusMessage = "请先输入需要配音的文案"
            return
        }
        if ttsProject.mode == .multiRole && localTTSAnalysisModels.isEmpty {
            ttsStatusMessage = "自然长文角色识别需要先配置一个本地 GGUF 或 MLX 文本模型"
            return
        }

        ttsAnalysisTask?.cancel()
        ttsIsAnalyzing = true
        ttsStatusMessage = ttsProject.mode == .multiRole ? "正在本地识别角色…" : "正在拆分朗读片段…"
        ttsAnalysisTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                ttsIsAnalyzing = false
                ttsAnalysisTask = nil
            }
            do {
                let analysis: TTSScriptAnalysis
                if ttsProject.mode == .singleNarrator {
                    analysis = TTSScriptParser.singleNarratorAnalysis(source)
                } else {
                    analysis = try await engine.analyzeTTSScript(
                        source: source,
                        modelID: ttsAnalysisModelID,
                        availableVoices: ttsProject.voices
                    )
                    // 角色分析完成后立即释放文本模型，避免与 VoxCPM2 同时占用统一内存。
                    await engine.unloadAll()
                }
                applyTTSAnalysis(TTSScriptParser.synthesisReadyAnalysis(analysis))
                ttsStatusMessage = "脚本已生成，请确认角色与台词后开始生成"
            } catch is CancellationError {
                ttsStatusMessage = "已取消角色识别"
                await engine.unloadAll()
            } catch {
                ttsStatusMessage = error.localizedDescription
                await engine.unloadAll()
            }
        }
    }

    func cancelTTSAnalysis() {
        ttsAnalysisTask?.cancel()
    }

    func generateTTSQueue() {
        startTTSGeneration(segmentIDs: nil, forceRegeneration: false)
    }

    func regenerateTTSSegment(_ id: UUID) {
        startTTSGeneration(segmentIDs: [id], forceRegeneration: true)
    }

    func cancelTTSGeneration() {
        ttsGenerationTask?.cancel()
        ttsStatusMessage = "正在停止 TTS 生成…"
    }

    func playTTSSegment(_ id: UUID) {
        let target = TTSPlaybackTarget.segment(id)
        if togglePausedTTSPlayback(for: target) { return }
        guard let segment = ttsProject.segments.first(where: { $0.id == id }),
              let relativePath = segment.audioRelativePath else { return }
        playTTSAudio(
            at: ttsProjectStore.resolve(relativePath: relativePath, projectID: ttsProject.id),
            target: target
        )
    }

    func playTTSProject() {
        if togglePausedTTSPlayback(for: .project) { return }
        do {
            let outputURL = try ttsProjectStore.audioDirectory(for: ttsProject.id)
                .appendingPathComponent("project-preview.wav")
            _ = try TTSAudioExporter.composeWAV(project: ttsProject, store: ttsProjectStore, outputURL: outputURL)
            playTTSAudio(at: outputURL, target: .project)
        } catch {
            ttsStatusMessage = error.localizedDescription
        }
    }

    func isTTSPlaying(_ target: TTSPlaybackTarget) -> Bool {
        ttsIsPlaying && ttsPlaybackTarget == target
    }

    func stopTTSPlayback() {
        ttsPlaybackMonitorTask?.cancel()
        ttsPlaybackMonitorTask = nil
        ttsAudioPlayer?.stop()
        ttsAudioPlayer = nil
        ttsIsPlaying = false
        ttsPlaybackTarget = nil
    }

    func updateQuickTTSInputText(_ text: String) {
        guard !quickTTSIsGenerating, text != quickTTSInputText else { return }
        quickTTSInputText = text
    }

    func updateQuickTTSDeliveryStyle(_ style: String) {
        let normalized = style.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              !normalized.isEmpty,
              normalized != quickTTSDeliveryStyle else { return }
        quickTTSDeliveryStyle = String(normalized.prefix(80))
    }

    func selectQuickTTSVoice(_ id: UUID) {
        guard !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              ttsProject.voices.contains(where: { $0.id == id }),
              id != quickTTSSelectedVoiceID else { return }
        quickTTSSelectedVoiceID = id
        // 输入、音色和风格只影响下一次生成，旧音频保留到用户再次点击生成。
    }

    func resetQuickActionSpeechSession() {
        if case .translation = ttsPlaybackTarget {
            stopTTSPlayback()
        }
        quickTTSInputText = ""
        quickTTSGenerationProgress = 0
        invalidateQuickTTSOutput()
        quickTranslationSpeechPendingRequest = nil
        quickTranslationSpeechCache.removeAll()
        quickTranslationSpeechProgress = 0
    }

    func previewQuickTTSVoice() {
        guard let voice = quickTTSSelectedVoice else {
            ttsStatusMessage = "请先选择音色"
            return
        }
        if ttsVoicePreviewInProgressID == voice.id {
            cancelTTSVoicePreview()
            return
        }
        guard !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              !ttsIsGenerating,
              !ttsIsAnalyzing else { return }
        if voice.previewAudioRelativePath != nil || voice.referenceAudioRelativePath != nil {
            playTTSVoicePreview(voice.id)
        } else {
            generateTTSVoicePreview(voice.id)
        }
    }

    func generateQuickTTS() {
        guard !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              !ttsIsGenerating,
              !ttsIsAnalyzing,
              ttsVoicePreviewInProgressID == nil else { return }
        let source = quickTTSInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            ttsStatusMessage = "请先输入需要生成语音的文字"
            return
        }
        guard let voice = quickTTSSelectedVoice else {
            ttsStatusMessage = "请先选择音色"
            return
        }
        guard ttsHealth?.status == .ready else {
            ttsStatusMessage = ttsHealth?.message ?? "请先检查 TTS runtime 与模型"
            return
        }
        if voice.origin == .cloned && voice.referenceAudioRelativePath == nil {
            ttsStatusMessage = "请先为克隆音色选择参考音频"
            return
        }
        if voice.origin == .cloned && !voice.usageRightsConfirmed {
            ttsStatusMessage = "请先在音色管理中确认克隆音色的使用授权"
            return
        }

        var segments = TTSScriptParser.synthesisReadyAnalysis(
            TTSScriptParser.singleNarratorAnalysis(source)
        ).segments
        guard !segments.isEmpty else {
            ttsStatusMessage = "没有可生成的朗读文字"
            return
        }
        for index in segments.indices {
            segments[index].roleID = voice.id
            segments[index].deliveryStyle = quickTTSDeliveryStyle
            segments[index].generationState = .pending
        }

        let projectID = ttsProject.id
        let variant = ttsProject.modelVariant
        let previousOutputURL = quickTTSOutputURL
        let generationDirectoryName = UUID().uuidString
        stopTTSPlayback()
        quickTTSIsGenerating = true
        quickTTSGenerationProgress = 0
        ttsStatusMessage = "正在启动 VoxCPM2…"
        quickTTSGenerationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var candidateDirectory: URL?
            var generatedOutputURL: URL?
            var generatedDuration: TimeInterval?
            do {
                let root = try ttsProjectStore.audioDirectory(for: projectID)
                    .appendingPathComponent("quick-action", isDirectory: true)
                    .appendingPathComponent(generationDirectoryName, isDirectory: true)
                candidateDirectory = root
                let segmentDirectory = root.appendingPathComponent("segments", isDirectory: true)
                try FileManager.default.createDirectory(at: segmentDirectory, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
                let referenceURL = voice.referenceAudioRelativePath.map {
                    ttsProjectStore.resolve(relativePath: $0, projectID: projectID)
                }

                for index in segments.indices {
                    try Task.checkCancellation()
                    let segmentURL = segmentDirectory.appendingPathComponent("\(index).wav")
                    ttsStatusMessage = "正在生成 \(index + 1)/\(segments.count)：\(voice.name)"
                    let result = try await ttsService.generate(
                        TTSGenerationRequest(
                            text: segments[index].spokenText,
                            instruction: ttsInstruction(for: voice, deliveryStyle: quickTTSDeliveryStyle),
                            referenceAudioURL: referenceURL,
                            referenceText: voice.referenceText.isEmpty ? nil : voice.referenceText,
                            outputURL: segmentURL
                        ),
                        variant: variant
                    )
                    try Task.checkCancellation()
                    segments[index].generationState = .completed
                    segments[index].audioRelativePath = ttsProjectStore.relativePath(
                        for: segmentURL,
                        projectID: projectID
                    )
                    segments[index].duration = result.duration
                    segments[index].generatedAt = .now
                    quickTTSGenerationProgress = Double(index + 1) / Double(segments.count)
                }

                let outputURL = root.appendingPathComponent("output.wav")
                let quickProject = TTSProject(
                    id: projectID,
                    name: "快速语音",
                    mode: .singleNarrator,
                    sourceText: source,
                    modelVariant: variant,
                    voices: [voice],
                    selectedVoiceID: voice.id,
                    segments: segments
                )
                let duration = try TTSAudioExporter.composeWAV(
                    project: quickProject,
                    store: ttsProjectStore,
                    outputURL: outputURL
                )
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
                try Task.checkCancellation()
                generatedOutputURL = outputURL
                generatedDuration = duration
            } catch is CancellationError {
                ttsStatusMessage = "已取消快速语音生成"
            } catch {
                ttsStatusMessage = error.localizedDescription
            }

            await ttsService.stopAndWait()
            if let generatedOutputURL, !Task.isCancelled {
                quickTTSOutputURL = generatedOutputURL
                quickTTSOutputDuration = generatedDuration
                if let previousOutputURL,
                   previousOutputURL.deletingLastPathComponent() != generatedOutputURL.deletingLastPathComponent() {
                    try? FileManager.default.removeItem(at: previousOutputURL.deletingLastPathComponent())
                }
                ttsStatusMessage = "语音已生成"
            } else if let candidateDirectory {
                try? FileManager.default.removeItem(at: candidateDirectory)
            }
            quickTTSIsGenerating = false
            quickTTSGenerationTask = nil
            if generatedOutputURL != nil, !Task.isCancelled {
                playQuickTTS()
            }
        }
    }

    func cancelQuickTTSGeneration() {
        guard quickTTSGenerationTask != nil else { return }
        quickTTSGenerationTask?.cancel()
        ttsStatusMessage = "正在停止快速语音生成…"
    }

    func playQuickTTS() {
        guard !quickTTSIsGenerating else { return }
        if togglePausedTTSPlayback(for: .quickAction) { return }
        guard let quickTTSOutputURL,
              FileManager.default.fileExists(atPath: quickTTSOutputURL.path) else {
            ttsStatusMessage = "请先生成语音"
            return
        }
        playTTSAudio(at: quickTTSOutputURL, target: .quickAction)
    }

    func exportQuickTTS(format: TTSExportFormat) {
        guard !quickTTSIsGenerating else { return }
        guard let quickTTSOutputURL,
              FileManager.default.fileExists(atPath: quickTTSOutputURL.path) else {
            ttsStatusMessage = "请先生成语音"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "快速语音.\(format.rawValue)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        do {
            try TTSAudioExporter.convert(wavURL: quickTTSOutputURL, to: outputURL, format: format)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
            ttsStatusMessage = "已导出 \(outputURL.lastPathComponent)"
        } catch {
            ttsStatusMessage = error.localizedDescription
        }
    }

    func toggleQuickTranslationSpeech(text: String, target: QuickTranslationSpeechTarget) {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        if let generatingTarget = quickTranslationSpeechGeneratingTarget {
            if generatingTarget == target {
                cancelQuickTranslationSpeech()
            } else {
                // 只保留最后一次点击；旧 sidecar 完全退出后再启动，避免两个请求争用同一管线。
                quickTranslationSpeechPendingRequest = PendingQuickTranslationSpeech(
                    text: source,
                    target: target
                )
                cancelQuickTranslationSpeech(clearPendingRequest: false)
                ttsStatusMessage = "正在切换朗读内容…"
            }
            return
        }

        let playbackTarget = TTSPlaybackTarget.translation(target)
        if togglePausedTTSPlayback(for: playbackTarget) { return }
        guard quickTranslationSpeechGeneratingTarget == nil,
              !quickTTSIsGenerating,
              !ttsIsGenerating,
              !ttsIsAnalyzing,
              ttsVoicePreviewInProgressID == nil,
              !ttsRuntimeInstallInProgress else { return }
        if let cached = quickTranslationSpeechCache[target],
           cached.text == source,
           FileManager.default.fileExists(atPath: cached.audioURL.path) {
            playTTSAudio(at: cached.audioURL, target: playbackTarget)
            return
        }
        guard let voice = quickTranslationSpeechVoice else {
            ttsStatusMessage = "没有可用的固定朗读音色"
            return
        }
        guard ttsHealth?.status == .ready else {
            ttsStatusMessage = ttsHealth?.message ?? "请先检查 TTS runtime 与模型"
            return
        }
        if voice.origin == .cloned && voice.referenceAudioRelativePath == nil {
            ttsStatusMessage = "请先为克隆音色选择参考音频"
            return
        }
        if voice.origin == .cloned && !voice.usageRightsConfirmed {
            ttsStatusMessage = "请先在音色管理中确认克隆音色的使用授权"
            return
        }

        var segments = TTSScriptParser.synthesisReadyAnalysis(
            TTSScriptParser.singleNarratorAnalysis(source)
        ).segments
        guard !segments.isEmpty else { return }
        let deliveryStyle: String
        switch target {
        case .term:
            deliveryStyle = "清晰标准发音，语速稍慢，只读出这个词语"
        case .source, .translation:
            deliveryStyle = "自然清晰朗读，语速适中"
        }
        for index in segments.indices {
            segments[index].roleID = voice.id
            segments[index].deliveryStyle = deliveryStyle
            segments[index].generationState = .pending
        }

        let projectID = ttsProject.id
        let variant = ttsProject.modelVariant
        let previousEntry = quickTranslationSpeechCache[target]
        let generationID = UUID().uuidString
        stopTTSPlayback()
        quickTranslationSpeechGeneratingTarget = target
        quickTranslationSpeechProgress = 0
        ttsStatusMessage = "正在生成朗读语音…"
        quickTranslationSpeechTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var candidateDirectory: URL?
            var generatedOutputURL: URL?
            do {
                let root = try quickTranslationSpeechRootDirectory(projectID: projectID)
                    .appendingPathComponent(generationID, isDirectory: true)
                candidateDirectory = root
                let segmentDirectory = root.appendingPathComponent("segments", isDirectory: true)
                try FileManager.default.createDirectory(at: segmentDirectory, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
                let referenceURL = voice.referenceAudioRelativePath.map {
                    ttsProjectStore.resolve(relativePath: $0, projectID: projectID)
                }
                let instruction = referenceURL == nil
                    ? ttsInstruction(for: voice, deliveryStyle: deliveryStyle)
                    : "严格保持参考音频中的同一音色，不改变年龄、性别、音高和声线；\(deliveryStyle)"

                for index in segments.indices {
                    try Task.checkCancellation()
                    let segmentURL = segmentDirectory.appendingPathComponent("\(index).wav")
                    ttsStatusMessage = "正在生成朗读 \(index + 1)/\(segments.count)…"
                    let result = try await ttsService.generate(
                        TTSGenerationRequest(
                            text: segments[index].spokenText,
                            instruction: instruction,
                            referenceAudioURL: referenceURL,
                            referenceText: voice.referenceText.isEmpty ? nil : voice.referenceText,
                            outputURL: segmentURL,
                            seed: 42
                        ),
                        variant: variant
                    )
                    try Task.checkCancellation()
                    segments[index].generationState = .completed
                    segments[index].audioRelativePath = ttsProjectStore.relativePath(
                        for: segmentURL,
                        projectID: projectID
                    )
                    segments[index].duration = result.duration
                    segments[index].generatedAt = .now
                    quickTranslationSpeechProgress = Double(index + 1) / Double(segments.count)
                }

                let outputURL = root.appendingPathComponent("output.wav")
                let temporaryProject = TTSProject(
                    id: projectID,
                    name: "快捷翻译朗读",
                    mode: .singleNarrator,
                    sourceText: source,
                    modelVariant: variant,
                    voices: [voice],
                    selectedVoiceID: voice.id,
                    segments: segments
                )
                _ = try TTSAudioExporter.composeWAV(
                    project: temporaryProject,
                    store: ttsProjectStore,
                    outputURL: outputURL
                )
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
                try Task.checkCancellation()
                generatedOutputURL = outputURL
            } catch is CancellationError {
                ttsStatusMessage = "已取消朗读生成"
            } catch {
                ttsStatusMessage = error.localizedDescription
            }

            await ttsService.stopAndWait()
            if let generatedOutputURL, !Task.isCancelled {
                quickTranslationSpeechCache[target] = QuickTranslationSpeechCacheEntry(
                    text: source,
                    audioURL: generatedOutputURL
                )
                if let previousEntry,
                   previousEntry.audioURL.deletingLastPathComponent()
                    != generatedOutputURL.deletingLastPathComponent() {
                    try? FileManager.default.removeItem(at: previousEntry.audioURL.deletingLastPathComponent())
                }
                ttsStatusMessage = "朗读语音已生成"
            } else if let candidateDirectory {
                try? FileManager.default.removeItem(at: candidateDirectory)
            }
            quickTranslationSpeechGeneratingTarget = nil
            quickTranslationSpeechProgress = 0
            quickTranslationSpeechTask = nil
            if let pending = quickTranslationSpeechPendingRequest {
                quickTranslationSpeechPendingRequest = nil
                toggleQuickTranslationSpeech(text: pending.text, target: pending.target)
            } else if let generatedOutputURL, !Task.isCancelled {
                playTTSAudio(at: generatedOutputURL, target: playbackTarget)
            }
        }
    }

    func cancelQuickTranslationSpeech(clearPendingRequest: Bool = true) {
        if clearPendingRequest {
            quickTranslationSpeechPendingRequest = nil
        }
        if quickTranslationSpeechTask != nil {
            quickTranslationSpeechTask?.cancel()
            ttsStatusMessage = "正在停止朗读生成…"
        }
        if case .translation = ttsPlaybackTarget {
            stopTTSPlayback()
        }
    }

    func exportTTSProject(format: TTSExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(sanitizedTTSProjectName()).\(format.rawValue)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        do {
            let workingWAV = try ttsProjectStore.audioDirectory(for: ttsProject.id)
                .appendingPathComponent("export-source.wav")
            _ = try TTSAudioExporter.composeWAV(project: ttsProject, store: ttsProjectStore, outputURL: workingWAV)
            try TTSAudioExporter.convert(wavURL: workingWAV, to: outputURL, format: format)
            ttsStatusMessage = "已导出 \(outputURL.lastPathComponent)"
        } catch {
            ttsStatusMessage = error.localizedDescription
        }
    }

    func exportTTSSRT() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(sanitizedTTSProjectName()).srt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        do {
            try Data(TTSAudioExporter.srt(project: ttsProject).utf8).write(to: outputURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
            ttsStatusMessage = "已导出 \(outputURL.lastPathComponent)"
        } catch {
            ttsStatusMessage = "字幕导出失败：\(error.localizedDescription)"
        }
    }

    func addTTSVoice() {
        let selectedGroupName = ttsSelectedVoiceID
            .flatMap { selectedID in ttsProject.voices.first(where: { $0.id == selectedID })?.groupName }
        let voice = TTSVoiceProfile(
            name: "新音色 \(ttsProject.voices.count + 1)",
            groupName: selectedGroupName
        )
        ttsProject.voices.append(voice)
        ttsSelectedVoiceID = voice.id
        ttsProject.selectedVoiceID = voice.id
        saveTTSProject()
    }

    func setTTSVoiceGroup(_ id: UUID, groupName: String?) {
        guard let index = ttsProject.voices.firstIndex(where: { $0.id == id }) else { return }
        let normalized = TTSVoiceCatalog.normalizedGroupName(groupName)
        guard TTSVoiceCatalog.normalizedGroupName(ttsProject.voices[index].groupName) != normalized else { return }

        // 分组只是管理元数据，不应让已生成音频失效；移组后放到目标组末尾更符合人工整理预期。
        var voice = ttsProject.voices.remove(at: index)
        voice.groupName = normalized
        let insertionIndex = ttsProject.voices.lastIndex {
            TTSVoiceCatalog.normalizedGroupName($0.groupName) == normalized
        }.map { $0 + 1 } ?? ttsProject.voices.endIndex
        ttsProject.voices.insert(voice, at: insertionIndex)
        ttsStatusMessage = normalized.map { "已移入分组“\($0)”" } ?? "已移到未分组"
        saveTTSProject()
    }

    func renameTTSVoiceGroup(_ groupName: String, to newName: String) {
        let current = TTSVoiceCatalog.normalizedGroupName(groupName)
        let replacement = TTSVoiceCatalog.normalizedGroupName(newName)
        guard let current, let replacement, current != replacement else { return }
        var changed = false
        for index in ttsProject.voices.indices
        where TTSVoiceCatalog.normalizedGroupName(ttsProject.voices[index].groupName) == current {
            ttsProject.voices[index].groupName = replacement
            changed = true
        }
        guard changed else { return }
        ttsStatusMessage = "分组已重命名为“\(replacement)”"
        saveTTSProject()
    }

    func removeTTSVoiceGroup(_ groupName: String) {
        guard let normalized = TTSVoiceCatalog.normalizedGroupName(groupName) else { return }
        var changed = false
        for index in ttsProject.voices.indices
        where TTSVoiceCatalog.normalizedGroupName(ttsProject.voices[index].groupName) == normalized {
            ttsProject.voices[index].groupName = nil
            changed = true
        }
        guard changed else { return }
        ttsStatusMessage = "已取消分组“\(normalized)”，音色保留在未分组"
        saveTTSProject()
    }

    func moveTTSVoice(_ id: UUID, by offset: Int) {
        guard let moved = TTSVoiceCatalog.movingVoice(id, by: offset, in: ttsProject.voices) else { return }
        ttsProject.voices = moved
        ttsStatusMessage = offset < 0 ? "音色已上移" : "音色已下移"
        saveTTSProject()
    }

    func removeTTSVoice(_ id: UUID) {
        guard quickTranslationSpeechGeneratingTarget == nil,
              ttsProject.voices.count > 1 else { return }
        ttsProject.voices.removeAll { $0.id == id }
        guard let replacementID = ttsProject.voices.first(where: { $0.name == "旁白" })?.id
                ?? ttsProject.voices.first?.id else { return }
        for index in ttsProject.segments.indices where ttsProject.segments[index].roleID == id {
            ttsProject.segments[index].roleID = replacementID
            ttsProject.segments[index].generationState = .stale
        }
        ttsSelectedVoiceID = replacementID
        ttsProject.selectedVoiceID = ttsSelectedVoiceID
        if quickTTSSelectedVoiceID == id {
            quickTTSSelectedVoiceID = replacementID
            invalidateQuickTTSOutput()
        }
        if quickTranslationSpeechVoiceID == id {
            quickTranslationSpeechVoiceID = replacementID
            quickTranslationSpeechCache.removeAll()
        }
        saveTTSProject()
    }

    func updateTTSVoice(_ id: UUID, _ update: (inout TTSVoiceProfile) -> Void) {
        guard quickTranslationSpeechGeneratingTarget == nil,
              let index = ttsProject.voices.firstIndex(where: { $0.id == id }) else { return }
        let previous = ttsProject.voices[index]
        update(&ttsProject.voices[index])
        var current = ttsProject.voices[index]
        if previous.origin != current.origin,
           previous.referenceAudioRelativePath == current.referenceAudioRelativePath {
            current.referenceAudioRelativePath = nil
            current.usageRightsConfirmed = false
        }
        if current.origin == .designed && previous.instruction != current.instruction {
            current.referenceAudioRelativePath = nil
        }
        if previous.origin != current.origin
            || previous.instruction != current.instruction
            || previous.referenceAudioRelativePath != current.referenceAudioRelativePath {
            current.previewAudioRelativePath = nil
        }
        ttsProject.voices[index] = current
        let synthesisChanged = previous.origin != current.origin
            || previous.instruction != current.instruction
            || previous.referenceAudioRelativePath != current.referenceAudioRelativePath
            || previous.referenceText != current.referenceText
        if synthesisChanged {
            for segmentIndex in ttsProject.segments.indices where ttsProject.segments[segmentIndex].roleID == id {
                if ttsProject.segments[segmentIndex].generationState == .completed {
                    ttsProject.segments[segmentIndex].generationState = .stale
                }
            }
        }
        scheduleTTSProjectSave()
    }

    func chooseTTSReferenceAudio(for voiceID: UUID) {
        guard quickTranslationSpeechGeneratingTarget == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        do {
            let voiceDirectory = try ttsProjectStore.audioDirectory(for: ttsProject.id)
                .appendingPathComponent("voices", isDirectory: true)
            try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: voiceDirectory.path)
            let fileExtension = sourceURL.pathExtension.isEmpty ? "wav" : sourceURL.pathExtension
            let destination = voiceDirectory.appendingPathComponent("\(voiceID.uuidString).\(fileExtension)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            updateTTSVoice(voiceID) { voice in
                voice.origin = .cloned
                voice.referenceAudioRelativePath = ttsProjectStore.relativePath(
                    for: destination,
                    projectID: ttsProject.id
                )
                voice.previewAudioRelativePath = nil
                voice.usageRightsConfirmed = false
            }
            saveTTSProject()
            ttsStatusMessage = "已导入参考音频，请确认拥有使用授权"
        } catch {
            ttsStatusMessage = "参考音频导入失败：\(error.localizedDescription)"
        }
    }

    func clearTTSReferenceAudio(for voiceID: UUID) {
        updateTTSVoice(voiceID) { voice in
            voice.referenceAudioRelativePath = nil
            voice.previewAudioRelativePath = nil
            voice.referenceText = ""
            voice.usageRightsConfirmed = false
        }
    }

    func updateTTSVoicePreviewText(_ text: String) {
        ttsProject.voicePreviewText = text
        scheduleTTSProjectSave()
    }

    func generateTTSVoicePreview(_ voiceID: UUID) {
        guard ttsVoicePreviewInProgressID == nil,
              !ttsIsGenerating,
              !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              !ttsIsAnalyzing,
              let voice = ttsProject.voices.first(where: { $0.id == voiceID }) else { return }
        let previewText = ttsVoicePreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previewText.isEmpty else {
            ttsStatusMessage = "试听文本不能为空"
            return
        }
        guard ttsHealth?.status == .ready else {
            ttsStatusMessage = ttsHealth?.message ?? "请先检查 TTS runtime 与模型"
            return
        }
        if voice.origin == .cloned && voice.referenceAudioRelativePath == nil {
            ttsStatusMessage = "请先选择克隆参考音频"
            return
        }
        if voice.origin == .cloned && !voice.usageRightsConfirmed {
            ttsStatusMessage = "请先确认该声音拥有合法使用授权"
            return
        }

        stopTTSPlayback()
        ttsVoicePreviewInProgressID = voiceID
        let wasSolidified = voice.referenceAudioRelativePath != nil
        let previousPreviewPath = voice.previewAudioRelativePath
        ttsStatusMessage = "正在生成音色试听…"
        ttsVoicePreviewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                ttsVoicePreviewInProgressID = nil
                ttsVoicePreviewTask = nil
            }
            do {
                let voiceDirectory = try ttsProjectStore.audioDirectory(for: ttsProject.id)
                    .appendingPathComponent("voices", isDirectory: true)
                try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: voiceDirectory.path)
                // 候选音频使用新文件，生成失败时继续保留当前已固化锚点。
                let outputURL = voiceDirectory.appendingPathComponent(
                    "\(voiceID.uuidString)-preview-\(UUID().uuidString).wav"
                )
                let referenceURL = voice.origin == .cloned ? voice.referenceAudioRelativePath.map {
                    ttsProjectStore.resolve(relativePath: $0, projectID: ttsProject.id)
                } : nil
                _ = try await ttsService.generate(
                    TTSGenerationRequest(
                        text: previewText,
                        instruction: voice.instruction.isEmpty ? nil : voice.instruction,
                        referenceAudioURL: referenceURL,
                        referenceText: voice.referenceText.isEmpty ? nil : voice.referenceText,
                        outputURL: outputURL,
                        seed: voice.origin == .designed ? UInt64(UInt32.random(in: .min ... .max)) : 42
                    ),
                    variant: ttsProject.modelVariant
                )
                try Task.checkCancellation()
                guard let index = ttsProject.voices.firstIndex(where: { $0.id == voiceID }) else {
                    await ttsService.stopAndWait()
                    return
                }
                let relativePath = ttsProjectStore.relativePath(for: outputURL, projectID: ttsProject.id)
                ttsProject.voices[index].previewAudioRelativePath = relativePath
                if ttsProject.voices[index].origin == .designed {
                    ttsProject.voices[index].referenceAudioRelativePath = relativePath
                    ttsProject.voices[index].usageRightsConfirmed = true
                    for segmentIndex in ttsProject.segments.indices
                    where ttsProject.segments[segmentIndex].roleID == voiceID
                        && ttsProject.segments[segmentIndex].generationState == .completed {
                        ttsProject.segments[segmentIndex].generationState = .stale
                    }
                }
                saveTTSProject()
                if let previousPreviewPath,
                   previousPreviewPath != relativePath,
                   previousPreviewPath.hasPrefix("audio/voices/") {
                    try? FileManager.default.removeItem(
                        at: ttsProjectStore.resolve(
                            relativePath: previousPreviewPath,
                            projectID: ttsProject.id
                        )
                    )
                }
                await ttsService.stopAndWait()
                playTTSAudio(at: outputURL, target: .voice(voiceID))
                if voice.origin == .designed {
                    ttsStatusMessage = wasSolidified ? "音色已重新固化并开始试听" : "音色已固化并开始试听"
                } else {
                    ttsStatusMessage = "克隆音色试听已生成"
                }
            } catch is CancellationError {
                await ttsService.stopAndWait()
                ttsStatusMessage = "已取消音色试听"
            } catch {
                await ttsService.stopAndWait()
                ttsStatusMessage = error.localizedDescription
            }
        }
    }

    func cancelTTSVoicePreview() {
        ttsVoicePreviewTask?.cancel()
    }

    func playTTSVoicePreview(_ voiceID: UUID) {
        let target = TTSPlaybackTarget.voice(voiceID)
        if togglePausedTTSPlayback(for: target) { return }
        guard let voice = ttsProject.voices.first(where: { $0.id == voiceID }),
              let relativePath = voice.previewAudioRelativePath ?? voice.referenceAudioRelativePath else {
            ttsStatusMessage = "请先生成音色试听"
            return
        }
        playTTSAudio(
            at: ttsProjectStore.resolve(relativePath: relativePath, projectID: ttsProject.id),
            target: target
        )
    }

    func updateTTSSegmentText(id: UUID, text: String) {
        guard let index = ttsProject.segments.firstIndex(where: { $0.id == id }) else { return }
        ttsProject.segments[index].spokenText = text
        ttsProject.segments[index].generationState = .stale
        scheduleTTSProjectSave()
    }

    func updateTTSSegmentDeliveryStyle(id: UUID, style: String) {
        guard let index = ttsProject.segments.firstIndex(where: { $0.id == id }) else { return }
        let normalized = style.trimmingCharacters(in: .whitespacesAndNewlines)
        ttsProject.segments[index].deliveryStyle = normalized.isEmpty ? nil : String(normalized.prefix(80))
        if ttsProject.segments[index].generationState == .completed {
            ttsProject.segments[index].generationState = .stale
        }
        scheduleTTSProjectSave()
    }

    func updateTTSSegmentPause(id: UUID, milliseconds: Int) {
        guard let index = ttsProject.segments.firstIndex(where: { $0.id == id }) else { return }
        ttsProject.segments[index].pauseAfterMilliseconds = min(max(milliseconds, 150), 2_000)
        scheduleTTSProjectSave()
    }

    func setTTSSegmentRole(id: UUID, roleID: UUID) {
        guard let index = ttsProject.segments.firstIndex(where: { $0.id == id }),
              ttsProject.voices.contains(where: { $0.id == roleID }) else { return }
        let speakerName = ttsProject.segments[index].speakerName
        for segmentIndex in ttsProject.segments.indices {
            let isTarget = ttsProject.segments[segmentIndex].id == id
                || (ttsProject.mode == .multiRole
                    && speakerName?.isEmpty == false
                    && ttsProject.segments[segmentIndex].speakerName == speakerName)
            guard isTarget else { continue }
            ttsProject.segments[segmentIndex].roleID = roleID
            if ttsProject.segments[segmentIndex].generationState == .completed {
                ttsProject.segments[segmentIndex].generationState = .stale
            }
        }
        scheduleTTSProjectSave()
    }

    func installTTSRuntime(downloadModel: Bool = false) {
        guard !ttsRuntimeInstallInProgress,
              !ttsIsGenerating,
              !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              ttsVoicePreviewInProgressID == nil
        else { return }
        ttsRuntimeInstallInProgress = true
        ttsStatusMessage = downloadModel ? "正在下载本地 VoxCPM2 模型…" : "正在安装独立 TTS runtime…"
        let variant = ttsProject.modelVariant
        ttsRuntimeInstallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                ttsRuntimeInstallInProgress = false
                ttsRuntimeInstallTask = nil
            }
            do {
                let path = try Self.ttsInstallerPath()
                let result = try await Self.runTTSInstaller(
                    at: path,
                    variant: variant,
                    downloadModel: downloadModel
                )
                guard result.terminationStatus == 0 else {
                    let message = String(data: result.standardError, encoding: .utf8)
                        ?? String(data: result.standardOutput, encoding: .utf8)
                        ?? "exit \(result.terminationStatus)"
                    let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    throw downloadModel ? TTSError.modelMissing(detail) : TTSError.runtimeMissing(detail)
                }
                await refreshTTSHealth()
            } catch {
                ttsStatusMessage = error.localizedDescription
            }
        }
    }

    func stopTTSForShutdown() async {
        ttsAnalysisTask?.cancel()
        ttsGenerationTask?.cancel()
        ttsRuntimeInstallTask?.cancel()
        ttsProjectSaveTask?.cancel()
        ttsVoicePreviewTask?.cancel()
        quickTTSGenerationTask?.cancel()
        quickTranslationSpeechTask?.cancel()
        quickTranslationSpeechPendingRequest = nil
        stopTTSPlayback()
        saveTTSProject()
        await ttsService.stopAndWait()
        if let root = try? quickTranslationSpeechRootDirectory(projectID: ttsProject.id) {
            try? FileManager.default.removeItem(at: root)
        }
        quickTranslationSpeechCache.removeAll()
    }

    func saveTTSProject() {
        ttsProjectSaveTask?.cancel()
        ttsProjectSaveTask = nil
        persistTTSProject()
    }

    private func scheduleTTSProjectSave() {
        ttsProjectSaveTask?.cancel()
        ttsProjectSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            ttsProjectSaveTask = nil
            persistTTSProject()
        }
    }

    private func persistTTSProject() {
        do {
            try ttsProjectStore.save(ttsProject)
        } catch {
            ttsStatusMessage = error.localizedDescription
        }
    }

    private func applyTTSAnalysis(_ analysis: TTSScriptAnalysis) {
        if ttsProject.mode == .singleNarrator,
           let selectedID = ttsSelectedVoiceID ?? ttsProject.voices.first?.id,
           ttsProject.voices.contains(where: { $0.id == selectedID }) {
            var segments = analysis.segments
            for index in segments.indices {
                segments[index].roleID = selectedID
                segments[index].generationState = .pending
            }
            ttsProject.selectedVoiceID = selectedID
            ttsProject.segments = segments
            saveTTSProject()
            return
        }

        let existingByName = Dictionary(
            ttsProject.voices.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingByID = Dictionary(uniqueKeysWithValues: ttsProject.voices.map { ($0.id, $0) })
        var roleMapping: [UUID: UUID] = [:]
        for analyzed in analysis.voices {
            if let existing = existingByID[analyzed.id] ?? existingByName[analyzed.name] {
                roleMapping[analyzed.id] = existing.id
            }
        }
        guard let fallbackVoiceID = ttsSelectedVoiceID.flatMap({ existingByID[$0]?.id })
                ?? ttsProject.voices.first?.id else {
            ttsStatusMessage = "角色分析没有返回可用音色"
            return
        }
        var segments = analysis.segments
        for index in segments.indices {
            // 角色识别只能选择项目现有音色；模型或解析器异常时回退，但绝不创建虚构音色。
            segments[index].roleID = roleMapping[segments[index].roleID] ?? fallbackVoiceID
            segments[index].generationState = .pending
        }
        ttsProject.segments = segments
        if ttsSelectedVoiceID == nil {
            ttsSelectedVoiceID = ttsProject.voices.first?.id
        }
        ttsProject.selectedVoiceID = ttsSelectedVoiceID
        saveTTSProject()
    }

    private func startTTSGeneration(segmentIDs: Set<UUID>?, forceRegeneration: Bool) {
        guard !ttsIsGenerating,
              !quickTTSIsGenerating,
              quickTranslationSpeechGeneratingTarget == nil,
              !ttsIsAnalyzing,
              ttsVoicePreviewInProgressID == nil else { return }
        if ttsProject.segments.isEmpty {
            guard ttsProject.mode == .singleNarrator,
                  !ttsProject.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                ttsStatusMessage = "请先输入文案，或识别并确认多角色脚本"
                return
            }
            applyTTSAnalysis(
                TTSScriptParser.synthesisReadyAnalysis(
                    TTSScriptParser.singleNarratorAnalysis(ttsProject.sourceText)
                )
            )
        }
        let targets = ttsProject.segments.filter { segment in
            if let segmentIDs { return segmentIDs.contains(segment.id) }
            return forceRegeneration || segment.generationState != .completed
        }.map(\.id)
        guard !targets.isEmpty else {
            ttsStatusMessage = "所有片段都已生成"
            return
        }
        guard ttsHealth?.status == .ready else {
            ttsStatusMessage = ttsHealth?.message ?? "请先检查 TTS runtime 与模型"
            return
        }

        stopTTSPlayback()
        ttsGenerationTask?.cancel()
        ttsIsGenerating = true
        ttsGenerationProgress = 0
        ttsStatusMessage = "正在启动 VoxCPM2…"
        ttsGenerationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var processed = 0
            for segmentID in targets {
                if Task.isCancelled { break }
                guard let segmentIndex = ttsProject.segments.firstIndex(where: { $0.id == segmentID }),
                      let voiceIndex = ttsProject.voices.firstIndex(where: {
                          $0.id == ttsProject.segments[segmentIndex].roleID
                      }) else { continue }
                let voice = ttsProject.voices[voiceIndex]
                if ttsProject.segments[segmentIndex].spokenText
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ttsProject.segments[segmentIndex].generationState = .failed
                    ttsProject.segments[segmentIndex].errorMessage = "朗读文本不能为空"
                    processed += 1
                    ttsGenerationProgress = Double(processed) / Double(targets.count)
                    saveTTSProject()
                    continue
                }
                if voice.origin == .cloned && voice.referenceAudioRelativePath == nil {
                    ttsProject.segments[segmentIndex].generationState = .failed
                    ttsProject.segments[segmentIndex].errorMessage = "请先为克隆音色选择参考音频"
                    processed += 1
                    ttsGenerationProgress = Double(processed) / Double(targets.count)
                    saveTTSProject()
                    continue
                }
                if voice.origin == .cloned && !voice.usageRightsConfirmed {
                    ttsProject.segments[segmentIndex].generationState = .failed
                    ttsProject.segments[segmentIndex].errorMessage = "请先确认该克隆音色拥有合法使用授权"
                    processed += 1
                    ttsGenerationProgress = Double(processed) / Double(targets.count)
                    saveTTSProject()
                    continue
                }
                do {
                    let audioDirectory = try ttsProjectStore.audioDirectory(for: ttsProject.id)
                        .appendingPathComponent("segments", isDirectory: true)
                    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: audioDirectory.path)
                    let outputURL = audioDirectory.appendingPathComponent("\(segmentID.uuidString).wav")
                    let referenceURL = voice.referenceAudioRelativePath.map {
                        ttsProjectStore.resolve(relativePath: $0, projectID: ttsProject.id)
                    }
                    let instruction = ttsInstruction(
                        for: voice,
                        segment: ttsProject.segments[segmentIndex]
                    )
                    ttsProject.segments[segmentIndex].generationState = .generating
                    ttsProject.segments[segmentIndex].errorMessage = nil
                    ttsStatusMessage = "正在生成 \(processed + 1)/\(targets.count)：\(voice.name)"
                    // 生成中状态只用于界面反馈，完成或失败后再落盘，避免每段开始时同步编码整份项目。
                    let result = try await ttsService.generate(
                        TTSGenerationRequest(
                            text: ttsProject.segments[segmentIndex].spokenText,
                            instruction: instruction,
                            referenceAudioURL: referenceURL,
                            referenceText: voice.referenceText.isEmpty ? nil : voice.referenceText,
                            outputURL: outputURL
                        ),
                        variant: ttsProject.modelVariant
                    )
                    if Task.isCancelled { break }
                    let relativePath = ttsProjectStore.relativePath(for: outputURL, projectID: ttsProject.id)
                    ttsProject.segments[segmentIndex].generationState = .completed
                    ttsProject.segments[segmentIndex].audioRelativePath = relativePath
                    ttsProject.segments[segmentIndex].duration = result.duration
                    ttsProject.segments[segmentIndex].generatedAt = .now
                    // 设计音色首次生成后固定为该角色锚点，后续片段才能保持稳定音色。
                    if voice.origin == .designed && voice.referenceAudioRelativePath == nil {
                        ttsProject.voices[voiceIndex].referenceAudioRelativePath = relativePath
                        ttsProject.voices[voiceIndex].previewAudioRelativePath = relativePath
                        ttsProject.voices[voiceIndex].usageRightsConfirmed = true
                    }
                } catch {
                    if Task.isCancelled { break }
                    ttsProject.segments[segmentIndex].generationState = .failed
                    ttsProject.segments[segmentIndex].errorMessage = error.localizedDescription
                }
                processed += 1
                ttsGenerationProgress = Double(processed) / Double(targets.count)
                saveTTSProject()
            }
            for index in ttsProject.segments.indices where ttsProject.segments[index].generationState == .generating {
                ttsProject.segments[index].generationState = .pending
            }
            let wasCancelled = Task.isCancelled
            await ttsService.stopAndWait()
            saveTTSProject()
            ttsIsGenerating = false
            ttsGenerationTask = nil
            ttsStatusMessage = wasCancelled ? "已停止生成，可继续未完成队列" : "生成队列已完成"
        }
    }

    private func ttsInstruction(for voice: TTSVoiceProfile, segment: TTSSegment) -> String? {
        ttsInstruction(for: voice, deliveryStyle: segment.deliveryStyle)
    }

    private func ttsInstruction(for voice: TTSVoiceProfile, deliveryStyle: String?) -> String? {
        let voiceDescription = voice.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliveryStyle = deliveryStyle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (voiceDescription.isEmpty, deliveryStyle.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return voiceDescription
        case (true, false):
            return "保持当前音色，本段表达：\(deliveryStyle)"
        case (false, false):
            // VoxCPM2 支持参考音色叠加自然语言风格控制，角色音色与本段语气放在同一 instruct 中。
            return "\(voiceDescription)；保持该音色，本段表达：\(deliveryStyle)"
        }
    }

    private func quickTranslationSpeechRootDirectory(projectID: UUID) throws -> URL {
        try ttsProjectStore.audioDirectory(for: projectID)
            .appendingPathComponent("quick-translation", isDirectory: true)
    }

    private func invalidateQuickTTSOutput() {
        if ttsPlaybackTarget == .quickAction {
            stopTTSPlayback()
        }
        quickTTSOutputURL = nil
        quickTTSOutputDuration = nil
    }

    private func togglePausedTTSPlayback(for target: TTSPlaybackTarget) -> Bool {
        guard ttsPlaybackTarget == target, let player = ttsAudioPlayer else { return false }
        if ttsIsPlaying {
            player.pause()
            ttsPlaybackMonitorTask?.cancel()
            ttsPlaybackMonitorTask = nil
            ttsIsPlaying = false
            ttsStatusMessage = "已暂停试听"
        } else if player.play() {
            ttsIsPlaying = true
            monitorTTSPlayback()
            ttsStatusMessage = "继续试听"
        }
        return true
    }

    private func playTTSAudio(at url: URL, target: TTSPlaybackTarget) {
        do {
            stopTTSPlayback()
            ttsAudioPlayer = try AVAudioPlayer(contentsOf: url)
            ttsAudioPlayer?.prepareToPlay()
            guard ttsAudioPlayer?.play() == true else {
                throw TTSError.generationFailed("音频播放器无法开始播放。")
            }
            ttsPlaybackTarget = target
            ttsIsPlaying = true
            monitorTTSPlayback()
            ttsStatusMessage = "正在播放 \(url.lastPathComponent)"
        } catch {
            stopTTSPlayback()
            ttsStatusMessage = "播放失败：\(error.localizedDescription)"
        }
    }

    private func monitorTTSPlayback() {
        ttsPlaybackMonitorTask?.cancel()
        ttsPlaybackMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                guard ttsIsPlaying else { return }
                if ttsAudioPlayer?.isPlaying != true {
                    ttsAudioPlayer = nil
                    ttsIsPlaying = false
                    ttsPlaybackTarget = nil
                    ttsPlaybackMonitorTask = nil
                    ttsStatusMessage = "试听结束"
                    return
                }
            }
        }
    }

    private func sanitizedTTSProjectName() -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let name = ttsProject.name.components(separatedBy: invalid).joined(separator: "-")
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "本地配音" : name
    }

    private nonisolated static func ttsInstallerPath() throws -> String {
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("tts", isDirectory: true)
                .appendingPathComponent("install-tts-voxcpm2-runtime.sh").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("install-tts-voxcpm2-runtime.sh").path
        ].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw TTSError.runtimeMissing("未找到 TTS runtime 安装脚本。")
        }
        return path
    }

    private nonisolated static func runTTSInstaller(
        at path: String,
        variant: TTSModelVariant,
        downloadModel: Bool
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.currentDirectoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:"
            + (environment["PATH"] ?? "")
        environment["LLMTOOLS_TTS_DOWNLOAD_MODEL"] = downloadModel ? "1" : "0"
        switch variant {
        case .voxCPM2BF16: environment["LLMTOOLS_TTS_VARIANT"] = "bf16"
        case .voxCPM2FourBit: environment["LLMTOOLS_TTS_VARIANT"] = "4bit"
        case .voxCPM2EightBit: environment["LLMTOOLS_TTS_VARIANT"] = "8bit"
        }
        process.environment = environment
        return try await ProcessOutputCollector.run(process)
    }
}
