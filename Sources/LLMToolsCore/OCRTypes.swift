import CoreGraphics
import CryptoKit
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

public enum OCRImagePreprocessor {
    public static func normalizeImageFile(
        at url: URL,
        preferences: OCRPreferences,
        sourceDescription: String? = nil
    ) throws -> OCRImageInput {
        let data = try Data(contentsOf: url)
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
        guard data.count <= max(preferences.maximumImageBytes * 4, preferences.maximumImageBytes) else {
            throw OCRTaskError.imageTooLarge(current: data.count, limit: preferences.maximumImageBytes)
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

        let pixelCount = width * height
        let maxPixels = max(preferences.maximumPixelCount, 1)
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
        let normalizedPixelCount = image.width * image.height
        guard normalizedPixelCount <= maxPixels else {
            throw OCRTaskError.pixelCountTooLarge(current: normalizedPixelCount, limit: maxPixels)
        }

        let encoded = try encodeProviderImage(
            image,
            maximumImageBytes: preferences.maximumImageBytes
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw OCRTaskError.remoteImageURLUnsupported(value)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw OCRTaskError.remoteImageDownloadFailed(
                    HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                )
            }
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("llmTools-ocr", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            let tempURL = tempDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "img" : url.pathExtension)
            try data.write(to: tempURL, options: [.atomic])
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }
            return try normalizeImageFile(
                at: tempURL,
                preferences: preferences,
                sourceDescription: "Remote image"
            )
        } catch let error as OCRTaskError {
            throw error
        } catch {
            throw OCRTaskError.remoteImageDownloadFailed(error.localizedDescription)
        }
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
