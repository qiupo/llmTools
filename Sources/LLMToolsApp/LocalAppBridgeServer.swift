import Foundation
import Network
import LLMToolsCore

@MainActor
final class LocalAppBridgeServer {
    private let appState: AppState
    private var listener: NWListener?
    private var token = UUID().uuidString + UUID().uuidString
    private var runningPort: UInt16?
    private var activeJobs: [String: [UUID: Task<WebPageTranslateSegmentsResult, Error>]] = [:]
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
        activeJobs.values.flatMap(\.values).forEach { $0.cancel() }
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
                        appName: "llmTools",
                        protocolVersion: 1,
                        bridgeReady: true,
                        modelName: appState.webPageTranslationModelDisplayName(limit: 48),
                        modelIsRemoteProvider: appState.webPageTranslationModelIsRemote,
                        maxConcurrentTranslationRequests: appState.webPageTranslationConcurrencyLimit,
                        appLanguage: appState.preferences.appLanguage.rawValue,
                        webPageTranslationEnabled: appState.preferences.webPageTranslation.enabled,
                        pendingIndicatorStyle: appState.preferences.webPageTranslation.pendingIndicatorStyle.rawValue,
                        autoTranslateDomains: appState.preferences.webPageTranslation.autoTranslateDomains,
                        disabledDomains: appState.preferences.webPageTranslation.disabledDomains,
                        domainReadingModes: domainReadingModePayload,
                        domainTranslationQualities: domainTranslationQualityPayload
                    )
                )
            case ("POST", "/translateSegments"):
                let payload = try decoder.decode(WebPageTranslateSegmentsPayload.self, from: request.body)
                let taskID = UUID()
                appState.beginExternalModelUse()
                let task = Task {
                    try await appState.engine.translateWebPageSegments(
                        payload: payload,
                        modelID: appState.webPageTranslationModelID
                    )
                }
                activeJobs[payload.jobID, default: [:]][taskID] = task
                do {
                    let result = try await task.value
                    finishActiveJob(jobID: payload.jobID, taskID: taskID)
                    sendResponse(connection: connection, statusCode: 200, payload: result)
                } catch is CancellationError {
                    finishActiveJob(jobID: payload.jobID, taskID: taskID)
                    sendResponse(connection: connection, statusCode: 499, payload: errorPayload(code: .cancelled, message: "网页翻译已取消。"))
                } catch let error as WebPageTranslationError {
                    finishActiveJob(jobID: payload.jobID, taskID: taskID)
                    sendResponse(connection: connection, statusCode: 400, payload: ["error": error])
                } catch {
                    finishActiveJob(jobID: payload.jobID, taskID: taskID)
                    sendResponse(connection: connection, statusCode: 500, payload: errorPayload(code: .translationFailed, message: error.localizedDescription))
                }
            case ("POST", "/cancelJob"):
                let payload = try decoder.decode(CancelJobPayload.self, from: request.body)
                activeJobs[payload.jobID]?.values.forEach { $0.cancel() }
                activeJobs[payload.jobID] = nil
                sendResponse(connection: connection, statusCode: 200, payload: ["cancelled": true])
            case ("POST", "/setDomainRule"):
                let payload = try decoder.decode(SetDomainRulePayload.self, from: request.body)
                let response = setDomainRule(domain: payload.domain, rule: payload.rule)
                sendResponse(connection: connection, statusCode: 200, payload: response)
            case ("POST", "/setDomainPageDefaults"):
                let payload = try decoder.decode(SetDomainPageDefaultsPayload.self, from: request.body)
                let response = setDomainPageDefaults(
                    domain: payload.domain,
                    readingMode: payload.readingMode,
                    translationQuality: payload.translationQuality
                )
                sendResponse(connection: connection, statusCode: 200, payload: response)
            case ("POST", "/setPendingIndicatorStyle"):
                let payload = try decoder.decode(SetPendingIndicatorStylePayload.self, from: request.body)
                let response = setPendingIndicatorStyle(payload.pendingIndicatorStyle)
                sendResponse(connection: connection, statusCode: 200, payload: response)
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

    private func finishActiveJob(jobID: String, taskID: UUID) {
        removeActiveJob(jobID: jobID, taskID: taskID)
        appState.endExternalModelUse()
    }

    private func removeActiveJob(jobID: String, taskID: UUID) {
        activeJobs[jobID]?[taskID] = nil
        if activeJobs[jobID]?.isEmpty == true {
            activeJobs[jobID] = nil
        }
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

    private func setDomainRule(domain rawDomain: String, rule rawRule: String) -> DomainRuleResponsePayload {
        let domain = normalizedDomain(rawDomain)
        let rule = normalizedDomainRule(rawRule)
        guard !domain.isEmpty else {
            return DomainRuleResponsePayload(
                domain: "",
                rule: "ask",
                autoTranslateDomains: appState.preferences.webPageTranslation.autoTranslateDomains,
                disabledDomains: appState.preferences.webPageTranslation.disabledDomains
            )
        }

        appState.updatePreferences { preferences in
            var autoDomains = self.normalizedDomains(preferences.webPageTranslation.autoTranslateDomains)
            var disabledDomains = self.normalizedDomains(preferences.webPageTranslation.disabledDomains)
            autoDomains.removeAll { $0 == domain }
            disabledDomains.removeAll { $0 == domain }
            switch rule {
            case "alwaysTranslate":
                autoDomains.append(domain)
            case "neverTranslate":
                disabledDomains.append(domain)
            default:
                break
            }
            preferences.webPageTranslation.autoTranslateDomains = self.normalizedDomains(autoDomains)
            preferences.webPageTranslation.disabledDomains = self.normalizedDomains(disabledDomains)
        }

        return DomainRuleResponsePayload(
            domain: domain,
            rule: rule,
            autoTranslateDomains: appState.preferences.webPageTranslation.autoTranslateDomains,
            disabledDomains: appState.preferences.webPageTranslation.disabledDomains
        )
    }

    private func setDomainPageDefaults(
        domain rawDomain: String,
        readingMode rawReadingMode: String?,
        translationQuality rawTranslationQuality: String?
    ) -> DomainPageDefaultsResponsePayload {
        let domain = normalizedDomain(rawDomain)
        guard !domain.isEmpty else {
            return DomainPageDefaultsResponsePayload(
                domain: "",
                domainReadingModes: domainReadingModePayload,
                domainTranslationQualities: domainTranslationQualityPayload
            )
        }

        appState.updatePreferences { preferences in
            preferences.webPageTranslation.domainReadingModes = self.normalizedReadingModeDefaults(
                preferences.webPageTranslation.domainReadingModes
            )
            preferences.webPageTranslation.domainTranslationQualities = self.normalizedQualityDefaults(
                preferences.webPageTranslation.domainTranslationQualities
            )
            if let rawReadingMode {
                if let readingMode = WebPageReadingMode(rawValue: rawReadingMode) {
                    preferences.webPageTranslation.domainReadingModes[domain] = readingMode
                } else {
                    preferences.webPageTranslation.domainReadingModes.removeValue(forKey: domain)
                }
            }
            if let rawTranslationQuality {
                if let translationQuality = WebPageTranslationQualityMode(rawValue: rawTranslationQuality) {
                    preferences.webPageTranslation.domainTranslationQualities[domain] = translationQuality
                } else {
                    preferences.webPageTranslation.domainTranslationQualities.removeValue(forKey: domain)
                }
            }
        }

        return DomainPageDefaultsResponsePayload(
            domain: domain,
            domainReadingModes: domainReadingModePayload,
            domainTranslationQualities: domainTranslationQualityPayload
        )
    }

    private func setPendingIndicatorStyle(_ rawStyle: String) -> PendingIndicatorStyleResponsePayload {
        let style = WebPagePendingIndicatorStyle(rawValue: rawStyle) ?? .loading
        appState.updatePreferences { preferences in
            preferences.webPageTranslation.pendingIndicatorStyle = style
        }
        return PendingIndicatorStyleResponsePayload(pendingIndicatorStyle: style.rawValue)
    }

    private var domainReadingModePayload: [String: String] {
        appState.preferences.webPageTranslation.domainReadingModes.reduce(into: [:]) { result, item in
            let domain = normalizedDomain(item.key)
            guard !domain.isEmpty else {
                return
            }
            result[domain] = item.value.rawValue
        }
    }

    private var domainTranslationQualityPayload: [String: String] {
        appState.preferences.webPageTranslation.domainTranslationQualities.reduce(into: [:]) { result, item in
            let domain = normalizedDomain(item.key)
            guard !domain.isEmpty else {
                return
            }
            result[domain] = item.value.rawValue
        }
    }

    private func normalizedReadingModeDefaults(_ values: [String: WebPageReadingMode]) -> [String: WebPageReadingMode] {
        values.reduce(into: [:]) { result, item in
            let domain = normalizedDomain(item.key)
            guard !domain.isEmpty else {
                return
            }
            result[domain] = item.value
        }
    }

    private func normalizedQualityDefaults(_ values: [String: WebPageTranslationQualityMode]) -> [String: WebPageTranslationQualityMode] {
        values.reduce(into: [:]) { result, item in
            let domain = normalizedDomain(item.key)
            guard !domain.isEmpty else {
                return
            }
            result[domain] = item.value
        }
    }

    private func normalizedDomainRule(_ rule: String) -> String {
        switch rule {
        case "alwaysTranslate", "neverTranslate":
            return rule
        default:
            return "ask"
        }
    }

    private func normalizedDomains(_ domains: [String]) -> [String] {
        Array(Set(domains.map(normalizedDomain).filter { !$0.isEmpty })).sorted()
    }

    private func normalizedDomain(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let withoutScheme = trimmed
            .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
        let host = withoutScheme
            .split(separator: "/", maxSplits: 1)
            .first?
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
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
    var modelIsRemoteProvider: Bool
    var maxConcurrentTranslationRequests: Int
    var appLanguage: String
    var webPageTranslationEnabled: Bool
    var pendingIndicatorStyle: String
    var autoTranslateDomains: [String]
    var disabledDomains: [String]
    var domainReadingModes: [String: String]
    var domainTranslationQualities: [String: String]
}

private struct CancelJobPayload: Codable {
    var jobID: String
}

private struct SetDomainRulePayload: Codable {
    var domain: String
    var rule: String
}

private struct SetDomainPageDefaultsPayload: Codable {
    var domain: String
    var readingMode: String?
    var translationQuality: String?
}

private struct SetPendingIndicatorStylePayload: Codable {
    var pendingIndicatorStyle: String
}

private struct DomainRuleResponsePayload: Codable {
    var domain: String
    var rule: String
    var autoTranslateDomains: [String]
    var disabledDomains: [String]
}

private struct DomainPageDefaultsResponsePayload: Codable {
    var domain: String
    var domainReadingModes: [String: String]
    var domainTranslationQualities: [String: String]
}

private struct PendingIndicatorStyleResponsePayload: Codable {
    var pendingIndicatorStyle: String
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
