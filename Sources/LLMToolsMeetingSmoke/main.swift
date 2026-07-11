import Foundation
import LLMToolsCore

@main
struct LLMToolsMeetingSmoke {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let inputIndex = arguments.firstIndex(of: "--input"), arguments.indices.contains(inputIndex + 1) else {
            throw SmokeError("Usage: LLMToolsMeetingSmoke --input /absolute/path/to/audio-or-video [--speech-model UUID] [--output-dir /absolute/path] [--generate-notes]")
        }
        let inputURL = URL(fileURLWithPath: arguments[inputIndex + 1])
        let requestedSpeechModelID = value(for: "--speech-model", arguments: arguments).flatMap(UUID.init(uuidString:))
        let generateNotes = arguments.contains("--generate-notes")
        let outputDirectory = value(for: "--output-dir", arguments: arguments).map(URL.init(fileURLWithPath:))
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let engine = TaskEngine()
        await engine.bootstrap()
        let snapshot = await engine.registry()
        let speechModelID = requestedSpeechModelID
            ?? snapshot.preferences.liveMeeting.fileASRModelID
            ?? snapshot.preferences.mediaSubtitles.fileASRModelID
        let fileResult = try await engine.transcribeMeetingFile(at: inputURL, modelID: speechModelID)
        guard let model = snapshot.models.first(where: { $0.id == speechModelID })
            ?? snapshot.models.first(where: { $0.enabled && $0.capabilities.supportsFileSpeech }) else {
            throw SmokeError("No local file ASR model is configured.")
        }
        let session = LiveMeetingSession(
            source: .localFile,
            sourceFileName: inputURL.lastPathComponent,
            sourceMediaKind: fileResult.descriptor.mediaKind == "video" ? .video : .audio,
            asrModelID: model.id,
            asrModelName: model.name,
            state: .stopped,
            diarizationRuntimeID: fileResult.diarizationModelID,
            recognitionStrategy: fileResult.recognitionStrategy
        )
        var speakers: [LiveMeetingSpeaker] = []
        for segment in fileResult.segments {
            guard let id = segment.speakerID, !speakers.contains(where: { $0.id == id }) else { continue }
            speakers.append(LiveMeetingSpeaker(id: id, label: segment.speakerLabel ?? "Speaker \(speakers.count + 1)"))
        }
        let segments = LiveMeetingTranscriptReducer.collapseAdjacentSpeakerSegments(
            fileResult.segments,
            speakers: speakers
        )
        let notes: MeetingNoteState?
        if generateNotes {
            let generated = try await engine.generateLocalMeetingNotes(segments: segments, speakers: speakers)
            guard generated.hasContent else {
                throw SmokeError("Local meeting-notes model returned no usable Chinese notes.")
            }
            notes = generated
        } else {
            notes = nil
        }
        let markdown = LiveMeetingMarkdownExporter.markdown(session: session, segments: segments, speakers: speakers, notes: notes)
        let outputURL = outputDirectory
            .appendingPathComponent(LiveMeetingMarkdownExporter.baseFileName(session: session))
            .appendingPathExtension("md")
        try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
        print("Meeting smoke passed")
        print("segments=\(segments.count) speakers=\(speakers.count) asr=\(fileResult.asrRuntimeSource.rawValue) strategy=\(fileResult.recognitionStrategy.rawValue) diarization=\(fileResult.diarizationModelID ?? "none") notes=\(notes?.hasContent == true ? "local" : "not-requested")")
        print("export=\(outputURL.path)")
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
