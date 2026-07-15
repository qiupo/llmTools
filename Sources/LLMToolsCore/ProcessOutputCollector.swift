import Foundation

public struct ProcessOutput: Sendable {
    public var terminationStatus: Int32
    public var standardOutput: Data
    public var standardError: Data

    public init(terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum ProcessOutputCollector {
    public static func run(_ process: Process, maximumCapturedBytes: Int = 64 * 1_024) async throws -> ProcessOutput {
        try Task.checkCancellation()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let processHandle = CancellableProcessHandle(process: process)

        return try await withTaskCancellationHandler {
            try processHandle.run()
            // 两条管道必须在等待进程退出前并发排空，否则安装日志较大时会互相死锁。
            async let output = readToEnd(outputPipe, maximumCapturedBytes: maximumCapturedBytes)
            async let errorOutput = readToEnd(errorPipe, maximumCapturedBytes: maximumCapturedBytes)
            process.waitUntilExit()
            let captured = await (output, errorOutput)
            let result = ProcessOutput(
                terminationStatus: process.terminationStatus,
                standardOutput: captured.0,
                standardError: captured.1
            )
            try Task.checkCancellation()
            return result
        } onCancel: {
            processHandle.cancel()
        }
    }

    private static func readToEnd(_ pipe: Pipe, maximumCapturedBytes: Int) async -> Data {
        await Task.detached(priority: .utility) {
            let limit = max(0, maximumCapturedBytes)
            var tail = Data()
            while true {
                let chunk = pipe.fileHandleForReading.readData(ofLength: 16 * 1_024)
                guard !chunk.isEmpty else {
                    return tail
                }
                guard limit > 0 else {
                    continue
                }
                tail.append(chunk)
                if tail.count > limit {
                    tail.removeFirst(tail.count - limit)
                }
            }
        }.value
    }
}
