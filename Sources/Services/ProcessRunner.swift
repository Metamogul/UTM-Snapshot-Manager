import Foundation

/// Result of an external command.
struct CommandResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String

    /// False when the command was still running when its deadline passed.
    let finished: Bool

    var ok: Bool { finished && status == 0 }

    var message: String {
        let joined = stdout + "\n" + stderr
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func timedOut() -> CommandResult {
        CommandResult(status: -1, stdout: "", stderr: "", finished: false)
    }
}

/// Runs command line tools off the main thread, always with a deadline.
///
/// The deadline is not optional. An earlier version time-boxed the directory
/// walk but not `qemu-img`, and a single image on an unreachable network volume
/// was enough to hang a scan forever — which in turn latched the "one scan at a
/// time" guard and killed every later refresh. Here a process that overruns is
/// terminated rather than waited on, so no caller can be stuck indefinitely.
enum ProcessRunner {

    /// Default deadline for the short, local commands this app runs.
    static let defaultTimeout: TimeInterval = 15

    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let gate = ResumeGate()
            DispatchQueue.global(qos: .userInitiated).async {
                let value = runSync(executable, arguments, timeout: timeout)
                if gate.claim() { continuation.resume(returning: value) }
            }
        }
    }

    /// Synchronous variant for the handful of checks that run before the UI
    /// exists. Same deadline behaviour.
    static func runSync(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription, finished: true)
        }

        // Drain both pipes before waiting - a full buffer would deadlock the
        // child no matter what the deadline says.
        let box = OutputBox()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            box.setOut(outPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            box.setErr(errPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        // Terminate rather than wait forever. SIGTERM first so qemu-img can
        // release its image lock; SIGKILL only if it ignores that.
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if group.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = group.wait(timeout: .now() + 2)
            }
            // Deliberately no `waitUntilExit()` here. It takes no timeout, and a
            // process wedged in an uninterruptible kernel wait does not die on
            // SIGKILL either — waiting on it would undo the very deadline this
            // branch exists to enforce. The caller is released; Foundation reaps
            // the child when it finally goes.
            return .timedOut()
        }

        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: box.outString,
            stderr: box.errString,
            finished: true
        )
    }

    /// Both reader closures write into this instead of capturing `var`s, so the
    /// hand-off to the waiting thread goes through one lock rather than relying
    /// on the dispatch group alone.
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()

        func setOut(_ data: Data) { lock.lock(); out = data; lock.unlock() }
        func setErr(_ data: Data) { lock.lock(); err = data; lock.unlock() }

        var outString: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: out, as: UTF8.self)
        }
        var errString: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: err, as: UTF8.self)
        }
    }

    /// Makes sure a continuation is resumed exactly once.
    final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    /// Races async work against a deadline, returning `nil` if it overruns.
    ///
    /// A task group cannot express this either: it waits for every child before
    /// returning, so cancelling the slow one still blocks until it finishes.
    /// This releases the caller on time and lets the loser finish unobserved.
    static func withDeadline<T: Sendable>(
        _ seconds: Double,
        _ work: @escaping @Sendable () async -> T
    ) async -> T? {
        await withCheckedContinuation { continuation in
            let gate = ResumeGate()
            Task {
                let value = await work()
                if gate.claim() { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }

    /// Runs blocking, uninterruptible work with a hard deadline.
    ///
    /// A task group cannot do this: cancelling a child task does not interrupt a
    /// blocking syscall, and the group only returns once every child finished. A
    /// permission dialog or an unreachable share would freeze the app for as
    /// long as it stays open. Here the caller is released on the deadline and
    /// the abandoned thread is left to finish on its own.
    static func timeboxed<T: Sendable>(
        _ seconds: Double,
        fallback: T,
        work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            let gate = ResumeGate()
            DispatchQueue.global(qos: .userInitiated).async {
                let value = work()
                if gate.claim() { continuation.resume(returning: value) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
                if gate.claim() { continuation.resume(returning: fallback) }
            }
        }
    }
}
