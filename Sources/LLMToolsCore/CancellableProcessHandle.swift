import Foundation

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
