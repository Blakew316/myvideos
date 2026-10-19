//
//  ProcessRunner.swift
//  My Videos
//

import Foundation

/// A command-line tool whose combined output is streamed back line by line.
nonisolated final class StreamingProcess: @unchecked Sendable {
    private let process = Process()

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = Toolchain.childEnvironment
        process.standardInput = FileHandle.nullDevice
    }

    var isRunning: Bool { process.isRunning }

    /// Launches the tool. Output arrives in whole lines (a read can end mid-line or even
    /// mid-UTF-8 character), and `onExit` is delivered only after EOF *and* exit — both on
    /// the main queue, in order — so the last lines are always handled before the result.
    func start(onLines: @escaping @MainActor ([String]) -> Void,
               onExit: @escaping @MainActor (_ status: Int32, _ signalled: Bool) -> Void) throws {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let handle = pipe.fileHandleForReading
        let process = self.process
        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = Data()
            func flush(all: Bool) {
                var lines: [String] = []
                while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    lines.append(String(decoding: buffer[buffer.startIndex..<idx], as: UTF8.self))
                    buffer.removeSubrange(buffer.startIndex...idx)
                }
                if all, !buffer.isEmpty {
                    lines.append(String(decoding: buffer, as: UTF8.self))
                    buffer.removeAll()
                }
                lines.removeAll { $0.isEmpty }
                guard !lines.isEmpty else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { onLines(lines) } }
            }
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                flush(all: false)
            }
            flush(all: true)
            process.waitUntilExit()
            let status = process.terminationStatus
            let signalled = process.terminationReason == .uncaughtSignal
            DispatchQueue.main.async { MainActor.assumeIsolated { onExit(status, signalled) } }
        }
    }

    /// Stops the tool and anything it spawned (yt-dlp runs ffmpeg as a child, which would
    /// otherwise keep running — and writing — after yt-dlp itself is gone).
    func terminate() {
        guard process.isRunning else { return }
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-TERM", "-P", String(process.processIdentifier)]
        try? pkill.run()
        pkill.waitUntilExit()
        process.terminate()
    }
}

/// Runs a tool to completion and captures stdout / stderr separately.
nonisolated enum ProcessRunner {
    struct Output: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: String
        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    }

    private final class Handle: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var cancelled = false

        func markLaunchedOrCancel() {
            lock.lock(); defer { lock.unlock() }
            if cancelled, process.isRunning { process.terminate() }
        }

        func cancel() {
            lock.lock(); defer { lock.unlock() }
            cancelled = true
            if process.isRunning { process.terminate() }
        }
    }

    /// Cancelling the calling task terminates the tool.
    static func run(_ executable: URL, _ arguments: [String]) async throws -> Output {
        let handle = Handle()
        let process = handle.process
        process.executableURL = executable
        process.arguments = arguments
        process.environment = Toolchain.childEnvironment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    handle.markLaunchedOrCancel()
                    // Drain stderr concurrently so a chatty tool can't fill one pipe and deadlock.
                    let errBox = DataBox()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    let outData = out.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()
                    continuation.resume(returning: Output(status: process.terminationStatus,
                                                          stdout: outData,
                                                          stderr: String(decoding: errBox.data, as: UTF8.self)))
                }
            }
        } onCancel: {
            handle.cancel()
        }
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}
