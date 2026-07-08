@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit
import LLMToolsCore

private enum LiveSubtitleCaptureServiceError: LocalizedError {
    case noDisplayAvailable
    case microphoneDenied
    case microphoneUnavailable
    case systemAudioUnavailable(String)
    case audioConversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display is available for system audio capture."
        case .microphoneDenied:
            return "Microphone permission is required for microphone live subtitles."
        case .microphoneUnavailable:
            return "No microphone input is available."
        case .systemAudioUnavailable(let message):
            return "System audio capture is unavailable: \(message)"
        case .audioConversionFailed(let message):
            return "Audio conversion failed: \(message)"
        }
    }
}

final class LiveSubtitleCaptureService: NSObject, @unchecked Sendable {
    typealias ChunkHandler = @Sendable (Data) -> Void

    private let chunkHandler: ChunkHandler
    private let captureQueue = DispatchQueue(label: "llmtools.live-subtitles.screencapture")
    private let microphoneQueue = DispatchQueue(label: "llmtools.live-subtitles.microphone")
    private let conversionQueue = DispatchQueue(label: "llmtools.live-subtitles.audio-conversion")
    private let stateLock = NSLock()
    private let converter = LiveSubtitlePCM16Converter()

    private var stream: SCStream?
    private var streamOutput: ScreenCaptureAudioOutput?
    private var microphoneEngine: AVAudioEngine?
    private var microphoneSession: AVCaptureSession?
    private var microphoneOutput: MicrophoneCaptureAudioOutput?
    private var captureToken = UUID()
    private var isCapturing = false

    init(chunkHandler: @escaping ChunkHandler) {
        self.chunkHandler = chunkHandler
    }

    func start(source: LiveSubtitleAudioSource) async throws {
        await stop()
        let token = UUID()
        setCapturing(true, token: token)
        do {
            if source.includesSystemAudio {
                try await startSystemAudio(token: token)
            }
            if source.includesMicrophone {
                try await startMicrophone(token: token)
            }
        } catch {
            await stop()
            throw error
        }
    }

    func requestMicrophoneAccessIfNeeded() async throws {
        try await requestMicrophoneAccess()
    }

    func stop() async {
        setCapturing(false, token: UUID())
        if let microphoneEngine {
            microphoneEngine.inputNode.removeTap(onBus: 0)
            microphoneEngine.stop()
            self.microphoneEngine = nil
        }
        if let microphoneSession {
            microphoneSession.stopRunning()
            self.microphoneSession = nil
            self.microphoneOutput = nil
        }
        if let stream {
            await withCheckedContinuation { continuation in
                stream.stopCapture { _ in
                    continuation.resume()
                }
            }
            self.stream = nil
            self.streamOutput = nil
        }
    }

    func stopImmediately() {
        setCapturing(false, token: UUID())
        if let microphoneEngine {
            microphoneEngine.inputNode.removeTap(onBus: 0)
            microphoneEngine.stop()
            self.microphoneEngine = nil
        }
        if let microphoneSession {
            microphoneSession.stopRunning()
            self.microphoneSession = nil
            self.microphoneOutput = nil
        }
        stream?.stopCapture { _ in }
        stream = nil
        streamOutput = nil
    }

    private func startSystemAudio(token: UUID) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw LiveSubtitleCaptureServiceError.systemAudioUnavailable(error.localizedDescription)
        }
        guard let display = content.displays.first else {
            throw LiveSubtitleCaptureServiceError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(display.width, 2)
        configuration.height = max(display.height, 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1

        let output = ScreenCaptureAudioOutput { [weak self] sampleBuffer in
            self?.processSystemSampleBuffer(sampleBuffer, token: token)
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: captureQueue)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                stream.startCapture { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            throw LiveSubtitleCaptureServiceError.systemAudioUnavailable(error.localizedDescription)
        }

        self.stream = stream
        self.streamOutput = output
    }

    private func startMicrophone(token: UUID) async throws {
        try await requestMicrophoneAccess()

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw LiveSubtitleCaptureServiceError.microphoneUnavailable
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw LiveSubtitleCaptureServiceError.microphoneUnavailable
            }
            session.addInput(input)
        } catch let error as LiveSubtitleCaptureServiceError {
            throw error
        } catch {
            session.commitConfiguration()
            throw LiveSubtitleCaptureServiceError.microphoneUnavailable
        }

        let output = AVCaptureAudioDataOutput()
        let delegate = MicrophoneCaptureAudioOutput { [weak self] sampleBuffer in
            self?.processMicrophoneSampleBuffer(sampleBuffer, token: token)
        }
        output.setSampleBufferDelegate(delegate, queue: microphoneQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw LiveSubtitleCaptureServiceError.microphoneUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()

        self.microphoneSession = session
        self.microphoneOutput = delegate
        session.startRunning()
        guard session.isRunning else {
            self.microphoneSession = nil
            self.microphoneOutput = nil
            throw LiveSubtitleCaptureServiceError.microphoneUnavailable
        }
    }

    private func requestMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if granted {
                return
            }
            throw LiveSubtitleCaptureServiceError.microphoneDenied
        case .denied, .restricted:
            throw LiveSubtitleCaptureServiceError.microphoneDenied
        @unknown default:
            throw LiveSubtitleCaptureServiceError.microphoneDenied
        }
    }

    private func processSystemSampleBuffer(_ sampleBuffer: CMSampleBuffer, token: UUID) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else {
            return
        }

        do {
            let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            ) else {
                throw LiveSubtitleCaptureServiceError.audioConversionFailed("Could not allocate system audio buffer.")
            }
            buffer.frameLength = AVAudioFrameCount(frameCount)
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sampleBuffer,
                at: 0,
                frameCount: Int32(frameCount),
                into: buffer.mutableAudioBufferList
            )
            guard status == noErr else {
                throw LiveSubtitleCaptureServiceError.audioConversionFailed("CoreMedia status \(status).")
            }
            let data = try converter.convert(buffer)
            emit(data, token: token)
        } catch {
            return
        }
    }

    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer, token: UUID) {
        let bufferCopy: AVAudioPCMBuffer
        do {
            bufferCopy = try copyPCMBuffer(buffer)
        } catch {
            return
        }
        conversionQueue.async { [weak self] in
            guard let self else {
                return
            }
            do {
                let data = try self.converter.convert(bufferCopy)
                self.emit(data, token: token)
            } catch {
                return
            }
        }
    }

    private func processMicrophoneSampleBuffer(_ sampleBuffer: CMSampleBuffer, token: UUID) {
        processSystemSampleBuffer(sampleBuffer, token: token)
    }

    private func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.frameLength > 0 else {
            return buffer
        }
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameLength
        ) else {
            throw LiveSubtitleCaptureServiceError.audioConversionFailed("Could not allocate microphone buffer copy.")
        }
        copy.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let targetBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard !sourceBuffers.isEmpty, sourceBuffers.count <= targetBuffers.count else {
            throw LiveSubtitleCaptureServiceError.audioConversionFailed("Microphone buffer layout is invalid.")
        }

        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData,
                  let targetData = targetBuffers[index].mData else {
                throw LiveSubtitleCaptureServiceError.audioConversionFailed("Missing microphone audio data.")
            }
            let byteCount = min(sourceBuffers[index].mDataByteSize, targetBuffers[index].mDataByteSize)
            memcpy(targetData, sourceData, Int(byteCount))
            targetBuffers[index].mDataByteSize = byteCount
        }
        return copy
    }

    private func emit(_ data: Data, token: UUID) {
        guard !data.isEmpty, shouldEmit(token: token) else {
            return
        }
        chunkHandler(data)
    }

    private func setCapturing(_ isCapturing: Bool, token: UUID) {
        stateLock.lock()
        self.isCapturing = isCapturing
        captureToken = token
        stateLock.unlock()
    }

    private func shouldEmit(token: UUID) -> Bool {
        stateLock.lock()
        let result = isCapturing && captureToken == token
        stateLock.unlock()
        return result
    }
}

private final class ScreenCaptureAudioOutput: NSObject, SCStreamOutput {
    private let handler: @Sendable (CMSampleBuffer) -> Void

    init(handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else {
            return
        }
        handler(sampleBuffer)
    }
}

private final class MicrophoneCaptureAudioOutput: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let handler: @Sendable (CMSampleBuffer) -> Void

    init(handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handler(sampleBuffer)
    }
}

private final class LiveSubtitlePCM16Converter: @unchecked Sendable {
    private let targetSampleRate: Double = 16_000

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> Data {
        guard inputBuffer.frameLength > 0 else {
            return Data()
        }
        let sourceSampleRate = inputBuffer.format.sampleRate
        guard sourceSampleRate > 0 else {
            throw LiveSubtitleCaptureServiceError.audioConversionFailed("Invalid input sample rate.")
        }
        let monoSamples = try monoFloatSamples(from: inputBuffer)
        guard !monoSamples.isEmpty else {
            return Data()
        }

        let ratio = targetSampleRate / sourceSampleRate
        let outputFrameCount = max(1, Int(ceil(Double(monoSamples.count) * ratio)))
        var data = Data(capacity: outputFrameCount * MemoryLayout<Int16>.size)
        for outputIndex in 0..<outputFrameCount {
            let sourcePosition = Double(outputIndex) * sourceSampleRate / targetSampleRate
            let lowerIndex = min(Int(sourcePosition), monoSamples.count - 1)
            let upperIndex = min(lowerIndex + 1, monoSamples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            let sample = monoSamples[lowerIndex] + (monoSamples[upperIndex] - monoSamples[lowerIndex]) * fraction
            appendPCM16(sample, to: &data)
        }
        return data
    }

    private func monoFloatSamples(from inputBuffer: AVAudioPCMBuffer) throws -> [Float] {
        let frameCount = Int(inputBuffer.frameLength)
        let channelCount = Int(inputBuffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return []
        }

        switch inputBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            return try extractMonoSamples(from: inputBuffer, as: Float.self) { $0 }
        case .pcmFormatInt16:
            return try extractMonoSamples(from: inputBuffer, as: Int16.self) { Float($0) / 32_768 }
        case .pcmFormatInt32:
            return try extractMonoSamples(from: inputBuffer, as: Int32.self) { Float($0) / 2_147_483_648 }
        default:
            throw LiveSubtitleCaptureServiceError.audioConversionFailed(
                "Unsupported input PCM format: \(inputBuffer.format.commonFormat.rawValue)."
            )
        }
    }

    private func extractMonoSamples<T>(
        from inputBuffer: AVAudioPCMBuffer,
        as sampleType: T.Type,
        normalize: (T) -> Float
    ) throws -> [Float] {
        let frameCount = Int(inputBuffer.frameLength)
        let channelCount = Int(inputBuffer.format.channelCount)
        let buffers = UnsafeMutableAudioBufferListPointer(inputBuffer.mutableAudioBufferList)
        let sampleSize = MemoryLayout<T>.stride
        var samples = [Float]()
        samples.reserveCapacity(frameCount)

        if inputBuffer.format.isInterleaved {
            guard let audioBuffer = buffers.first,
                  let rawData = audioBuffer.mData else {
                throw LiveSubtitleCaptureServiceError.audioConversionFailed("Missing interleaved audio data.")
            }
            let availableSamples = Int(audioBuffer.mDataByteSize) / sampleSize
            let availableFrames = min(frameCount, availableSamples / channelCount)
            let pointer = rawData.assumingMemoryBound(to: T.self)
            for frameIndex in 0..<availableFrames {
                var sum: Float = 0
                let baseIndex = frameIndex * channelCount
                for channelIndex in 0..<channelCount {
                    sum += normalize(pointer[baseIndex + channelIndex])
                }
                samples.append(sum / Float(channelCount))
            }
        } else {
            let readableChannelCount = min(channelCount, buffers.count)
            guard readableChannelCount > 0 else {
                throw LiveSubtitleCaptureServiceError.audioConversionFailed("Missing planar audio channels.")
            }
            let channelPointers: [UnsafeMutablePointer<T>] = try (0..<readableChannelCount).map { channelIndex in
                guard let rawData = buffers[channelIndex].mData else {
                    throw LiveSubtitleCaptureServiceError.audioConversionFailed("Missing planar audio data.")
                }
                return rawData.assumingMemoryBound(to: T.self)
            }
            let availableFrames = (0..<readableChannelCount).reduce(frameCount) { current, channelIndex in
                min(current, Int(buffers[channelIndex].mDataByteSize) / sampleSize)
            }
            for frameIndex in 0..<availableFrames {
                var sum: Float = 0
                for channelIndex in 0..<readableChannelCount {
                    sum += normalize(channelPointers[channelIndex][frameIndex])
                }
                samples.append(sum / Float(readableChannelCount))
            }
        }

        return samples
    }

    private func appendPCM16(_ sample: Float, to data: inout Data) {
        let clipped = max(-1, min(1, sample))
        let scaled: Int
        if clipped >= 0 {
            scaled = min(Int(clipped * 32_767), 32_767)
        } else {
            scaled = max(Int(clipped * 32_768), -32_768)
        }
        var littleEndian = Int16(scaled).littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
