import Foundation

public enum TTSError: Error, LocalizedError, Sendable {
    case invalidScript(String)
    case runtimeMissing(String)
    case modelMissing(String)
    case generationFailed(String)
    case projectStorageFailed(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidScript(let message): return "角色识别失败：\(message)"
        case .runtimeMissing(let message): return "TTS runtime 不可用：\(message)"
        case .modelMissing(let message): return "VoxCPM2 模型不可用：\(message)"
        case .generationFailed(let message): return "语音生成失败：\(message)"
        case .projectStorageFailed(let message): return "TTS 项目保存失败：\(message)"
        case .exportFailed(let message): return "音频导出失败：\(message)"
        }
    }
}

public enum TTSScriptParser {
    private struct AnalysisRole: Decodable {
        var name: String
        var aliases: [String]?
        var voiceHint: String?
    }

    private struct AssignmentEnvelope: Decodable {
        var roles: [AnalysisRole]
        var assignments: [AnalysisAssignment]
    }

    private struct AnalysisAssignment: Decodable {
        var index: Int
        var speaker: String
        var voiceIndex: Int?
        var type: String?
        var confidence: Double?
        var deliveryStyle: String?
        var pauseAfterMilliseconds: Int?
    }

    public static func explicitAnalysis(_ source: String) -> TTSScriptAnalysis? {
        guard let expression = try? NSRegularExpression(
            pattern: #"^\s*(?:\[([^\]]+)\]|([^：:\n，。！？；、“”"']{1,16})[：:])\s*(.+?)\s*$"#
        ) else { return nil }
        let lines = source.components(separatedBy: .newlines)
        var voices = [TTSVoiceProfile(name: "旁白")]
        var voiceIDs: [String: UUID] = ["旁白": voices[0].id]
        var segments: [TTSSegment] = []
        var characterOffset = 0
        var explicitLineCount = 0

        for line in lines {
            defer { characterOffset += line.count + 1 }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = expression.firstMatch(in: line, range: range),
               let textRange = Range(match.range(at: 3), in: line) {
                let bracketName = Range(match.range(at: 1), in: line).map { String(line[$0]) }
                let colonName = Range(match.range(at: 2), in: line).map { String(line[$0]) }
                let name = (bracketName ?? colonName ?? "待确认").trimmingCharacters(in: .whitespacesAndNewlines)
                let roleID: UUID
                if let existing = voiceIDs[name] {
                    roleID = existing
                } else {
                    let voice = TTSVoiceProfile(name: name)
                    voices.append(voice)
                    voiceIDs[name] = voice.id
                    roleID = voice.id
                }
                let text = String(line[textRange])
                let start = characterOffset + line.distance(from: line.startIndex, to: textRange.lowerBound)
                segments.append(TTSSegment(
                    index: segments.count,
                    kind: name == "旁白" ? .narration : .dialogue,
                    roleID: roleID,
                    speakerName: name,
                    sourceText: text,
                    sourceStart: start,
                    sourceEnd: start + text.count,
                    pauseAfterMilliseconds: suggestedPauseAfterMilliseconds(for: text, kind: name == "旁白" ? .narration : .dialogue)
                ))
                explicitLineCount += 1
            } else {
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let leading = line.count - line.drop(while: { $0.isWhitespace }).count
                let start = characterOffset + leading
                segments.append(TTSSegment(
                    index: segments.count,
                    kind: .narration,
                    roleID: voices[0].id,
                    speakerName: "旁白",
                    sourceText: text,
                    sourceStart: start,
                    sourceEnd: start + text.count,
                    pauseAfterMilliseconds: suggestedPauseAfterMilliseconds(for: text, kind: .narration)
                ))
            }
        }
        // 小说常见“动作描写：台词”，显式脚本必须让每个非空行都带角色前缀。
        guard explicitLineCount > 0, explicitLineCount == segments.count else { return nil }
        return TTSScriptAnalysis(voices: voices, segments: segments)
    }

    public static func singleNarratorAnalysis(
        _ source: String,
        maximumCharacters: Int = 240
    ) -> TTSScriptAnalysis {
        let voice = TTSVoiceProfile(name: "旁白")
        let chunks = synthesisChunks(source, maximumCharacters: maximumCharacters)
        var cursor = source.startIndex
        let segments = chunks.enumerated().map { index, text -> TTSSegment in
            let located = source.range(of: text, range: cursor..<source.endIndex)
            let start = located.map { source.distance(from: source.startIndex, to: $0.lowerBound) }
            if let located { cursor = located.upperBound }
            return TTSSegment(
                index: index,
                kind: .narration,
                roleID: voice.id,
                speakerName: "旁白",
                sourceText: text,
                sourceStart: start,
                sourceEnd: start.map { $0 + text.count },
                pauseAfterMilliseconds: suggestedPauseAfterMilliseconds(for: text, kind: .narration)
            )
        }
        return TTSScriptAnalysis(voices: [voice], segments: segments)
    }

    public static func sourceUnits(
        _ source: String,
        maximumCharacters: Int = 180
    ) -> [TTSSourceUnit] {
        let boundaries = CharacterSet(charactersIn: "。！？!?；;\n")
        let openingQuotes: [Character: Character] = [
            "“": "”",
            "‘": "’",
            "「": "」",
            "『": "』",
            "\"": "\""
        ]
        var rawUnits: [String] = []
        var current = ""
        var expectedClosingQuotes: [Character] = []

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { rawUnits.append(trimmed) }
            current = ""
        }

        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if expectedClosingQuotes.isEmpty, let closingQuote = openingQuotes[character] {
                // 小说里的“动作描写：台词”必须先拆成旁白和台词，角色模型只负责判断说话人。
                flushCurrent()
                current.append(character)
                expectedClosingQuotes.append(closingQuote)
            } else {
                current.append(character)
                if character == expectedClosingQuotes.last {
                    expectedClosingQuotes.removeLast()
                    if expectedClosingQuotes.isEmpty { flushCurrent() }
                } else if let closingQuote = openingQuotes[character], !expectedClosingQuotes.isEmpty {
                    expectedClosingQuotes.append(closingQuote)
                } else if expectedClosingQuotes.isEmpty,
                          character.unicodeScalars.allSatisfy({ boundaries.contains($0) }) {
                    flushCurrent()
                }
            }
            index = source.index(after: index)
        }
        flushCurrent()

        let bounded = rawUnits.flatMap { unit -> [String] in
            unit.count <= maximumCharacters
                ? [unit]
                : synthesisChunks(unit, maximumCharacters: maximumCharacters)
        }
        var cursor = source.startIndex
        var result: [TTSSourceUnit] = []
        for (unitIndex, text) in bounded.enumerated() {
            guard let range = source.range(of: text, range: cursor..<source.endIndex) else { return [] }
            cursor = range.upperBound
            result.append(TTSSourceUnit(
                index: unitIndex,
                text: text,
                sourceStart: source.distance(from: source.startIndex, to: range.lowerBound),
                sourceEnd: source.distance(from: source.startIndex, to: range.upperBound)
            ))
        }
        let normalizedSource = source.filter { !$0.isWhitespace }
        let normalizedUnits = result.map(\.text).joined().filter { !$0.isWhitespace }
        return normalizedSource == normalizedUnits ? result : []
    }

    public static func sourceUnitChunks(
        _ units: [TTSSourceUnit],
        maximumCharacters: Int = 900,
        maximumUnits: Int = 16
    ) -> [[TTSSourceUnit]] {
        var result: [[TTSSourceUnit]] = []
        var current: [TTSSourceUnit] = []
        var currentCharacters = 0
        let unitLimit = max(1, maximumUnits)
        for unit in units {
            if !current.isEmpty
                && (current.count >= unitLimit || currentCharacters + unit.text.count > maximumCharacters) {
                result.append(current)
                current = []
                currentCharacters = 0
            }
            current.append(unit)
            currentCharacters += unit.text.count
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    public static func parseModelAssignments(
        _ raw: String,
        units: [TTSSourceUnit],
        availableVoices: [TTSVoiceProfile] = []
    ) throws -> TTSScriptAnalysis {
        let envelope: AssignmentEnvelope
        do {
            envelope = try JSONDecoder().decode(AssignmentEnvelope.self, from: extractedJSONObject(from: raw))
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.invalidScript("本地模型没有返回有效的角色分配 JSON。")
        }
        let expectedIndices = Set(units.map(\.index))
        let returnedIndices = envelope.assignments.map(\.index)
        guard returnedIndices.count == Set(returnedIndices).count,
              Set(returnedIndices) == expectedIndices else {
            throw TTSError.invalidScript("角色分析没有完整返回全部句段索引。")
        }

        let usesVoiceCatalog = !availableVoices.isEmpty
        var voices = usesVoiceCatalog ? availableVoices : [TTSVoiceProfile(name: "旁白")]
        var voiceIDs: [String: UUID] = [:]
        if !usesVoiceCatalog {
            voiceIDs = ["旁白": voices[0].id, "narrator": voices[0].id]
            for role in envelope.roles {
                let name = role.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isPlausibleRoleName(name), voiceIDs[name] == nil else { continue }
                let voice = TTSVoiceProfile(name: name, instruction: role.voiceHint ?? "")
                voices.append(voice)
                voiceIDs[name] = voice.id
                for alias in role.aliases ?? [] where !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    voiceIDs[alias] = voice.id
                }
            }
        }

        let assignmentByIndex = Dictionary(uniqueKeysWithValues: envelope.assignments.map { ($0.index, $0) })
        let segments = try units.map { unit -> TTSSegment in
            guard let assignment = assignmentByIndex[unit.index] else {
                throw TTSError.invalidScript("角色分析遗漏了句段 \(unit.index)。")
            }
            let speaker = assignment.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            let roleID: UUID
            if usesVoiceCatalog {
                // 有现成音色时，模型只返回目录索引；角色名仍单独保留用于跨片段一致性和人工复核。
                guard let voiceIndex = assignment.voiceIndex,
                      availableVoices.indices.contains(voiceIndex) else {
                    throw TTSError.invalidScript("角色分析返回了无效的音色编号。")
                }
                roleID = availableVoices[voiceIndex].id
            } else if speaker.isEmpty
                || speaker == "旁白"
                || speaker.lowercased() == "narrator"
                || !isPlausibleRoleName(speaker) {
                roleID = voices[0].id
            } else if let existing = voiceIDs[speaker] {
                roleID = existing
            } else {
                let voice = TTSVoiceProfile(name: speaker)
                voices.append(voice)
                voiceIDs[speaker] = voice.id
                roleID = voice.id
            }
            let isNarration = assignment.type?.lowercased() == "narration"
                || speaker == "旁白"
                || speaker.lowercased() == "narrator"
            let kind: TTSSegmentKind = isNarration ? .narration : .dialogue
            let deliveryStyle = assignment.deliveryStyle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDeliveryStyle = deliveryStyle.flatMap {
                $0.isEmpty ? nil : String($0.prefix(80))
            }
            let requestedPause = assignment.pauseAfterMilliseconds
                ?? suggestedPauseAfterMilliseconds(for: unit.text, kind: kind)
            return TTSSegment(
                index: unit.index,
                kind: kind,
                roleID: roleID,
                speakerName: speaker.isEmpty ? "旁白" : speaker,
                sourceText: unit.text,
                sourceStart: unit.sourceStart,
                sourceEnd: unit.sourceEnd,
                confidence: assignment.confidence ?? 0.5,
                deliveryStyle: normalizedDeliveryStyle,
                pauseAfterMilliseconds: min(max(requestedPause, 150), 2_000)
            )
        }
        return TTSScriptAnalysis(voices: voices, segments: segments)
    }

    private static func isPlausibleRoleName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 24 else { return false }
        let narrativePunctuation = CharacterSet(charactersIn: "，。！？；：“”\"'")
        return !value.unicodeScalars.contains { narrativePunctuation.contains($0) }
    }

    public static func suggestedPauseAfterMilliseconds(
        for text: String,
        kind: TTSSegmentKind
    ) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ending = trimmed.last else { return 320 }
        if "！？!?".contains(ending) { return 520 }
        if "。.".contains(ending) { return kind == .narration ? 460 : 400 }
        if "；;".contains(ending) { return 360 }
        if "，,".contains(ending) { return 260 }
        return kind == .narration ? 380 : 320
    }

    public static func synthesisChunks(_ source: String, maximumCharacters: Int) -> [String] {
        let limit = max(20, maximumCharacters)
        var result: [String] = []
        var current = ""
        for character in source {
            current.append(character)
            let isBoundary = "。！？!?；;\n".contains(character)
            if current.count >= limit || (isBoundary && current.count >= 24) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
        }
        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty { result.append(trailing) }
        return result
    }

    public static func synthesisReadyAnalysis(
        _ analysis: TTSScriptAnalysis,
        maximumCharacters: Int = 240
    ) -> TTSScriptAnalysis {
        var result: [TTSSegment] = []
        // 仅含引号或标点的伪片段没有可朗读内容，不能进入生成队列。
        let segments = analysis.segments
            .sorted(by: { $0.index < $1.index })
            .filter { hasSpokenContent($0.sourceText) }
        for (segmentIndex, segment) in segments.enumerated() {
            let chunks = synthesisChunks(segment.sourceText, maximumCharacters: maximumCharacters)
                .filter(hasSpokenContent)
            guard !chunks.isEmpty else { continue }
            let next = segments.indices.contains(segmentIndex + 1) ? segments[segmentIndex + 1] : nil
            let speakerChanges = next?.speakerName != nil
                && segment.speakerName != nil
                && next?.speakerName != segment.speakerName
            let naturalPause = max(
                suggestedPauseAfterMilliseconds(for: segment.sourceText, kind: segment.kind),
                speakerChanges ? 520 : 0
            )
            let finalPause = max(segment.pauseAfterMilliseconds, naturalPause)
            guard chunks.count > 1 else {
                var unchanged = segment
                unchanged.index = result.count
                unchanged.pauseAfterMilliseconds = finalPause
                result.append(unchanged)
                continue
            }
            var localCursor = segment.sourceText.startIndex
            for (chunkIndex, chunk) in chunks.enumerated() {
                let located = segment.sourceText.range(
                    of: chunk,
                    range: localCursor..<segment.sourceText.endIndex
                )
                let localStart = located.map {
                    segment.sourceText.distance(from: segment.sourceText.startIndex, to: $0.lowerBound)
                }
                if let located { localCursor = located.upperBound }
                result.append(TTSSegment(
                    index: result.count,
                    kind: segment.kind,
                    roleID: segment.roleID,
                    speakerName: segment.speakerName,
                    sourceText: chunk,
                    sourceStart: localStart.flatMap { local in segment.sourceStart.map { $0 + local } },
                    sourceEnd: localStart.flatMap { local in segment.sourceStart.map { $0 + local + chunk.count } },
                    confidence: segment.confidence,
                    deliveryStyle: segment.deliveryStyle,
                    pauseAfterMilliseconds: chunkIndex == chunks.count - 1 ? finalPause : 180
                ))
            }
        }
        return TTSScriptAnalysis(voices: analysis.voices, segments: result)
    }

    private static func hasSpokenContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func extractedJSONObject(from raw: String) throws -> Data {
        guard let start = raw.firstIndex(of: "{") else {
            throw TTSError.invalidScript("本地模型没有返回 JSON。")
        }

        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var completedEnd: String.Index?
        for index in raw[start...].indices {
            let character = raw[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }
            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                guard depth >= 0 else {
                    throw TTSError.invalidScript("本地模型没有返回有效的 JSON。")
                }
                if depth == 0 {
                    completedEnd = index
                    break
                }
            }
        }

        if let completedEnd {
            return Data(raw[start...completedEnd].utf8)
        }
        guard !isInsideString, (1...2).contains(depth) else {
            throw TTSError.invalidScript("本地模型没有返回完整的 JSON。")
        }

        // 小模型偶尔只漏掉最外层右花括号；仅补尾部花括号，数组、字符串等仍交给 JSONDecoder 严格校验。
        var repaired = String(raw[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if repaired.hasSuffix("```") {
            repaired.removeLast(3)
            repaired = repaired.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        repaired.append(String(repeating: "}", count: depth))
        return Data(repaired.utf8)
    }
}

public final class TTSProjectStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL = AppPaths.ttsProjectsDirectory) {
        self.rootDirectory = rootDirectory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ project: TTSProject) throws {
        let directory = projectDirectory(for: project.id)
        let fileURL = directory.appendingPathComponent("project.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            var updated = project
            updated.updatedAt = .now
            try encoder.encode(updated).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw TTSError.projectStorageFailed(error.localizedDescription)
        }
    }

    public func loadMostRecent() throws -> TTSProject? {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return nil }
        let projects = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).compactMap { directory -> TTSProject? in
            let fileURL = directory.appendingPathComponent("project.json")
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? decoder.decode(TTSProject.self, from: data)
        }
        return projects.max { $0.updatedAt < $1.updatedAt }
    }

    public func projectDirectory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func audioDirectory(for id: UUID) throws -> URL {
        let directory = projectDirectory(for: id).appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory
    }

    public func resolve(relativePath: String, projectID: UUID) -> URL {
        projectDirectory(for: projectID).appendingPathComponent(relativePath)
    }

    public func relativePath(for fileURL: URL, projectID: UUID) -> String {
        let root = projectDirectory(for: projectID).standardizedFileURL.path
        let path = fileURL.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return fileURL.lastPathComponent }
        return String(path.dropFirst(root.count + 1))
    }
}

public enum TTSAudioExporter {
    @discardableResult
    public static func composeWAV(project: TTSProject, store: TTSProjectStore, outputURL: URL) throws -> TimeInterval {
        var pcm = Data()
        var sampleRate: Int?
        var duration: TimeInterval = 0
        for segment in project.segments.sorted(by: { $0.index < $1.index }) {
            guard segment.generationState == .completed,
                  let relativePath = segment.audioRelativePath else { continue }
            let buffer = try LiveMeetingAudioStorage.readPCM16WAV(
                at: store.resolve(relativePath: relativePath, projectID: project.id)
            )
            if let sampleRate, sampleRate != buffer.sampleRate {
                throw TTSError.exportFailed("生成片段采样率不一致。")
            }
            sampleRate = buffer.sampleRate
            pcm.append(buffer.data)
            duration += Double(buffer.data.count) / Double(buffer.sampleRate * 2)
            let pauseSamples = buffer.sampleRate * segment.pauseAfterMilliseconds / 1_000
            pcm.append(Data(repeating: 0, count: pauseSamples * 2))
            duration += Double(segment.pauseAfterMilliseconds) / 1_000
        }
        guard let sampleRate, !pcm.isEmpty else { throw TTSError.exportFailed("没有已完成的音频片段。") }
        try LiveMeetingAudioStorage.writePCM16WAV(data: pcm, sampleRate: sampleRate, to: outputURL)
        return duration
    }

    public static func convert(wavURL: URL, to outputURL: URL, format: TTSExportFormat) throws {
        guard format != .wav else {
            if wavURL.standardizedFileURL != outputURL.standardizedFileURL {
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.copyItem(at: wavURL, to: outputURL)
            }
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        switch format {
        case .wav:
            return
        case .m4a:
            process.arguments = [wavURL.path, outputURL.path, "-f", "m4af", "-d", "aac ", "-b", "192000"]
        }
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try? FileManager.default.removeItem(at: outputURL)
        do { try process.run() } catch { throw TTSError.exportFailed(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TTSError.exportFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
    }

    public static func srt(project: TTSProject) -> String {
        var cursor: TimeInterval = 0
        var lines: [String] = []
        let voices = Dictionary(uniqueKeysWithValues: project.voices.map { ($0.id, $0.name) })
        let completed = project.segments
            .filter { $0.generationState == .completed && $0.audioRelativePath != nil }
            .sorted(by: { $0.index < $1.index })
        for (outputIndex, segment) in completed.enumerated() {
            let duration = max(0.1, segment.duration ?? 0)
            let speaker = segment.speakerName ?? voices[segment.roleID] ?? "旁白"
            lines.append("\(outputIndex + 1)\n\(timestamp(cursor)) --> \(timestamp(cursor + duration))\n\(speaker)：\(segment.spokenText)\n")
            cursor += duration + Double(segment.pauseAfterMilliseconds) / 1_000
        }
        return lines.joined(separator: "\n")
    }

    private static func timestamp(_ value: TimeInterval) -> String {
        let milliseconds = max(0, Int((value * 1_000).rounded()))
        return String(
            format: "%02d:%02d:%02d,%03d",
            milliseconds / 3_600_000,
            (milliseconds / 60_000) % 60,
            (milliseconds / 1_000) % 60,
            milliseconds % 1_000
        )
    }
}
