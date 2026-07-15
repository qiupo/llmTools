import Foundation

public enum ProviderRedirectPolicy {
    public static func allowsRedirect(from source: URL, to destination: URL) -> Bool {
        guard ProviderEndpointPolicy.allows(destination) else {
            return false
        }
        return normalizedOrigin(source) == normalizedOrigin(destination)
    }

    private static func normalizedOrigin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return nil
        }
        let defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : -1)
        return "\(scheme)://\(host):\(url.port ?? defaultPort)"
    }
}

private final class ProviderRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let originURL: URL

    init(originURL: URL) {
        self.originURL = originURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let destination = request.url,
              ProviderRedirectPolicy.allowsRedirect(from: originURL, to: destination) else {
            // Provider 请求携带密钥，只允许同协议、同主机、同端口跳转。
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

public enum ProviderHTTPSession {
    public static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let originURL = request.url else {
            throw URLError(.badURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: ProviderRedirectDelegate(originURL: originURL),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }
}
