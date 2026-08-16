import Darwin
import Foundation
import os

/// The shared container every Roam process reads and writes.
///
/// Declared here rather than beside the data stack because the logger reaches
/// for it from every target, including the test bundles that do not compile the
/// data stack at all. `mainAppGroup` is an alias of this.
public let roamAppGroup = "group.com.msdrigg.roam"

/// Durable, per-run diagnostics that outlive the process that wrote them.
///
/// Everything Roam knew about a crash used to come from
/// `OSLogStore(scope: .currentProcessIdentifier)`, read while assembling the
/// MetricKit upload. That scope is the *reading* process, and MetricKit only
/// hands a payload to the launch **after** the one that died — so every crash
/// report shipped the relaunch's log, which by construction says nothing about
/// what crashed. The three macOS stack overflows reviewed on 2026-08-16 all
/// arrived with a log window that began after the crash.
///
/// So the app keeps its own copy: every `DualLogger` line is mirrored into a
/// file named for the run that wrote it, and the next launch reads the dead
/// run's file back (see `FileLog.collect(around:)`).
///
/// `CrashStackTrap`, below, covers the other half of the same gap — MetricKit
/// could not unwind the blown stack on any of those three reports, so the
/// attributed thread arrived with zero frames.
public enum FileLog {
    private static let directoryName = "process-logs"
    /// Per-run cap. A rolling tail for diagnosis, not an archive.
    private static let maxBytesPerRun = 1_500_000
    /// How many previous runs to keep. A crash is uploaded on the very next
    /// launch, so this only needs to cover launches that failed to upload.
    private static let maxRunFiles = 8
    /// Lines are batched: a remote app logs a few hundred lines a second while
    /// scanning, and one `write(2)` per line would be pure overhead.
    private static let flushThresholdBytes = 16 * 1024
    private static let flushInterval: TimeInterval = 1

    /// Serialises every touch of the buffer, the handle and the counters.
    private static let queue = DispatchQueue(
        label: "com.msdrigg.roam.file-log", qos: .utility)

    /// Raw logger for our own failures — must never recurse through `DualLogger`.
    private static let selfLog = Logger(subsystem: Log.getLogSubsystem(), category: "FileLog")

    public static let pid = Int(ProcessInfo.processInfo.processIdentifier)
    private static let processName = ProcessInfo.processInfo.processName
    /// Identifies this run's file. Wall-clock at launch, so run files sort by
    /// age even after the OS recycles a pid.
    static let launchedAt = Date()

    // Queue-confined state (every touch happens on `queue`, hence the opt-out).
    nonisolated(unsafe) private static var buffer = Data()
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var bytesWritten = 0
    nonisolated(unsafe) private static var flushScheduled = false
    nonisolated(unsafe) private static var started = false

    /// Opens this run's file and prunes older ones. Safe to call more than once;
    /// only the first call does anything.
    ///
    /// Call it early — anything logged before this lands in the buffer and is
    /// written on the first flush, but a run that never starts the log leaves
    /// nothing behind if it dies.
    public static func start() {
        queue.async {
            guard !started else { return }
            started = true
            pruneOldRuns()
        }
        observeLifecycle()
    }

    /// Flush when the process is about to stop running our code. A suspended
    /// app does not service the flush timer, so without this the last second of
    /// a session is lost every time it goes to the background.
    ///
    /// Named rather than typed so this file stays free of UIKit/AppKit and
    /// compiles unchanged into the widget and watch targets.
    private static func observeLifecycle() {
        let names = [
            "NSApplicationWillTerminateNotification",
            "NSApplicationDidResignActiveNotification",
            "UIApplicationWillTerminateNotification",
            "UIApplicationDidEnterBackgroundNotification",
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                forName: Notification.Name(name), object: nil, queue: nil
            ) { _ in
                flushNow()
            }
        }
    }

    /// Mirror one line into this run's file.
    public static func append(level: String, category: String, message: String) {
        // Snapshot the timestamp on the calling thread: the flush is
        // asynchronous, and a line's time is when it happened, not when it
        // reached the disk.
        let timestamp = Date().timeIntervalSince1970
        queue.async {
            appendEncoded(timestamp: timestamp, level: level, category: category, message: message)
        }
    }

    /// Push everything buffered to disk and wait for it.
    ///
    /// Used where the next thing to happen may be the process dying: the
    /// stack-depth warnings in `RenderTrace`, and backgrounding.
    public static func flushNow() {
        queue.sync { flush() }
    }

    // MARK: Writing

    /// One JSONL line, hand-rolled rather than run through `JSONEncoder`: this
    /// happens on every log line in the app, and the shape is four fixed keys.
    ///
    /// It has to decode as `FileLogEntry`; the two are written independently,
    /// so a test pins them together.
    public static func encodedLine(
        timestamp: TimeInterval, level: String, category: String, message: String
    ) -> String {
        var line = "{\"t\":"
        line += String(format: "%.3f", timestamp)
        line += ",\"l\":\""
        line += jsonEscaped(level)
        line += "\",\"c\":\""
        line += jsonEscaped(category)
        line += "\",\"m\":\""
        line += jsonEscaped(message)
        line += "\"}\n"
        return line
    }

    private static func appendEncoded(
        timestamp: TimeInterval, level: String, category: String, message: String
    ) {
        let line = encodedLine(
            timestamp: timestamp, level: level, category: category, message: message)
        buffer.append(contentsOf: Array(line.utf8))
        if buffer.count >= flushThresholdBytes {
            flush()
        } else {
            scheduleFlush()
        }
    }

    private static func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + flushInterval) {
            flushScheduled = false
            flush()
        }
    }

    private static func flush() {
        guard !buffer.isEmpty else { return }
        let pending = buffer
        buffer.removeAll(keepingCapacity: true)
        do {
            let handle = try openHandle()
            try handle.write(contentsOf: pending)
            bytesWritten += pending.count
            if bytesWritten > maxBytesPerRun {
                trim()
            }
        } catch {
            selfLog.error("file-log write failed: \(error.localizedDescription, privacy: .public)")
            try? handle?.close()
            handle = nil
        }
    }

    private static func openHandle() throws -> FileHandle {
        if let handle { return handle }
        guard let url = runFileURL() else { throw CocoaError(.fileNoSuchFile) }
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            manager.createFile(atPath: url.path, contents: nil)
        }
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        bytesWritten = Int(try opened.offset())
        handle = opened
        return opened
    }

    /// Drop whole lines off the front until the run file is back under its cap.
    private static func trim() {
        guard
            let url = runFileURL(),
            let data = try? Data(contentsOf: url)
        else { return }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var kept = data.count
        while kept > maxBytesPerRun, !lines.isEmpty {
            kept -= lines.removeFirst().count + 1
        }
        var out = Data(capacity: kept)
        for line in lines {
            out.append(contentsOf: line)
            out.append(0x0A)
        }
        try? handle?.close()
        handle = nil
        try? out.write(to: url, options: .atomic)
        bytesWritten = out.count
    }

    /// Keep the newest `maxRunFiles` runs **per process**, never our own.
    ///
    /// Per process, because the widget extension shares this directory and is
    /// launched far more often than the app. A flat cap would let a morning of
    /// widget refreshes evict the app run that crashed overnight, which is the
    /// one run that had to survive.
    private static func pruneOldRuns() {
        guard let directory = directoryURL() else { return }
        let manager = FileManager.default
        let ours = runFileURL()?.lastPathComponent
        let files =
            (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []

        var byProcess: [String: [URL]] = [:]
        for file in files
            where file.pathExtension == "jsonl" && file.lastPathComponent != ours
        {
            // "<stamp>-<pid>-<process>.jsonl" — the process is everything past
            // the second separator, and may itself contain dashes.
            let stem = file.deletingPathExtension().lastPathComponent
            let process = stem.split(separator: "-", maxSplits: 2).last.map(String.init) ?? stem
            byProcess[process, default: []].append(file)
        }

        for (_, runs) in byProcess {
            let stale = runs
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .dropFirst(maxRunFiles)
            for file in stale {
                try? manager.removeItem(at: file)
                // The backtrace beside it is only meaningful with its log.
                try? manager.removeItem(at: file.deletingPathExtension().appendingPathExtension("stack"))
            }
        }
    }

    // MARK: Reading

    /// Entries from **previous** runs, newest last, centred on a crash.
    ///
    /// `window` is MetricKit's payload window. Anything logged after it is from
    /// a launch that came later than the crash, and is dropped: that is exactly
    /// the noise this whole file exists to remove. This run's own file is
    /// excluded for the same reason — when we are uploading a crash, we are by
    /// definition the launch that came after it.
    public static func collect(around window: DateInterval?, limit: Int = 5000) -> [FileLogEntry] {
        guard let directory = directoryURL() else { return [] }
        let manager = FileManager.default
        let ours = runFileURL()?.lastPathComponent
        let files =
            (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []

        // A crash is reported on the next launch, so the run we want is the
        // newest one that is not us. Read newest-first and stop once we have
        // enough.
        let candidates =
            files
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent != ours }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        // A little slack past the payload window: MetricKit stamps the window
        // to the minute, so the last lines before the crash can land just
        // outside it.
        let cutoff = window.map { $0.end.addingTimeInterval(120) }

        var collected: [FileLogEntry] = []
        let decoder = JSONDecoder()
        for file in candidates {
            guard let data = try? Data(contentsOf: file) else { continue }
            var fromFile: [FileLogEntry] = []
            for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                guard let entry = try? decoder.decode(FileLogEntry.self, from: Data(line))
                else { continue }
                if let cutoff, entry.date > cutoff { continue }
                fromFile.append(entry)
            }
            collected.insert(contentsOf: fromFile, at: 0)
            if collected.count >= limit { break }
        }

        if collected.count > limit {
            // Keep the newest: whatever the app was doing last is the part that
            // explains the crash.
            collected.removeFirst(collected.count - limit)
        }
        return collected
    }

    /// Wipe every run's file, including our own.
    public static func deleteAll() {
        queue.async {
            try? handle?.close()
            handle = nil
            buffer.removeAll(keepingCapacity: false)
            bytesWritten = 0
            guard let directory = directoryURL() else { return }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Paths

    static func directoryURL() -> URL? {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: roamAppGroup)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return container?.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Sortable by age, and unique even when the OS recycles a pid.
    static func runFileName(extension pathExtension: String) -> String {
        let stamp = Int(launchedAt.timeIntervalSince1970 * 1000)
        return "\(stamp)-\(pid)-\(processName).\(pathExtension)"
    }

    private static func runFileURL() -> URL? {
        directoryURL()?.appendingPathComponent(runFileName(extension: "jsonl"))
    }

    private static func jsonEscaped(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count + 8)
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out
    }
}

/// One line read back off disk. Short keys because they are written once per
/// log line; `FileLog` writes this shape by hand.
public struct FileLogEntry: Codable, Sendable {
    let t: TimeInterval
    let l: String
    let c: String
    let m: String

    var date: Date { Date(timeIntervalSince1970: t) }
    var level: String { l }
    var category: String { c }
    var message: String { m }
}

/// Writes the crashing thread's backtrace to disk from inside a `SIGSEGV`
/// handler running on its own signal stack.
///
/// This exists because MetricKit cannot unwind a **stack overflow**. All three
/// macOS crashes reviewed on 2026-08-16 came back with the attributed thread
/// holding zero frames — in the raw payload, not just the rendered report — so
/// the one thing needed to name the recursion was the one thing missing.
///
/// A handler installed the ordinary way cannot help either: the thread that
/// overflowed has no stack left to run it on. `sigaltstack` gives the handler
/// its own, which is the whole point.
///
/// The handler is deliberately minimal and touches only async-signal-safe
/// calls (`open`, `write`, `backtrace`, `backtrace_symbols_fd`), then restores
/// the previous disposition and re-raises so the OS still produces the crash
/// report MetricKit delivers. We add a trace; we do not swallow the crash.
public enum CrashStackTrap {
    private static let maxFrames = 192

    nonisolated(unsafe) private static var installed = false
    /// Preallocated at install time — a signal handler must not allocate.
    nonisolated(unsafe) private static var frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    nonisolated(unsafe) private static var alternateStack: UnsafeMutableRawPointer?
    nonisolated(unsafe) static var pathBuffer: UnsafeMutablePointer<CChar>?

    /// Install the handler. Idempotent.
    ///
    /// A no-op on watchOS, where `sigaltstack` is unavailable — without an
    /// alternate stack a handler cannot run on an overflowed stack anyway, so
    /// there is nothing to fall back to.
    public static func install() {
        #if os(watchOS)
            return
        #else
            installHandler()
        #endif
    }

    #if !os(watchOS)
    private static func installHandler() {
        guard !installed else { return }
        guard let url = traceFileURL() else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Everything the handler touches is set up here, while it is still safe
        // to allocate: a lazily-initialised Swift global read for the first
        // time from inside a signal handler can deadlock on its own once-token.
        let path = url.path
        let bytes = Array(path.utf8CString)
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
        buffer.update(from: bytes, count: bytes.count)
        pathBuffer = buffer
        frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: maxFrames)

        let stackSize = max(Int(SIGSTKSZ), 128 * 1024)
        let stack = UnsafeMutableRawPointer.allocate(
            byteCount: stackSize, alignment: MemoryLayout<UInt>.alignment)
        alternateStack = stack
        var signalStack = stack_t(ss_sp: stack, ss_size: stackSize, ss_flags: 0)
        guard sigaltstack(&signalStack, nil) == 0 else { return }

        var action = sigaction()
        action.__sigaction_u.__sa_sigaction = crashStackTrapHandler
        action.sa_flags = Int32(SA_ONSTACK | SA_SIGINFO | SA_RESETHAND)
        sigemptyset(&action.sa_mask)
        // SIGSEGV is the guard-page hit; SIGBUS is the same fault on a
        // misaligned or unmapped access and costs nothing to cover.
        sigaction(SIGSEGV, &action, nil)
        sigaction(SIGBUS, &action, nil)

        installed = true
    }
    #endif

    /// The backtrace left by a **previous** run, if one died on a bad access.
    /// Reading consumes it, so a trace is uploaded once.
    public static func collectPrevious() -> [String] {
        guard let directory = FileLog.directoryURL() else { return [] }
        let manager = FileManager.default
        let ours = traceFileURL()?.lastPathComponent
        let files =
            (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []
        var traces: [String] = []
        for file in files
            where file.pathExtension == "stack" && file.lastPathComponent != ours
        {
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
                traces.append(text)
            }
            try? manager.removeItem(at: file)
        }
        return traces
    }

    static func traceFileURL() -> URL? {
        FileLog.directoryURL()?.appendingPathComponent(FileLog.runFileName(extension: "stack"))
    }

    // Called from the signal handler. Kept here so the handler itself is a
    // plain C function with no Swift metadata work in its path.
    fileprivate static func writeTrace(signal: Int32) {
        guard let pathBuffer, let frames else { return }
        let fd = open(pathBuffer, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { return }

        writeLiteral(fd, "Fatal access violation, signal ")
        writeInt(fd, Int(signal))
        writeLiteral(fd, ", at unix time ")
        writeInt(fd, Int(time(nil)))
        writeLiteral(fd, "\nBacktrace of the faulting thread (innermost first):\n")

        let count = backtrace(frames, Int32(maxFrames))
        // `backtrace_symbols_fd` writes straight to the descriptor; the
        // allocating `backtrace_symbols` would not be safe here.
        backtrace_symbols_fd(frames, count, fd)
        if count >= Int32(maxFrames) {
            writeLiteral(fd, "... truncated, the stack is at least this deep\n")
        }
        close(fd)
    }

    private static func writeLiteral(_ fd: Int32, _ text: StaticString) {
        _ = text.withUTF8Buffer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return write(fd, base, buffer.count)
        }
    }

    /// Decimal, without `malloc`. A signal handler must not allocate — the
    /// process may well have crashed inside the allocator, and taking its lock
    /// again would hang instead of crashing.
    private static func writeInt(_ fd: Int32, _ value: Int) {
        let capacity = 24
        withUnsafeTemporaryAllocation(of: CChar.self, capacity: capacity) { digits in
            var value = value
            var index = capacity - 1
            if value <= 0 {
                digits[index] = CChar(UInt8(ascii: "0"))
                index -= 1
            }
            while value > 0, index >= 0 {
                digits[index] = CChar(UInt8(ascii: "0") + UInt8(value % 10))
                value /= 10
                index -= 1
            }
            let start = index + 1
            guard let base = digits.baseAddress else { return }
            _ = write(fd, base + start, capacity - start)
        }
    }
}

/// The `SA_SIGINFO` handler. A file-scope C function so no Swift closure
/// context is needed at signal time.
///
/// It writes the trace and **returns**. `SA_RESETHAND` has already restored the
/// default disposition, so the faulting instruction re-executes, faults again,
/// and the process dies exactly as it would have — same address, same thread,
/// same faulting frame. Calling `raise` instead would kill the process from
/// inside the handler and hand the OS crash reporter `raise`'s stack rather
/// than the recursion's, degrading the very MetricKit report this is meant to
/// supplement. We add a trace; we do not alter the crash.
#if !os(watchOS)
private let crashStackTrapHandler:
    @convention(c) (Int32, UnsafeMutablePointer<siginfo_t>?, UnsafeMutableRawPointer?) -> Void = {
        signalNumber, _, _ in
        CrashStackTrap.writeTrace(signal: signalNumber)
    }
#endif
