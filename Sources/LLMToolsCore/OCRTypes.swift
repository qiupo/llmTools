import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum OCRTaskError: Error, LocalizedError, Sendable, Equatable {
    case disabled
    case missingImage
    case missingVisionModel
    case modelNotVisionCapable(String)
    case unsupportedVisionRunner(String)
    case unsupportedImageFormat
    case imageTooLarge(current: Int, limit: Int)
    case pixelCountTooLarge(current: Int, limit: Int)
    case remoteImageURLUnsupported(String)
    case remoteImageDownloadFailed(String)
    case temporaryFileCleanupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "OCR/image recognition is disabled."
        case .missingImage:
            return "Choose, paste, or drop an image first."
        case .missingVisionModel:
            return "Choose a vision-capable OCR model in Settings."
        case .modelNotVisionCapable(let modelName):
            return "\(modelName) is not marked as vision-capable."
        case .unsupportedVisionRunner(let modelName):
            return "\(modelName) does not support Phase 3 image payloads."
        case .unsupportedImageFormat:
            return "Unsupported or unreadable image format."
        case .imageTooLarge(let current, let limit):
            return "Image payload is too large: \(current)/\(limit) bytes."
        case .pixelCountTooLarge(let current, let limit):
            return "Image is too large: \(current)/\(limit) pixels."
        case .remoteImageURLUnsupported(let value):
            return "Unsupported image URL: \(value)"
        case .remoteImageDownloadFailed(let message):
            return "Could not download image: \(message)"
        case .temporaryFileCleanupFailed(let message):
            return "Temporary image cleanup failed: \(message)"
        }
    }
}

public struct OCRImageInput: Sendable, Hashable {
    public var data: Data
    public var mimeType: String
    public var fileName: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var contentHash: String
    public var sourceDescription: String

    public init(
        data: Data,
        mimeType: String,
        fileName: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        contentHash: String,
        sourceDescription: String = "Image"
    ) {
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.contentHash = contentHash
        self.sourceDescription = sourceDescription
    }

    public var byteCount: Int {
        data.count
    }

    public var hashPrefix: String {
        String(contentHash.prefix(12))
    }

    public var redactedHistoryPreview: String {
        let sizeText: String
        if let pixelWidth, let pixelHeight {
            sizeText = "\(pixelWidth)x\(pixelHeight)"
        } else {
            sizeText = "unknown-size"
        }
        return "\(sourceDescription) \(sizeText) \(mimeType) #\(hashPrefix)"
    }

    public var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

public struct OCRTaskRequest: Sendable, Hashable {
    public var image: OCRImageInput
    public var mode: OCRMode
    public var prompt: String

    public init(image: OCRImageInput, mode: OCRMode, prompt: String) {
        self.image = image
        self.mode = mode
        self.prompt = prompt
    }
}

public struct OCRTaskResult: Sendable, Hashable {
    public var text: String
    public var rawModelText: String?
    public var structuredMarkdown: String?
    public var modelName: String?
    public var warnings: [String]

    public init(
        text: String,
        rawModelText: String? = nil,
        structuredMarkdown: String? = nil,
        modelName: String? = nil,
        warnings: [String] = []
    ) {
        self.text = text
        self.rawModelText = rawModelText
        self.structuredMarkdown = structuredMarkdown
        self.modelName = modelName
        self.warnings = warnings
    }
}

public struct VisionCapabilityProbeResult: Sendable, Hashable {
    public var modelID: UUID
    public var modelName: String
    public var ok: Bool
    public var message: String

    public init(modelID: UUID, modelName: String, ok: Bool, message: String) {
        self.modelID = modelID
        self.modelName = modelName
        self.ok = ok
        self.message = message
    }
}

public enum RemoteImageURLPolicy {
    public static func validatedURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              !host.isEmpty,
              host != "localhost",
              !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local") else {
            throw OCRTaskError.remoteImageURLUnsupported(value)
        }

        if isIPAddress(host) {
            guard isPublicIPAddress(host) else {
                throw OCRTaskError.remoteImageURLUnsupported(value)
            }
            return url
        }

        let resolvedAddresses = resolveAddresses(for: host)
        guard !resolvedAddresses.isEmpty,
              resolvedAddresses.allSatisfy(isPublicIPAddress) else {
            throw OCRTaskError.remoteImageURLUnsupported(value)
        }
        return url
    }

    public static func isPublicIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 {
            let bytes = withUnsafeBytes(of: &ipv4) { Array($0) }
            guard bytes.count == 4 else {
                return false
            }
            let first = bytes[0]
            let second = bytes[1]
            return first != 0
                && first != 10
                && first != 127
                && !(first == 100 && (64...127).contains(second))
                && !(first == 169 && second == 254)
                && !(first == 172 && (16...31).contains(second))
                && !(first == 192 && second == 0)
                && !(first == 192 && second == 2)
                && !(first == 192 && second == 168)
                && !(first == 198 && (18...19).contains(second))
                && !(first == 198 && second == 51)
                && !(first == 203 && second == 0)
                && first < 224
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, value, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            guard bytes.count == 16 else {
                return false
            }
            let isUnspecified = bytes.allSatisfy { $0 == 0 }
            let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            let isUniqueLocal = (bytes[0] & 0xFE) == 0xFC
            let isLinkLocal = bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80
            let isSiteLocal = bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0xC0
            let isMulticast = bytes[0] == 0xFF
            let isDocumentation = bytes[0] == 0x20
                && bytes[1] == 0x01
                && bytes[2] == 0x0D
                && bytes[3] == 0xB8
            let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 }
                && bytes[10] == 0xFF
                && bytes[11] == 0xFF
            if isIPv4Mapped {
                return isPublicIPAddress(bytes[12...15].map(String.init).joined(separator: "."))
            }
            return !isUnspecified
                && !isLoopback
                && !isUniqueLocal
                && !isLinkLocal
                && !isSiteLocal
                && !isMulticast
                && !isDocumentation
        }
        return false
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return inet_pton(AF_INET, host, &ipv4) == 1 || inet_pton(AF_INET6, host, &ipv6) == 1
    }

    private static func resolveAddresses(for host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else {
            return []
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = result
        while let info = current?.pointee {
            if let address = info.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    address,
                    info.ai_addrlen,
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let terminator = buffer.firstIndex(of: 0) ?? buffer.endIndex
                    addresses.append(String(decoding: buffer[..<terminator].map(UInt8.init(bitPattern:)), as: UTF8.self))
                }
            }
            current = info.ai_next
        }
        return Array(Set(addresses))
    }
}

private struct RemoteImageDownloadResult: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

private final class RemoteImageDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let maximumBytes: Int
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<RemoteImageDownloadResult, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var isFinished = false
    private var isCancelled = false

    init(url: URL, maximumBytes: Int) {
        self.url = url
        self.maximumBytes = maximumBytes
    }

    func download() async throws -> RemoteImageDownloadResult {
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: url)
                let shouldStart = lock.withLock {
                    self.continuation = continuation
                    self.session = session
                    self.task = task
                    return !isCancelled
                }
                if shouldStart {
                    task.resume()
                } else {
                    finish(.failure(CancellationError()))
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let value = request.url?.absoluteString,
              (try? RemoteImageURLPolicy.validatedURL(value)) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            completionHandler(.cancel)
            finish(.failure(OCRTaskError.remoteImageDownloadFailed(
                HTTPURLResponse.localizedString(forStatusCode: statusCode)
            )))
            return
        }
        guard let finalURLValue = httpResponse.url?.absoluteString,
              (try? RemoteImageURLPolicy.validatedURL(finalURLValue)) != nil,
              httpResponse.mimeType?.lowercased().hasPrefix("image/") == true else {
            completionHandler(.cancel)
            finish(.failure(OCRTaskError.remoteImageDownloadFailed(
                "The response is not a permitted public image."
            )))
            return
        }
        if httpResponse.expectedContentLength > Int64(maximumBytes) {
            completionHandler(.cancel)
            finish(.failure(OCRTaskError.imageTooLarge(
                current: Int(clamping: httpResponse.expectedContentLength),
                limit: maximumBytes
            )))
            return
        }
        lock.withLock {
            self.response = httpResponse
            if httpResponse.expectedContentLength > 0 {
                data.reserveCapacity(min(Int(httpResponse.expectedContentLength), maximumBytes))
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let exceededLimit = lock.withLock { () -> Bool in
            guard chunk.count <= maximumBytes - data.count else {
                return true
            }
            data.append(chunk)
            return false
        }
        if exceededLimit {
            dataTask.cancel()
            finish(.failure(OCRTaskError.imageTooLarge(
                current: maximumBytes + 1,
                limit: maximumBytes
            )))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let cancellation = lock.withLock { isCancelled }
            finish(.failure(cancellation ? CancellationError() : error))
            return
        }
        let result = lock.withLock { () -> RemoteImageDownloadResult? in
            guard let response else {
                return nil
            }
            return RemoteImageDownloadResult(data: data, response: response)
        }
        guard let result else {
            finish(.failure(OCRTaskError.remoteImageDownloadFailed("No HTTP response.")))
            return
        }
        finish(.success(result))
    }

    private func cancel() {
        let task = lock.withLock { () -> URLSessionDataTask? in
            isCancelled = true
            return self.task
        }
        task?.cancel()
    }

    private func finish(_ result: Result<RemoteImageDownloadResult, Error>) {
        let state = lock.withLock { () -> (CheckedContinuation<RemoteImageDownloadResult, Error>?, URLSession?) in
            guard !isFinished else {
                return (nil, nil)
            }
            isFinished = true
            let continuation = self.continuation
            self.continuation = nil
            let session = self.session
            self.session = nil
            self.task = nil
            return (continuation, session)
        }
        guard let continuation = state.0 else {
            return
        }
        state.1?.invalidateAndCancel()
        continuation.resume(with: result)
    }
}

public enum OCRImagePreprocessor {
    public static func normalizeImageFile(
        at url: URL,
        preferences: OCRPreferences,
        sourceDescription: String? = nil
    ) throws -> OCRImageInput {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let sourceByteLimit = sourceImageByteLimit(preferences: preferences)
        guard fileSize <= sourceByteLimit else {
            throw OCRTaskError.imageTooLarge(current: fileSize, limit: sourceByteLimit)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: sourceByteLimit + 1) ?? Data()
        guard data.count <= sourceByteLimit else {
            throw OCRTaskError.imageTooLarge(current: data.count, limit: sourceByteLimit)
        }
        return try normalizeImageData(
            data,
            preferences: preferences,
            fileName: url.lastPathComponent,
            sourceDescription: sourceDescription ?? "Image"
        )
    }

    public static func normalizeImageData(
        _ data: Data,
        preferences: OCRPreferences,
        fileName: String? = nil,
        sourceDescription: String = "Image"
    ) throws -> OCRImageInput {
        let sourceByteLimit = sourceImageByteLimit(preferences: preferences)
        guard data.count <= sourceByteLimit else {
            throw OCRTaskError.imageTooLarge(current: data.count, limit: sourceByteLimit)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw OCRTaskError.unsupportedImageFormat
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw OCRTaskError.unsupportedImageFormat
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else {
            throw OCRTaskError.unsupportedImageFormat
        }

        let (pixelCount, pixelCountOverflowed) = width.multipliedReportingOverflow(by: height)
        let maxPixels = min(max(preferences.maximumPixelCount, 1), 100_000_000)
        guard !pixelCountOverflowed else {
            throw OCRTaskError.pixelCountTooLarge(current: Int.max, limit: maxPixels)
        }
        let maxDimension: Int
        if pixelCount > maxPixels {
            let scale = sqrt(Double(maxPixels) / Double(pixelCount))
            maxDimension = max(1, Int(ceil(Double(max(width, height)) * scale)))
        } else {
            maxDimension = max(width, height)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw OCRTaskError.unsupportedImageFormat
        }
        let (normalizedPixelCount, normalizedPixelCountOverflowed) = image.width.multipliedReportingOverflow(by: image.height)
        guard !normalizedPixelCountOverflowed, normalizedPixelCount <= maxPixels else {
            throw OCRTaskError.pixelCountTooLarge(
                current: normalizedPixelCountOverflowed ? Int.max : normalizedPixelCount,
                limit: maxPixels
            )
        }

        let encoded = try encodeProviderImage(
            image,
            maximumImageBytes: encodedImageByteLimit(preferences: preferences)
        )
        let hash = SHA256.hash(data: encoded.data)
            .map { String(format: "%02x", $0) }
            .joined()

        return OCRImageInput(
            data: encoded.data,
            mimeType: encoded.mimeType,
            fileName: fileName,
            pixelWidth: image.width,
            pixelHeight: image.height,
            contentHash: hash,
            sourceDescription: sourceDescription
        )
    }

    public static func downloadAndNormalizeRemoteImage(
        from value: String,
        preferences: OCRPreferences
    ) async throws -> OCRImageInput {
        let url = try RemoteImageURLPolicy.validatedURL(value)
        let maximumDownloadBytes = sourceImageByteLimit(preferences: preferences)

        do {
            // URLSessionDataDelegate 按数据块累计，达到硬上限立即取消连接。
            let result = try await RemoteImageDownloader(
                url: url,
                maximumBytes: maximumDownloadBytes
            ).download()
            return try normalizeImageData(
                result.data,
                preferences: preferences,
                fileName: result.response.url?.lastPathComponent,
                sourceDescription: "Remote image"
            )
        } catch let error as OCRTaskError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OCRTaskError.remoteImageDownloadFailed(error.localizedDescription)
        }
    }

    private static func sourceImageByteLimit(preferences: OCRPreferences) -> Int {
        min(encodedImageByteLimit(preferences: preferences), 8_000_000) * 4
    }

    private static func encodedImageByteLimit(preferences: OCRPreferences) -> Int {
        min(max(preferences.maximumImageBytes, 128_000), 16_000_000)
    }

    public static var probeImage: OCRImageInput {
        let data = makeProbeImageData()
        let hash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return OCRImageInput(
            data: data,
            mimeType: "image/png",
            fileName: "vision-probe.png",
            pixelWidth: 64,
            pixelHeight: 64,
            contentHash: hash,
            sourceDescription: "Probe image"
        )
    }

    private static func makeProbeImageData() -> Data {
        let width = 64
        let height = 64
        let pixels = Data(repeating: 255, count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let data = encode(image, type: UTType.png.identifier as CFString, properties: [:]) else {
            return Data()
        }
        return data
    }

    private static func encodeProviderImage(
        _ image: CGImage,
        maximumImageBytes: Int
    ) throws -> (data: Data, mimeType: String) {
        if let pngData = encode(image, type: UTType.png.identifier as CFString, properties: [:]),
           pngData.count <= maximumImageBytes {
            return (pngData, "image/png")
        }
        let jpegProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.88
        ]
        if let jpegData = encode(image, type: UTType.jpeg.identifier as CFString, properties: jpegProperties),
           jpegData.count <= maximumImageBytes {
            return (jpegData, "image/jpeg")
        }
        let byteCount = encode(image, type: UTType.jpeg.identifier as CFString, properties: jpegProperties)?.count ?? 0
        throw OCRTaskError.imageTooLarge(current: byteCount, limit: maximumImageBytes)
    }

    private static func encode(
        _ image: CGImage,
        type: CFString,
        properties: [CFString: Any]
    ) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
