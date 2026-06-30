import Foundation
import Network
import LLMTranslateCore

@MainActor
final class LocalAppBridgeServer {
    private let appState: AppState
    private var listener: NWListener?
    private var token = UUID().uuidString + UUID().uuidString
    private var runningPort: UInt16?
    private var activeJobs: [String: Task<WebPageTranslateSegmentsResult, Error>] = [:]
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(appState: AppState) {
        self.appState = appState
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    var port: UInt16? {
        runningPort
    }

    func start() {
        guard listener == nil else {
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(IPv4Address("127.0.0.1")!),
                port: .any
            )
            let listener = try NWListener(using: parameters)
            listener.service = nil
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handle(connection: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handle(listenerState: state)
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            appState.validationError = "Could not start webpage bridge: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        runningPort = nil
        activeJobs.values.forEach { $0.cancel() }
        activeJobs.removeAll()
        try? FileManager.default.removeItem(at: AppPaths.webPageBridgeStateFileURL)
    }

    private func handle(listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            if let port = listener?.port {
                runningPort = port.rawValue
                writeBridgeState(port: port.rawValue)
            }
        case .failed(let error):
            appState.validationError = "Webpage bridge failed: \(error.localizedDescription)"
            stop()
        case .cancelled:
            runningPort = nil
        default:
            break
        }
    }

    private func writeBridgeState(port: UInt16) {
        do {
            try FileManager.default.createDirectory(at: AppPaths.applicationSupportDirectory, withIntermediateDirectories: true)
            let state = LocalAppBridgeState(port: port, token: token, pid: ProcessInfo.processInfo.processIdentifier)
            let data = try encoder.encode(state)
            try data.write(to: AppPaths.webPageBridgeStateFileURL, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: AppPaths.webPageBridgeStateFileURL.path
            )
        } catch {
            appState.validationError = "Could not write webpage bridge state: \(error.localizedDescription)"
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .main)
        receiveRequest(connection: connection, accumulated: Data())
    }

    private func receiveRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if let error {
                    self.sendResponse(connection: connection, statusCode: 400, payload: ["error": error.localizedDescription])
                    return
                }
                var next = accumulated
                if let data {
                    next.append(data)
                }
                if self.isCompleteHTTPRequest(next) {
                    await self.respond(to: next, connection: connection)
                } else if isComplete {
                    self.sendResponse(connection: connection, statusCode: 400, payload: ["error": "Incomplete request"])
                } else if next.count > 2 * 1024 * 1024 {
                    self.sendResponse(connection: connection, statusCode: 413, payload: ["error": "Request too large"])
                } else {
                    self.receiveRequest(connection: connection, accumulated: next)
                }
            }
        }
    }

    private func respond(to requestData: Data, connection: NWConnection) async {
        do {
            let request = try parseHTTPRequest(requestData)
            guard request.headers["authorization"] == "Bearer \(token)" else {
                sendResponse(connection: connection, statusCode: 401, payload: errorPayload(code: .extensionNotAllowed, message: "本地桥接认证失败。"))
                return
            }
            switch (request.method, request.path) {
            case ("GET", "/status"):
                sendResponse(
                    connection: connection,
                    statusCode: 200,
                    payload: BridgeStatusPayload(
                        appName: "llmTranslate",
                        protocolVersion: 1,
                        bridgeReady: true,
                        modelName: appState.selectedModelDisplayName(limit: 48),
                        webPageTranslationEnabled: appState.preferences.webPageTranslation.enabled
                    )
                )
            case ("POST", "/translateSegments"):
                let payload = try decoder.decode(WebPageTranslateSegmentsPayload.self, from: request.body)
                let task = Task {
                    try await appState.engine.translateWebPageSegments(
                        payload: payload,
                        modelID: appState.selectedModelID
                    )
                }
                activeJobs[payload.jobID] = task
                do {
                    let result = try await task.value
                    activeJobs[payload.jobID] = nil
                    sendResponse(connection: connection, statusCode: 200, payload: result)
                } catch is CancellationError {
                    activeJobs[payload.jobID] = nil
                    sendResponse(connection: connection, statusCode: 499, payload: errorPayload(code: .cancelled, message: "网页翻译已取消。"))
                } catch let error as WebPageTranslationError {
                    activeJobs[payload.jobID] = nil
                    sendResponse(connection: connection, statusCode: 400, payload: ["error": error])
                } catch {
                    activeJobs[payload.jobID] = nil
                    sendResponse(connection: connection, statusCode: 500, payload: errorPayload(code: .translationFailed, message: error.localizedDescription))
                }
            case ("POST", "/cancelJob"):
                let payload = try decoder.decode(CancelJobPayload.self, from: request.body)
                activeJobs[payload.jobID]?.cancel()
                activeJobs[payload.jobID] = nil
                sendResponse(connection: connection, statusCode: 200, payload: ["cancelled": true])
            default:
                sendResponse(connection: connection, statusCode: 404, payload: ["error": "Not found"])
            }
        } catch {
            sendResponse(connection: connection, statusCode: 400, payload: errorPayload(code: .internalError, message: error.localizedDescription))
        }
    }

    private func parseHTTPRequest(_ data: Data) throws -> HTTPRequest {
        guard let headersEnd = requestHeadersEnd(in: data) else {
            throw BridgeHTTPError.invalidRequest
        }
        let headerData = data[..<headersEnd]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw BridgeHTTPError.invalidRequest
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw BridgeHTTPError.invalidRequest
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw BridgeHTTPError.invalidRequest
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }
            headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        let bodyStart = headersEnd + 4
        let body = bodyStart <= data.count ? Data(data[bodyStart...]) : Data()
        return HTTPRequest(method: requestParts[0], path: requestParts[1], headers: headers, body: body)
    }

    private func requestHeadersEnd(in data: Data) -> Data.Index? {
        let marker = Data([13, 10, 13, 10])
        return data.range(of: marker)?.lowerBound
    }

    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let headersEnd = requestHeadersEnd(in: data),
              let headerText = String(data: data[..<headersEnd], encoding: .utf8) else {
            return false
        }
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line -> Int? in
                let value = line.split(separator: ":", maxSplits: 1).dropFirst().first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.flatMap(Int.init)
            } ?? 0
        return data.count >= headersEnd + 4 + contentLength
    }

    private func sendResponse<Payload: Encodable>(
        connection: NWConnection,
        statusCode: Int,
        payload: Payload
    ) {
        let body = (try? encoder.encode(payload)) ?? Data("{}".utf8)
        let reason = HTTPReason.reason(for: statusCode)
        let header = """
        HTTP/1.1 \(statusCode) \(reason)\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func errorPayload(code: WebPageTranslationErrorCode, message: String) -> [String: WebPageTranslationError] {
        ["error": WebPageTranslationError(code: code, message: message)]
    }
}

public struct LocalAppBridgeState: Codable, Sendable, Hashable {
    public var port: UInt16
    public var token: String
    public var pid: Int32

    public init(port: UInt16, token: String, pid: Int32) {
        self.port = port
        self.token = token
        self.pid = pid
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

private struct BridgeStatusPayload: Codable {
    var appName: String
    var protocolVersion: Int
    var bridgeReady: Bool
    var modelName: String
    var webPageTranslationEnabled: Bool
}

private struct CancelJobPayload: Codable {
    var jobID: String
}

private enum BridgeHTTPError: Error {
    case invalidRequest
}

private enum HTTPReason {
    static func reason(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 499: return "Client Closed Request"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}
