import Foundation

public enum RunnerError: Error, LocalizedError, Sendable {
    case notLoaded
    case unsupportedFormat(ModelFormat)
    case emptyResult
    case inputTooLong(current: Int, limit: Int)
    case unsupportedConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "The model is not loaded."
        case .unsupportedFormat(let format):
            return "Unsupported model format: \(format.rawValue)"
        case .emptyResult:
            return "模型返回了空结果，请重新生成。"
        case .inputTooLong(let current, let limit):
            return "Input is too long for the selected model. Shorten it to \(limit) characters or less. Current length: \(current)."
        case .unsupportedConfiguration(let message):
            return message
        }
    }
}

public protocol ModelRunner: Actor, Sendable {
    func modelFormat() async -> ModelFormat
    func loadedState() async -> Bool
    func loadedModelID() async -> UUID?
    func loadedModelName() async -> String?
    func load(model: ModelDescriptor) async throws
    func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult
    func unload() async
}

public protocol VisionModelRunner: ModelRunner {
    func generateOCR(request: OCRTaskRequest, preferences: AppPreferences) async throws -> OCRTaskResult
}
