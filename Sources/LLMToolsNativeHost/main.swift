import Foundation
import LLMToolsCore

@main
struct LLMToolsNativeHost {
    static func main() {
        let host = NativeMessagingHost()
        host.run()
    }
}

final class NativeMessagingHost: @unchecked Sendable {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private let outputLock = NSLock()

    init() {}

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func run() {
        let group = DispatchGroup()
        while true {
            guard let messageData = readNativeMessage() else {
                break
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let response = handle(messageData: messageData)
                writeNativeMessage(response)
                group.leave()
            }
        }
        group.wait()
    }

    private func handle(messageData: Data) -> Data {
        do {
            let request = try makeDecoder().decode(GenericNativeEnvelope.self, from: messageData)
            switch request.type {
            case "hello", "getStatus":
                return try statusResponse(for: request)
            case "translateSegments":
                return try bridgeResponse(for: request, path: "/translateSegments")
            case "cancelJob":
                return try bridgeResponse(for: request, path: "/cancelJob")
            case "setDomainRule":
                return try bridgeResponse(for: request, path: "/setDomainRule")
            case "setDomainPageDefaults":
                return try bridgeResponse(for: request, path: "/setDomainPageDefaults")
            case "setPendingIndicatorStyle":
                return try bridgeResponse(for: request, path: "/setPendingIndicatorStyle")
            case "createLiveSubtitleSession":
                return try bridgeResponse(for: request, path: "/liveSubtitleSessions")
            case "appendLiveAudioChunk":
                return try bridgeResponse(for: request, path: "/liveSubtitleChunks")
            case "stopLiveSubtitleSession":
                return try bridgeResponse(for: request, path: "/stopLiveSubtitleSession")
            case "getAppLiveSubtitleStatus":
                return try bridgeResponse(for: request, path: "/appLiveSubtitleStatus", method: "GET")
            case "startAppLiveSubtitles":
                return try bridgeResponse(for: request, path: "/startAppLiveSubtitles")
            case "stopAppLiveSubtitles":
                return try bridgeResponse(for: request, path: "/stopAppLiveSubtitles")
            case "openSettings":
                return try statusResponse(for: request)
            default:
                return try encodeErrorResponse(
                    requestID: request.requestID,
                    type: "\(request.type).result",
                    code: .internalError,
                    message: "未知的网页翻译请求。"
                )
            }
        } catch {
            return (try? encodeErrorResponse(
                requestID: UUID().uuidString,
                type: "error",
                code: .internalError,
                message: error.localizedDescription
            )) ?? Data("{}".utf8)
        }
    }

    private func statusResponse(for request: GenericNativeEnvelope) throws -> Data {
        guard let state = readBridgeState() else {
            return try encodeErrorResponse(
                requestID: request.requestID,
                type: "\(request.type).result",
                code: .appNotRunning,
                message: "llmTools 未运行，请先启动应用。"
            )
        }
        let data = try httpRequest(state: state, method: "GET", path: "/status", body: nil)
        let payload = try decodeHTTPBody(data)
        return try encodeEnvelope(
            requestID: request.requestID,
            type: "\(request.type).result",
            status: "ok",
            payload: payload,
            error: nil
        )
    }

    private func bridgeResponse(for request: GenericNativeEnvelope, path: String, method: String = "POST") throws -> Data {
        guard let state = readBridgeState() else {
            return try encodeErrorResponse(
                requestID: request.requestID,
                type: "\(request.type).result",
                code: .appNotRunning,
                message: "llmTools 未运行，请先启动应用。"
            )
        }
        let body = method == "GET" ? nil : (request.payload ?? Data("{}".utf8))
        do {
            let data = try httpRequest(state: state, method: method, path: path, body: body)
            let payload = try decodeHTTPBody(data)
            return try encodeEnvelope(
                requestID: request.requestID,
                type: "\(request.type).result",
                status: "ok",
                payload: payload,
                error: nil
            )
        } catch let error as NativeHostHTTPError {
            return try encodeErrorResponse(
                requestID: request.requestID,
                type: "\(request.type).result",
                code: error.code,
                message: error.message
            )
        }
    }

    private func readBridgeState() -> LocalBridgeState? {
        guard let data = try? Data(contentsOf: AppPaths.webPageBridgeStateFileURL),
              let state = try? makeDecoder().decode(LocalBridgeState.self, from: data) else {
            return nil
        }
        guard state.pid > 0, kill(state.pid, 0) == 0 else {
            return nil
        }
        return state
    }

    private func httpRequest(state: LocalBridgeState, method: String, path: String, body: Data?) throws -> Data {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(state.port)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(state.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = body

        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = box.error {
            throw NativeHostHTTPError(code: .appNotRunning, message: error.localizedDescription)
        }
        guard let httpResponse = box.response as? HTTPURLResponse,
              let data = box.data else {
            throw NativeHostHTTPError(code: .appNotRunning, message: "本地桥接没有响应。")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? makeDecoder().decode(BridgeErrorEnvelope.self, from: data).error.message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw NativeHostHTTPError(code: .translationFailed, message: message)
        }
        return data
    }

    private func decodeHTTPBody(_ data: Data) throws -> Data {
        if JSONSerialization.isValidJSONObject(try JSONSerialization.jsonObject(with: data)) {
            return data
        }
        return Data("{}".utf8)
    }

    private func encodeEnvelope(
        requestID: String,
        type: String,
        status: String,
        payload: Data?,
        error: WebPageTranslationError?
    ) throws -> Data {
        var object: [String: Any] = [
            "protocolVersion": 1,
            "requestID": requestID,
            "type": type,
            "status": status
        ]
        if let payload,
           let payloadObject = try JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            object["payload"] = payloadObject
        } else {
            object["payload"] = NSNull()
        }
        if let error {
            object["error"] = [
                "code": error.code.rawValue,
                "message": error.message,
                "repairAction": error.repairAction as Any,
                "diagnostic": error.diagnostic as Any
            ]
        } else {
            object["error"] = NSNull()
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func encodeErrorResponse(
        requestID: String,
        type: String,
        code: WebPageTranslationErrorCode,
        message: String
    ) throws -> Data {
        try encodeEnvelope(
            requestID: requestID,
            type: type,
            status: "error",
            payload: nil,
            error: WebPageTranslationError(code: code, message: message)
        )
    }

    private func readNativeMessage() -> Data? {
        let lengthData = input.readData(ofLength: 4)
        guard lengthData.count == 4 else {
            return nil
        }
        let length = lengthData.withUnsafeBytes { pointer -> UInt32 in
            pointer.load(as: UInt32.self).littleEndian
        }
        guard length > 0, length < 16 * 1024 * 1024 else {
            return nil
        }
        let data = input.readData(ofLength: Int(length))
        guard data.count == Int(length) else {
            return nil
        }
        return data
    }

    private func writeNativeMessage(_ data: Data) {
        var length = UInt32(data.count).littleEndian
        let lengthData = Data(bytes: &length, count: 4)
        outputLock.lock()
        defer { outputLock.unlock() }
        output.write(lengthData)
        output.write(data)
    }
}

private struct GenericNativeEnvelope: Decodable {
    var protocolVersion: Int?
    var requestID: String
    var type: String
    var payload: Data?

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case requestID
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion)
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID) ?? UUID().uuidString
        type = try container.decode(String.self, forKey: .type)
        if container.contains(.payload) {
            let payloadObject = try container.decode(JSONValue.self, forKey: .payload)
            payload = try JSONSerialization.data(withJSONObject: payloadObject.jsonObject)
        } else {
            payload = nil
        }
    }
}

private struct LocalBridgeState: Decodable {
    var port: UInt16
    var token: String
    var pid: Int32
}

private struct BridgeErrorEnvelope: Decodable {
    var error: WebPageTranslationError
}

private struct NativeHostHTTPError: Error {
    var code: WebPageTranslationErrorCode
    var message: String
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var jsonObject: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues(\.jsonObject)
        case .array(let value):
            return value.map(\.jsonObject)
        case .null:
            return NSNull()
        }
    }
}
