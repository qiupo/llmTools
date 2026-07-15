import Foundation

public enum LocalBridgeHTTPRequestReadState: Equatable, Sendable {
    case incomplete
    case complete(expectedByteCount: Int)
    case invalid
    case tooLarge
}

public enum LocalBridgeHTTPFraming {
    public static let maximumHeaderBytes = 64 * 1024
    public static let maximumRequestBytes = 2 * 1024 * 1024

    public static func readState(for data: Data) -> LocalBridgeHTTPRequestReadState {
        if data.count > maximumRequestBytes {
            return .tooLarge
        }

        let marker = Data([13, 10, 13, 10])
        guard let headerRange = data.range(of: marker) else {
            return data.count > maximumHeaderBytes ? .tooLarge : .incomplete
        }
        let headersEnd = headerRange.lowerBound
        guard headersEnd <= maximumHeaderBytes,
              let headerText = String(data: data[..<headersEnd], encoding: .utf8) else {
            return headersEnd > maximumHeaderBytes ? .tooLarge : .invalid
        }

        let contentLengthValues = headerText
            .components(separatedBy: "\r\n")
            .dropFirst()
            .compactMap { line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                    return nil
                }
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        guard contentLengthValues.count <= 1 else {
            return .invalid
        }

        let contentLength: Int
        if let rawValue = contentLengthValues.first {
            // 只接受十进制非负整数，避免负数、符号位或溢出绕过请求大小限制。
            guard !rawValue.isEmpty,
                  rawValue.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let parsed = Int(rawValue) else {
                return .invalid
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }

        let bodyStart = headersEnd + marker.count
        let (expectedByteCount, overflowed) = bodyStart.addingReportingOverflow(contentLength)
        guard !overflowed else {
            return .invalid
        }
        guard expectedByteCount <= maximumRequestBytes else {
            return .tooLarge
        }
        return data.count >= expectedByteCount
            ? .complete(expectedByteCount: expectedByteCount)
            : .incomplete
    }
}
