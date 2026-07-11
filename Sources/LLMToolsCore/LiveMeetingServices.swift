import Foundation
import Darwin

public enum LiveMeetingError: Error, LocalizedError, Sendable {
    case missingLocalTextModel
    case remoteTextModelForbidden
    case sessionIsRunning
    case sessionNotStopped
    case invalidExportDirectory
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingLocalTextModel: return "Generate Notes requires an enabled local text model. Add or enable a local GGUF or MLX text model in Settings."
        case .remoteTextModelForbidden: return "Meeting notes are local-only. Select a local GGUF or MLX text model, not a remote provider."
        case .sessionIsRunning: return "Stop the meeting before running this action."
        case .sessionNotStopped: return "This action is available after the meeting stops."
        case .invalidExportDirectory: return "The export directory is unavailable."
        case .cancelled: return "Meeting task cancelled."
        }
    }
}

/// Ordinary meeting ASR prefers a readable pause but keeps transcript latency bounded.
public enum LiveMeetingTurnSegmentationPolicy {
    public static let minimumSpeechMilliseconds = 200
    public static let pauseMilliseconds = 1_200
    public static let preferredBatchMilliseconds = 20_000
    public static let postTargetPauseMilliseconds = 400
    public static let maximumContinuousSpeechMilliseconds = 30_000

    public static func shouldFlush(
        speechMilliseconds: Int,
        trailingSilenceMilliseconds: Int
    ) -> Bool {
        let speech = max(0, speechMilliseconds)
        let silence = max(0, trailingSilenceMilliseconds)
        return (speech >= minimumSpeechMilliseconds && silence >= pauseMilliseconds)
            || (speech >= preferredBatchMilliseconds && silence >= postTargetPauseMilliseconds)
            || speech >= maximumContinuousSpeechMilliseconds
    }
}

/// Ordinary live ASR must not wait for pyannote. Transcript batches close on a
/// natural pause, while speaker labels are refreshed against an older stable prefix.
public enum LiveMeetingDelayedSpeakerPolicy {
    public static let speakerStabilizationMilliseconds = 30_000
    public static let diarizationRefreshMilliseconds = 30_000
    public static let minimumStableAdvanceMilliseconds = 30_000
    public static let minimumFinalAdvanceMilliseconds = 200

    public static func shouldFlushTranscript(
        speechMilliseconds: Int,
        trailingSilenceMilliseconds: Int
    ) -> Bool {
        LiveMeetingTurnSegmentationPolicy.shouldFlush(
            speechMilliseconds: speechMilliseconds,
            trailingSilenceMilliseconds: trailingSilenceMilliseconds
        )
    }

    public static func stableThroughMilliseconds(
        capturedMilliseconds: Int,
        final: Bool
    ) -> Int {
        let captured = max(0, capturedMilliseconds)
        return final ? captured : max(0, captured - speakerStabilizationMilliseconds)
    }

    public static func shouldRefreshSpeakerLabels(
        capturedMilliseconds: Int,
        lastAttemptMilliseconds: Int,
        labeledThroughMilliseconds: Int,
        final: Bool = false
    ) -> Bool {
        let stableThrough = stableThroughMilliseconds(
            capturedMilliseconds: capturedMilliseconds,
            final: final
        )
        let stableAdvance = stableThrough - max(0, labeledThroughMilliseconds)
        if final {
            return stableAdvance >= minimumFinalAdvanceMilliseconds
        }
        return max(0, capturedMilliseconds - lastAttemptMilliseconds) >= diarizationRefreshMilliseconds
            && stableAdvance >= minimumStableAdvanceMilliseconds
    }
}

/// A preferred duration only arms a shorter natural-pause boundary. It must
/// never become a duration-only cut while speech is still continuous.
public enum LiveMeetingNativeBatchPolicy {
    public static let minimumSpeechMilliseconds = 200
    public static let clearInterruptionMilliseconds = 2_500
    public static let preferredBatchMilliseconds = 90 * 1_000
    public static let postTargetPauseMilliseconds = 800

    public static func shouldFlush(
        speechMilliseconds: Int,
        trailingSilenceMilliseconds: Int,
        batchDurationMilliseconds: Int
    ) -> Bool {
        let speech = max(0, speechMilliseconds)
        let silence = max(0, trailingSilenceMilliseconds)
        let duration = max(0, batchDurationMilliseconds)
        guard speech >= minimumSpeechMilliseconds else { return false }
        return silence >= clearInterruptionMilliseconds
            || (duration >= preferredBatchMilliseconds && silence >= postTargetPauseMilliseconds)
    }

    public static func shouldDiscardNoise(
        speechMilliseconds: Int,
        trailingSilenceMilliseconds: Int
    ) -> Bool {
        let speech = max(0, speechMilliseconds)
        guard speech > 0, speech < minimumSpeechMilliseconds else { return false }
        return max(0, trailingSilenceMilliseconds) >= clearInterruptionMilliseconds
    }
}

/// Native speaker ASR keeps natural pauses as the logical turn boundary, while
/// sealing bounded technical windows so one local inference cannot grow forever.
public enum LiveMeetingNativeTechnicalWindowPolicy {
    public static let maximumInferenceWindowMilliseconds = 120 * 1_000

    public static func shouldSeal(sourceDurationMilliseconds: Int) -> Bool {
        max(0, sourceDurationMilliseconds) >= maximumInferenceWindowMilliseconds
    }
}

public enum LiveMeetingASRBackpressurePolicy {
    public static let maximumQueuedBatches = 2

    public static func shouldStopCapture(pendingBatchCount: Int) -> Bool {
        max(0, pendingBatchCount) >= maximumQueuedBatches
    }
}

public enum LiveMeetingSpeakerTurnPlanner {
    public static let minimumTurnDuration: TimeInterval = 0.20
    public static let maximumASRTurnDuration: TimeInterval = 120
    public static let adjacentMergeGap: TimeInterval = 1.20
    public static let minimumPrimarySpeakerShare = 0.60

    public static func plan(
        turns: [SpeakerTurn],
        processedThrough: TimeInterval,
        stableThrough: TimeInterval,
        maximumTurnDuration: TimeInterval = maximumASRTurnDuration
    ) -> [LiveMeetingSpeakerAudioSlice] {
        let lowerBound = max(0, processedThrough)
        let upperBound = max(lowerBound, stableThrough)
        guard upperBound - lowerBound >= minimumTurnDuration else { return [] }

        let candidates = turns.compactMap { turn -> Candidate? in
            let start = max(lowerBound, turn.startTime)
            let end = min(upperBound, turn.endTime)
            guard end - start >= 0.01 else { return nil }
            return Candidate(turn: turn, startTime: start, endTime: end)
        }
        guard !candidates.isEmpty else { return [] }

        let boundaries = Array(Set(
            [lowerBound, upperBound] + candidates.flatMap { [$0.startTime, $0.endTime] }
        )).sorted()
        var atomic: [LiveMeetingSpeakerAudioSlice] = []
        for index in boundaries.indices.dropLast() {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end - start >= 0.01 else { continue }
            let active = candidates.filter { $0.startTime < end && $0.endTime > start }
            guard !active.isEmpty else { continue }

            let grouped = Dictionary(grouping: active, by: { $0.turn.speakerID })
            let ranked = grouped.map { speakerID, group -> RankedSpeaker in
                let evidence = group.map { $0.endTime - $0.startTime }.max() ?? 0
                let label = group.compactMap(\.turn.speakerLabel).first
                let confidence = group.compactMap(\.turn.confidence).min()
                return RankedSpeaker(
                    speakerID: speakerID,
                    speakerLabel: label,
                    evidence: evidence,
                    confidence: confidence
                )
            }.sorted { lhs, rhs in
                if lhs.evidence == rhs.evidence { return lhs.speakerID < rhs.speakerID }
                return lhs.evidence > rhs.evidence
            }
            guard let primary = ranked.first else { continue }
            let totalEvidence = ranked.reduce(0) { $0 + $1.evidence }
            let primaryShare = primary.evidence / max(totalEvidence, 0.001)
            let explicitLowConfidence = primary.confidence.map { $0 < 0.55 } ?? false
            let ambiguousOverlap = ranked.count > 1 && primaryShare < minimumPrimarySpeakerShare
            atomic.append(LiveMeetingSpeakerAudioSlice(
                startTime: start,
                endTime: end,
                speakerID: ambiguousOverlap ? nil : primary.speakerID,
                speakerLabel: ambiguousOverlap ? "Unknown" : primary.speakerLabel,
                confidence: primary.confidence ?? primaryShare,
                isLowConfidence: explicitLowConfidence || ambiguousOverlap
            ))
        }

        let merged = mergeAdjacent(atomic)
        return merged.flatMap { split($0, maximumDuration: max(minimumTurnDuration, maximumTurnDuration)) }
            .filter { $0.endTime - $0.startTime >= minimumTurnDuration }
    }

    private static func mergeAdjacent(
        _ slices: [LiveMeetingSpeakerAudioSlice]
    ) -> [LiveMeetingSpeakerAudioSlice] {
        var result: [LiveMeetingSpeakerAudioSlice] = []
        for slice in slices {
            if let previousIndex = result.indices.last,
               result[previousIndex].speakerID == slice.speakerID,
               result[previousIndex].speakerLabel == slice.speakerLabel,
               result[previousIndex].isLowConfidence == slice.isLowConfidence,
               slice.startTime - result[previousIndex].endTime <= adjacentMergeGap {
                result[previousIndex].endTime = slice.endTime
                result[previousIndex].confidence = minConfidence(
                    result[previousIndex].confidence,
                    slice.confidence
                )
            } else {
                result.append(slice)
            }
        }
        return result
    }

    private static func split(
        _ slice: LiveMeetingSpeakerAudioSlice,
        maximumDuration: TimeInterval
    ) -> [LiveMeetingSpeakerAudioSlice] {
        var result: [LiveMeetingSpeakerAudioSlice] = []
        var start = slice.startTime
        while slice.endTime - start > maximumDuration {
            var part = slice
            part.startTime = start
            part.endTime = start + maximumDuration
            result.append(part)
            start += maximumDuration
        }
        if slice.endTime > start {
            var part = slice
            part.startTime = start
            result.append(part)
        }
        return result
    }

    private static func minConfidence(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)): return min(left, right)
        case let (.some(value), .none), let (.none, .some(value)): return value
        case (.none, .none): return nil
        }
    }

    private struct Candidate {
        var turn: SpeakerTurn
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    private struct RankedSpeaker {
        var speakerID: String
        var speakerLabel: String?
        var evidence: TimeInterval
        var confidence: Double?
    }
}

public enum LiveMeetingTranscriptReducer {
    private static let minimumPrimarySpeakerShare = 0.60
    private static let minimumSpeakerEvidenceSeconds: TimeInterval = 0.20
    private static let maximumReadableTurnCharacters = 12_000

    public static func append(
        _ incoming: [LiveMeetingSegment],
        to existing: [LiveMeetingSegment]
    ) -> [LiveMeetingSegment] {
        var result = existing
        for var segment in incoming where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segment.index = result.count
            result.append(segment)
        }
        return result
    }

    /// One diarized speaker slice is one meeting row. ASR runtimes may emit
    /// sentence-sized technical segments inside that slice, but exposing those
    /// segments would recreate subtitle-style fragmentation in the meeting UI.
    public static func groupSpeakerSlice(
        _ segments: [LiveMeetingSegment],
        slice: LiveMeetingSpeakerAudioSlice,
        index: Int
    ) -> LiveMeetingSegment? {
        let usable = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = usable.first else { return nil }
        let text = usable.map(\.text).joined(separator: " ")
        let originalText = usable.map(\.originalText).joined(separator: " ")
        return LiveMeetingSegment(
            id: first.id,
            index: index,
            startTime: slice.startTime,
            endTime: slice.endTime,
            text: text,
            originalText: originalText,
            speakerID: slice.speakerID,
            speakerLabel: slice.speakerLabel,
            confidence: slice.confidence,
            state: slice.isLowConfidence ? .lowConfidence : .final
        )
    }

    /// Collapse only contiguous, already speaker-confirmed technical slices.
    /// Natural pauses stay as paragraph breaks because meeting capture omits the
    /// trailing silence from the preceding ASR request.
    public static func collapseAdjacentSpeakerSegments(
        _ segments: [LiveMeetingSegment],
        speakers: [LiveMeetingSpeaker],
        collapseThrough: TimeInterval? = nil
    ) -> [LiveMeetingSegment] {
        var collapsed: [LiveMeetingSegment] = []
        for segment in segments where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var normalized = segment
            if let speakerID = normalized.speakerID,
               let resolved = resolvedSpeaker(speakerID, speakers: speakers) {
                normalized.speakerID = resolved.id
                normalized.speakerLabel = resolved.renderedName
            }
            if let previousIndex = collapsed.indices.last,
               canCollapseSpeakerSegments(
                   collapsed[previousIndex],
                   normalized,
                   collapseThrough: collapseThrough
               ) {
                collapsed[previousIndex].endTime = normalized.endTime
                collapsed[previousIndex].text = join(collapsed[previousIndex].text, normalized.text)
                collapsed[previousIndex].originalText = join(collapsed[previousIndex].originalText, normalized.originalText)
                collapsed[previousIndex].confidence = minConfidence(
                    collapsed[previousIndex].confidence,
                    normalized.confidence
                )
                collapsed[previousIndex].includedInNotes = collapsed[previousIndex].includedInNotes || normalized.includedInNotes
                continue
            }
            collapsed.append(normalized)
        }
        for index in collapsed.indices { collapsed[index].index = index }
        return collapsed
    }

    public static func editText(
        id: UUID,
        text: String,
        segments: inout [LiveMeetingSegment]
    ) -> Bool {
        guard let index = segments.firstIndex(where: { $0.id == id }), segments[index].state != .partial else {
            return false
        }
        segments[index].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        segments[index].userEditedText = true
        segments[index].textEditedAt = .now
        return true
    }

    public static func applySpeakerTurns(
        _ turns: [SpeakerTurn],
        to segments: inout [LiveMeetingSegment],
        speakers: inout [LiveMeetingSpeaker],
        confidenceThreshold: Double = 0.55,
        through: TimeInterval? = nil
    ) {
        for index in segments.indices {
            let segment = segments[index]
            guard !segment.userEditedSpeaker else { continue }
            let end = max(segment.endTime ?? segment.startTime, segment.startTime)
            if let through, end > through { continue }
            let segmentDuration = max(0.001, end - segment.startTime)
            var overlaps: [SpeakerTurnOverlap] = []
            for turn in turns {
                let overlapStart = max(segment.startTime, turn.startTime)
                let overlapEnd = min(end, turn.endTime)
                guard overlapEnd > overlapStart else { continue }
                let speaker = ensureSpeaker(
                    id: turn.speakerID,
                    suggestedLabel: turn.speakerLabel,
                    speakers: &speakers
                )
                guard let resolved = resolvedSpeaker(speaker.id, speakers: speakers) else { continue }
                overlaps.append(SpeakerTurnOverlap(
                    turn: turn,
                    startTime: overlapStart,
                    endTime: overlapEnd,
                    resolvedSpeakerID: resolved.id,
                    resolvedSpeakerLabel: resolved.renderedName
                ))
            }
            guard !overlaps.isEmpty else {
                continue
            }

            let candidatesBySpeaker = Dictionary(grouping: overlaps, by: \.resolvedSpeakerID)
            let coverageBySpeaker = candidatesBySpeaker.mapValues { candidates in
                unionDuration(candidates.map { ($0.startTime, $0.endTime) })
            }
            guard let primary = coverageBySpeaker.sorted(by: { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }).first,
            let primaryCandidates = candidatesBySpeaker[primary.key] else {
                continue
            }

            let coveredDuration = unionDuration(overlaps.map { ($0.startTime, $0.endTime) })
            let totalSpeakerEvidence = coverageBySpeaker.values.reduce(0, +)
            let primaryShare = primary.value / max(totalSpeakerEvidence, 0.001)
            let coverageShare = coveredDuration / segmentDuration
            let minimumEvidence = min(
                minimumSpeakerEvidenceSeconds,
                max(0.05, segmentDuration * 0.25)
            )
            let runtimeConfidence = primaryCandidates.compactMap(\.turn.confidence).min()
            let hasLowRuntimeConfidence = runtimeConfidence.map { $0 < confidenceThreshold } ?? false
            let hasMaterialOverlap = hasMaterialDifferentSpeakerOverlap(
                overlaps,
                segmentDuration: segmentDuration
            )
            let hasAmbiguousPrimary = primary.value < minimumEvidence
                || coverageShare < 0.35
                || (hasMaterialOverlap && primaryShare < minimumPrimarySpeakerShare)
            if hasLowRuntimeConfidence || hasAmbiguousPrimary {
                segments[index].speakerID = nil
                segments[index].speakerLabel = "Unknown"
                segments[index].confidence = runtimeConfidence ?? primaryShare
                segments[index].state = .lowConfidence
                continue
            }
            segments[index].speakerID = primary.key
            segments[index].speakerLabel = primaryCandidates.first?.resolvedSpeakerLabel
            segments[index].confidence = runtimeConfidence ?? primaryShare
            segments[index].state = .final
        }
    }

    @discardableResult
    public static func renameSpeaker(id: String, name: String, speakers: inout [LiveMeetingSpeaker]) -> Bool {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return false }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speakers[index].displayName = value.isEmpty ? nil : value
        speakers[index].userEdited = true
        return true
    }

    @discardableResult
    public static func mergeSpeaker(
        sourceID: String,
        into targetID: String,
        speakers: inout [LiveMeetingSpeaker],
        segments: inout [LiveMeetingSegment]
    ) -> Bool {
        guard sourceID != targetID,
              let sourceIndex = speakers.firstIndex(where: { $0.id == sourceID }),
              let target = speakers.first(where: { $0.id == targetID }) else {
            return false
        }
        speakers[sourceIndex].mergedIntoSpeakerID = target.id
        speakers[sourceIndex].userEdited = true
        for index in segments.indices where segments[index].speakerID == sourceID && !segments[index].userEditedSpeaker {
            segments[index].speakerID = target.id
            segments[index].speakerLabel = target.renderedName
        }
        return true
    }

    public static func finalize(
        _ segments: [LiveMeetingSegment],
        speakers: [LiveMeetingSpeaker]
    ) -> [LiveMeetingSegment] {
        var cleaned: [LiveMeetingSegment] = []
        for segment in segments {
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var normalized = segment
            normalized.state = .final
            if let speakerID = normalized.speakerID,
               let resolved = resolvedSpeaker(speakerID, speakers: speakers) {
                normalized.speakerID = resolved.id
                normalized.speakerLabel = resolved.renderedName
            }
            if let previousIndex = cleaned.indices.last,
               canMerge(cleaned[previousIndex], normalized) {
                cleaned[previousIndex].endTime = normalized.endTime
                if !cleaned[previousIndex].userEditedText && !normalized.userEditedText {
                    cleaned[previousIndex].text = join(cleaned[previousIndex].text, normalized.text)
                    cleaned[previousIndex].originalText = join(cleaned[previousIndex].originalText, normalized.originalText)
                }
                continue
            }
            cleaned.append(normalized)
        }
        return collapseAdjacentSpeakerSegments(cleaned, speakers: speakers)
    }

    public static func markNotesStale(_ noteState: inout MeetingNoteState?, reason: String) {
        guard var current = noteState, current.hasContent else { return }
        current.isStale = true
        current.staleReason = reason
        current.generationState = .completed
        noteState = current
    }

    private static func ensureSpeaker(
        id: String,
        suggestedLabel: String?,
        speakers: inout [LiveMeetingSpeaker]
    ) -> LiveMeetingSpeaker {
        if let existing = speakers.first(where: { $0.id == id }) { return existing }
        let number = speakers.filter { $0.mergedIntoSpeakerID == nil }.count + 1
        let new = LiveMeetingSpeaker(
            id: id,
            label: nonBlank(suggestedLabel) ?? "Speaker \(number)",
            colorKey: ["blue", "green", "orange", "pink", "purple"][number % 5]
        )
        speakers.append(new)
        return new
    }

    private static func resolvedSpeaker(_ id: String, speakers: [LiveMeetingSpeaker]) -> LiveMeetingSpeaker? {
        var current = speakers.first(where: { $0.id == id })
        var visited = Set<String>()
        while let targetID = current?.mergedIntoSpeakerID, !visited.contains(targetID) {
            visited.insert(targetID)
            current = speakers.first(where: { $0.id == targetID }) ?? current
        }
        return current
    }

    private static func canMerge(_ lhs: LiveMeetingSegment, _ rhs: LiveMeetingSegment) -> Bool {
        guard lhs.state == .final, rhs.state == .final,
              let lhsSpeakerID = lhs.speakerID,
              lhsSpeakerID == rhs.speakerID,
              !lhs.userEditedText, !rhs.userEditedText,
              lhs.text != rhs.text else { return false }
        let lhsEnd = lhs.endTime ?? lhs.startTime
        let containsShortTurn = min(lhs.text.count, rhs.text.count) <= 80
        return rhs.startTime - lhsEnd <= 0.8
            && containsShortTurn
            && (lhs.text.count + rhs.text.count) <= 1_200
    }

    private static func canCollapseSpeakerSegments(
        _ lhs: LiveMeetingSegment,
        _ rhs: LiveMeetingSegment,
        collapseThrough: TimeInterval?
    ) -> Bool {
        guard lhs.state == .final,
              rhs.state == .final,
              let lhsSpeakerID = lhs.speakerID,
              lhsSpeakerID == rhs.speakerID,
              !lhs.userEditedSpeaker,
              !rhs.userEditedSpeaker,
              !lhs.userEditedText,
              !rhs.userEditedText,
              (lhs.text.count + rhs.text.count) <= maximumReadableTurnCharacters else {
            return false
        }
        let lhsEnd = lhs.endTime ?? lhs.startTime
        let rhsEnd = rhs.endTime ?? rhs.startTime
        if let collapseThrough,
           lhsEnd > collapseThrough || rhsEnd > collapseThrough {
            return false
        }
        return rhs.startTime - lhsEnd <= 0.35
    }

    private static func unionDuration(_ intervals: [(TimeInterval, TimeInterval)]) -> TimeInterval {
        let ordered = intervals
            .filter { $0.1 > $0.0 }
            .sorted { lhs, rhs in
                if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
        guard var current = ordered.first else { return 0 }
        var total: TimeInterval = 0
        for interval in ordered.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1 - current.0
                current = interval
            }
        }
        return total + current.1 - current.0
    }

    private static func hasMaterialDifferentSpeakerOverlap(
        _ overlaps: [SpeakerTurnOverlap],
        segmentDuration: TimeInterval
    ) -> Bool {
        let minimumOverlap = max(0.25, segmentDuration * 0.15)
        for lhsIndex in overlaps.indices {
            let lhs = overlaps[lhsIndex]
            for rhsIndex in overlaps.indices where rhsIndex > lhsIndex {
                let rhs = overlaps[rhsIndex]
                guard lhs.resolvedSpeakerID != rhs.resolvedSpeakerID else { continue }
                let overlap = max(0, min(lhs.endTime, rhs.endTime) - max(lhs.startTime, rhs.startTime))
                if overlap >= minimumOverlap {
                    return true
                }
            }
        }
        return false
    }

    private static func minConfidence(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)): return min(left, right)
        case let (.some(value), .none), let (.none, .some(value)): return value
        case (.none, .none): return nil
        }
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        let separator = lhs.hasSuffix("。") || lhs.hasSuffix(".") ? " " : " "
        return lhs + separator + rhs
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct SpeakerTurnOverlap {
        var turn: SpeakerTurn
        var startTime: TimeInterval
        var endTime: TimeInterval
        var resolvedSpeakerID: String
        var resolvedSpeakerLabel: String
    }
}

public enum LiveMeetingMarkdownExporter {
    public static func baseFileName(session: LiveMeetingSession, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: date)
        if session.source == .localFile,
           let name = session.sourceFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "\(URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent)-meeting-notes-\(stamp)"
        }
        return "meeting-notes-\(stamp)"
    }

    public static func markdown(
        session: LiveMeetingSession,
        segments: [LiveMeetingSegment],
        speakers: [LiveMeetingSpeaker],
        notes: MeetingNoteState?
    ) -> String {
        let speakerNames = speakers.filter { $0.mergedIntoSpeakerID == nil }.map(\.renderedName).joined(separator: ", ")
        let metadataDate = ISO8601DateFormatter().string(from: session.startedAt)
        let source: String
        switch session.source {
        case .microphone:
            source = "麦克风"
        case .systemAudio:
            source = "系统音频"
        case .localFile:
            source = "本地\(session.sourceMediaKind == .video ? "视频" : "音频")文件"
        }
        var lines = [
            "# 会议纪要",
            "",
            "## 元信息",
            "- 时间：\(metadataDate)",
            "- 来源：\(source)",
            "- ASR 模型：\(session.asrModelName)",
            "- 讲话人：\(speakerNames.isEmpty ? "Unknown" : speakerNames)",
            "",
            "## 摘要",
            nonBlank(notes?.summary) ?? "待生成",
            "",
            "## 关键决策"
        ]
        appendList(notes?.decisions ?? [], empty: "- 暂无", to: &lines)
        lines += ["", "## 待办事项"]
        appendActionList(notes?.actionItems ?? [], to: &lines)
        lines += ["", "## 开放问题"]
        appendList(notes?.openQuestions ?? [], empty: "- 暂无", to: &lines)
        lines += ["", "## 讨论主题"]
        appendList(notes?.topics ?? [], empty: "- 暂无", to: &lines)
        lines += ["", "## 完整转写"]
        for segment in segments {
            let speaker = segment.speakerLabel ?? "Unknown"
            lines.append("\(timestamp(segment.startTime)) \(speaker): \(segment.text)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func plainText(
        session: LiveMeetingSession,
        segments: [LiveMeetingSegment],
        speakers: [LiveMeetingSpeaker],
        notes: MeetingNoteState?
    ) -> String {
        markdown(session: session, segments: segments, speakers: speakers, notes: notes)
    }

    public static func json(
        session: LiveMeetingSession,
        segments: [LiveMeetingSegment],
        speakers: [LiveMeetingSpeaker],
        notes: MeetingNoteState?
    ) throws -> Data {
        struct Export: Codable { var session: LiveMeetingSession; var segments: [LiveMeetingSegment]; var speakers: [LiveMeetingSpeaker]; var notes: MeetingNoteState? }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Export(session: session, segments: segments, speakers: speakers, notes: notes))
    }

    private static func appendList(_ values: [String], empty: String, to lines: inout [String]) {
        if values.isEmpty { lines.append(empty) } else { lines.append(contentsOf: values.map { "- \($0)" }) }
    }

    private static func appendActionList(_ values: [String], to lines: inout [String]) {
        if values.isEmpty { lines.append("- [ ] 负责人：未知 事项：暂无 截止：未知") }
        else { lines.append(contentsOf: values.map { "- [ ] 负责人：未知 事项：\($0) 截止：未知" }) }
    }

    private static func timestamp(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public final class LiveMeetingRecoveryStore: @unchecked Sendable {
    public let fileURL: URL
    public let temporaryAudioRootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL = AppPaths.liveMeetingRecoveryDraftFileURL,
        temporaryAudioRootURL: URL = AppPaths.liveMeetingTemporaryDirectory
    ) {
        self.fileURL = fileURL
        self.temporaryAudioRootURL = temporaryAudioRootURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ draft: LiveMeetingRecoveryDraft) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var sanitized = draft
        sanitized.session.temporaryAudioDirectory = nil
        try encoder.encode(sanitized).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func load() throws -> LiveMeetingRecoveryDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(LiveMeetingRecoveryDraft.self, from: Data(contentsOf: fileURL))
    }

    public func loadDiscardingTemporaryAudio(
        orphanCutoff: Date = Date(timeIntervalSinceNow: -(24 * 60 * 60))
    ) throws -> LiveMeetingRecoveryDraft? {
        let draft = try load()
        if let sessionID = draft?.session.id {
            _ = try? LiveMeetingAudioStorage.deleteTemporaryDirectoryIfAbandoned(
                sessionID: sessionID,
                rootDirectory: temporaryAudioRootURL
            )
        }
        try? LiveMeetingAudioStorage.deleteOrphanedTemporaryDirectories(
            olderThan: orphanCutoff,
            rootDirectory: temporaryAudioRootURL
        )
        return draft
    }

    public func delete() throws {
        let sessionID = try? load()?.session.id
        if let sessionID {
            _ = try LiveMeetingAudioStorage.deleteTemporaryDirectoryIfAbandoned(
                sessionID: sessionID,
                rootDirectory: temporaryAudioRootURL
            )
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

public enum LiveMeetingAudioStorage {
    private static let ownerMarkerFileName = ".owner.json"

    private struct OwnerMarker: Codable {
        var sessionID: UUID
        var processIdentifier: Int32
        var createdAt: Date
    }

    public struct PCM16Buffer: Sendable, Hashable {
        public var data: Data
        public var sampleRate: Int

        public init(data: Data, sampleRate: Int) {
            self.data = data
            self.sampleRate = max(1, sampleRate)
        }
    }

    public static func makeTemporaryDirectory(
        sessionID: UUID,
        rootDirectory: URL = AppPaths.liveMeetingTemporaryDirectory,
        ownerProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = rootDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let marker = OwnerMarker(
            sessionID: sessionID,
            processIdentifier: ownerProcessIdentifier,
            createdAt: .now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let markerURL = directory.appendingPathComponent(ownerMarkerFileName)
        try encoder.encode(marker).write(to: markerURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
        return directory
    }

    public static func writePCM16WAV(data: Data, sampleRate: Int = 16_000, to url: URL) throws {
        let safeSampleRate = max(sampleRate, 1)
        let dataSize = UInt32(min(data.count, Int(UInt32.max)))
        var wav = Data()
        wav.append(Data("RIFF".utf8))
        appendUInt32(36 + dataSize, to: &wav)
        wav.append(Data("WAVE".utf8))
        wav.append(Data("fmt ".utf8))
        appendUInt32(16, to: &wav)
        appendUInt16(1, to: &wav)
        appendUInt16(1, to: &wav)
        appendUInt32(UInt32(safeSampleRate), to: &wav)
        appendUInt32(UInt32(safeSampleRate * 2), to: &wav)
        appendUInt16(2, to: &wav)
        appendUInt16(16, to: &wav)
        wav.append(Data("data".utf8))
        appendUInt32(dataSize, to: &wav)
        wav.append(data.prefix(Int(dataSize)))
        try wav.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func readPCM16WAV(at url: URL) throws -> PCM16Buffer {
        let wav = try Data(contentsOf: url)
        guard wav.count >= 12,
              String(data: wav[0..<4], encoding: .ascii) == "RIFF",
              String(data: wav[8..<12], encoding: .ascii) == "WAVE" else {
            throw MediaSubtitleError.extractionFailed("Meeting audio is not a readable PCM WAV file.")
        }
        var offset = 12
        var sampleRate: Int?
        var isPCM16Mono = false
        var pcmData: Data?
        while offset + 8 <= wav.count {
            let chunkID = String(data: wav[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32(wav, offset: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = min(wav.count, payloadStart + chunkSize)
            guard payloadStart <= payloadEnd else { break }
            if chunkID == "fmt ", payloadEnd - payloadStart >= 16 {
                let format = readUInt16(wav, offset: payloadStart)
                let channels = readUInt16(wav, offset: payloadStart + 2)
                sampleRate = Int(readUInt32(wav, offset: payloadStart + 4))
                let bitsPerSample = readUInt16(wav, offset: payloadStart + 14)
                isPCM16Mono = format == 1 && channels == 1 && bitsPerSample == 16
            } else if chunkID == "data" {
                pcmData = Data(wav[payloadStart..<payloadEnd])
            }
            offset = payloadEnd + (chunkSize % 2)
        }
        guard isPCM16Mono, let sampleRate, sampleRate > 0, let pcmData else {
            throw MediaSubtitleError.extractionFailed("Meeting audio must be mono 16-bit PCM WAV.")
        }
        return PCM16Buffer(data: pcmData, sampleRate: sampleRate)
    }

    public static func slicePCM16(
        _ data: Data,
        sampleRate: Int = 16_000,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> Data {
        let safeSampleRate = max(1, sampleRate)
        let bytesPerSecond = safeSampleRate * 2
        let startByte = min(data.count, max(0, Int((max(0, startTime) * Double(bytesPerSecond)).rounded(.down))))
        let endByte = min(data.count, max(startByte, Int((max(startTime, endTime) * Double(bytesPerSecond)).rounded(.up))))
        let alignedStart = startByte - (startByte % 2)
        let alignedEnd = endByte - (endByte % 2)
        guard alignedEnd > alignedStart else { return Data() }
        return Data(data[alignedStart..<alignedEnd])
    }

    public static func deleteTemporaryDirectory(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path, isDirectory: true))
    }

    public static func deleteTemporaryDirectory(
        sessionID: UUID,
        rootDirectory: URL = AppPaths.liveMeetingTemporaryDirectory
    ) throws {
        let directory = rootDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    public static func deleteTemporaryDirectoryIfAbandoned(
        sessionID: UUID,
        rootDirectory: URL = AppPaths.liveMeetingTemporaryDirectory
    ) throws -> Bool {
        let directory = rootDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return true }
        if let marker = ownerMarker(in: directory), processIsRunning(marker.processIdentifier) {
            return false
        }
        try FileManager.default.removeItem(at: directory)
        return true
    }

    public static func deleteOrphanedTemporaryDirectories(
        olderThan cutoff: Date,
        rootDirectory: URL = AppPaths.liveMeetingTemporaryDirectory
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        let children = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants]
        )
        for directory in children {
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            if let marker = ownerMarker(in: directory) {
                guard !processIsRunning(marker.processIdentifier) else { continue }
                try fileManager.removeItem(at: directory)
                continue
            }
            let modifiedAt = try directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                ?? .distantFuture
            if modifiedAt < cutoff {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    private static func ownerMarker(in directory: URL) -> OwnerMarker? {
        let url = directory.appendingPathComponent(ownerMarkerFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OwnerMarker.self, from: data)
    }

    private static func processIsRunning(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else { return false }
        if kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
