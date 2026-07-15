import Foundation
import Darwin

final class CancellableProcessHandle: @unchecked Sendable {
    let process: Process

    private let lock = NSLock()
    private var cancellationRequested = false

    init(process: Process) {
        self.process = process
    }

    func run() throws {
        lock.lock()
        if cancellationRequested {
            lock.unlock()
            throw CancellationError()
        }
        do {
            try process.run()
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let shouldTerminate = process.isRunning
        lock.unlock()

        if shouldTerminate {
            process.terminate()
        }
    }
}

/// 持久 sidecar 的停止不能等待请求锁，否则正在读取 stdout 的请求会让模型进程永远无法退出。
final class PersistentProcessLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool {
        lock.withLock { stopped }
    }

    func stop(
        process: Process,
        inputHandle: FileHandle,
        errorHandle: FileHandle
    ) {
        let shouldStop = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            stopped = true
            return true
        }
        guard shouldStop else { return }

        errorHandle.readabilityHandler = nil
        try? inputHandle.close()
        guard process.isRunning else { return }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(500)) {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(2)) {
                guard process.isRunning else { return }
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}
