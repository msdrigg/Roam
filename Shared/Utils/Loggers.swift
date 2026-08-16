import Darwin
import Foundation
import os
import OSLog

/// A log line, rendered eagerly to a `String`.
///
/// `Logger` takes an `OSLogMessage`, which is deliberately opaque — the whole
/// point of the unified log is that formatting is deferred to read time. That
/// is a good trade until the process dies and takes its buffer with it, which
/// is exactly the case Roam needs to diagnose, so `DualLogger` renders the line
/// once and hands the same text to both the console and `FileLog`.
///
/// The interpolation deliberately mirrors `OSLogInterpolation` closely enough
/// that call sites keep their `privacy:` annotations and compile unchanged.
/// Every line Roam logs is already `.public` — these are device names, IPs and
/// error text, not secrets, and a persisted `<private>` has no diagnostic
/// value — so the argument is accepted and ignored rather than honoured.
public struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    public let text: String

    public init(stringLiteral value: String) {
        text = value
    }

    public init(stringInterpolation: Interpolation) {
        text = stringInterpolation.text
    }

    public struct Interpolation: StringInterpolationProtocol {
        var text: String

        public init(literalCapacity: Int, interpolationCount: Int) {
            text = ""
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            text.append(literal)
        }

        /// Non-generic on purpose: one `Any` overload keeps the app from
        /// emitting a specialisation per interpolated type across ~800 call
        /// sites, which the binary-size budget would notice.
        public mutating func appendInterpolation(
            _ value: @autoclosure () -> Any, privacy _: OSLogPrivacy = .auto
        ) {
            let value = value()
            if let string = value as? String {
                text.append(string)
            } else {
                text.append(String(describing: value))
            }
        }
    }
}

/// Writes every line twice: to the system console, so it can be correlated
/// against the rest of the system live, and to `FileLog`, so a process that
/// dies without warning still leaves its trace for the next launch to upload.
///
/// Modelled on Artemis's logger of the same name, for the same reason: the
/// OS-provided read-back (`OSLogStore(scope: .currentProcessIdentifier)`)
/// only ever covers the process doing the reading, which for a crash upload is
/// the launch *after* the one that crashed.
public struct DualLogger: Sendable {
    private let category: String
    /// The underlying console logger, for the rare caller that wants
    /// `OSLogMessage`'s deferred formatting.
    public let console: Logger

    public init(_ category: String) {
        self.category = category
        console = Logger(subsystem: Log.getLogSubsystem(), category: category)
    }

    public func trace(_ message: LogMessage) {
        emit(message, level: .debug, name: "Debug")
    }

    public func debug(_ message: LogMessage) {
        emit(message, level: .debug, name: "Debug")
    }

    public func info(_ message: LogMessage) {
        emit(message, level: .info, name: "Info")
    }

    public func notice(_ message: LogMessage) {
        emit(message, level: .default, name: "Notice")
    }

    /// The unified log has no warning level — `Logger.warning` is `.error` — so
    /// this records as `Error`, matching how the same line reads back out of
    /// `OSLogStore`.
    public func warning(_ message: LogMessage) {
        emit(message, level: .error, name: "Error")
    }

    public func error(_ message: LogMessage) {
        emit(message, level: .error, name: "Error")
    }

    public func fault(_ message: LogMessage) {
        emit(message, level: .fault, name: "Fault")
    }

    private func emit(_ message: LogMessage, level: OSLogType, name: String) {
        let text = message.text
        console.log(level: level, "\(text, privacy: .public)")
        FileLog.append(level: name, category: category, message: text)
    }
}

public enum Log {
    // Used for watch connectivity
    public static let watch = DualLogger("Watch")
    // Used for notification events
    public static let notifications = DualLogger("Notifications")
    // Used for backend events and status
    public static let backend = DualLogger("Backend")
    // Used for UI interface
    public static let interface = DualLogger("Interface")
    // Used for network status and permissions logs
    public static let network = DualLogger("Network")
    // Used for data loading, storage and other information
    public static let data = DualLogger("Data")
    // Used for all view and app lifecycle related events
    public static let lifecycle = DualLogger("Lifecycle")
    // Used for the headphones mode and related events (latency listener included)
    public static let headphones = DualLogger("Headphones")
    // Used for the scanning module and related events
    public static let scanning = DualLogger("Scanning")
    // Used for the device connection module and related events
    public static let connection = DualLogger("Connection")
    // Used for direct response to users clicking buttons or performing actions
    public static let userInteraction = DualLogger("UserInteraction")
    // Used for view-tree evaluation and main-thread stack depth (see `RenderTrace`)
    public static let rendering = DualLogger("Rendering")

    public static func getLogSubsystem() -> String {
        return Bundle.main.bundleIdentifier ?? "com.msdrigg.roam"
    }
}

/// Instrumentation for the unexplained macOS main-thread stack overflows.
///
/// Two users on two Macs, on 1.50 and 1.51, crashed with the faulting address
/// inside the Stack Guard region 607 bytes below the main stack — the same
/// depth both times, so it is a repeatable recursion rather than corruption.
/// Neither report could say *what* recursed: MetricKit returns zero frames for
/// a blown stack.
///
/// Two things are recorded here, both cheap enough to leave on in release:
///
/// - **Stack headroom.** A view body costs a pointer comparison to ask how much
///   of the 8 MB main stack is gone. Crossing a band that has not been reported
///   yet logs a bounded backtrace, which names the recursion *before* the
///   overflow kills the process — and it lands in `FileLog`, so it survives.
/// - **Body evaluation counts.** A view re-entering its own body is the shape
///   a SwiftUI recursion takes, and a runaway re-render is worth seeing even
///   when it stops short of a crash. Counts are summarised on an interval
///   rather than logged per evaluation, so the log stays readable.
@MainActor
public enum RenderTrace {
    /// Fractions of the thread's stack that are worth a backtrace. The first is
    /// already far past anything a healthy view tree uses.
    private static let bands: [Double] = [0.4, 0.6, 0.8]
    /// Only summarise when a body is running hot; a redraw or two per second is
    /// normal and not worth a line.
    private static let evaluationReportThreshold = 400
    private static let evaluationReportInterval: TimeInterval = 5

    /// Keyed by the literal's address rather than its text: this runs on every
    /// evaluation of an instrumented body, and `"\(site)"` would allocate a
    /// `String` each time just to look up a counter.
    private static var reportedBands: Set<Int> = []
    private static var evaluations: [UnsafeRawPointer: (site: StaticString, count: Int)] = [:]
    private static var windowStartedAt = Date()
    private static var sinceClockCheck = 0

    /// Record one evaluation of a view body, and check the stack under it.
    ///
    /// Call from the `body` of views on the suspect path. It is a counter bump
    /// and a couple of pointer reads unless something is actually wrong.
    public static func body(_ site: StaticString) {
        checkStackHeadroom(site)

        guard site.hasPointerRepresentation else { return }
        let key = UnsafeRawPointer(site.utf8Start)
        evaluations[key, default: (site, 0)].count += 1

        // Asking the clock on every body evaluation would cost more than the
        // counter it guards.
        sinceClockCheck += 1
        guard sinceClockCheck >= 64 else { return }
        sinceClockCheck = 0

        let now = Date()
        let elapsed = now.timeIntervalSince(windowStartedAt)
        guard elapsed >= evaluationReportInterval else { return }

        let hot = evaluations.values.filter { $0.count >= evaluationReportThreshold }
        if !hot.isEmpty {
            let summary =
                hot
                .sorted { $0.count > $1.count }
                .map { "\($0.site)=\($0.count)" }
                .joined(separator: " ")
            Log.rendering.warning(
                "Hot view bodies over \(String(format: "%.1f", elapsed), privacy: .public)s: \(summary, privacy: .public)"
            )
        }
        evaluations.removeAll(keepingCapacity: true)
        windowStartedAt = now
    }

    /// How much of the current thread's stack has been used, and how big it is.
    public static func stackUsage() -> (used: Int, total: Int) {
        var probe = 0
        return withUnsafeMutablePointer(to: &probe) { pointer in
            let total = pthread_get_stacksize_np(pthread_self())
            // Darwin's "stack address" is the high end; the stack grows down
            // from it toward the guard region.
            let top = pthread_get_stackaddr_np(pthread_self())
            let used = UnsafeRawPointer(top) - UnsafeRawPointer(pointer)
            return (max(0, used), total)
        }
    }

    private static func checkStackHeadroom(_ site: StaticString) {
        let (used, total) = stackUsage()
        guard total > 0 else { return }
        let fraction = Double(used) / Double(total)

        for (index, band) in bands.enumerated() where fraction >= band {
            guard !reportedBands.contains(index) else { continue }
            reportedBands.insert(index)
            let frames = boundedBacktrace()
            Log.rendering.fault(
                "Main-thread stack \(Int(fraction * 100), privacy: .public)% used (\(used, privacy: .public) of \(total, privacy: .public) bytes) at \(site, privacy: .public) — recursion suspected"
            )
            for (depth, frame) in frames.enumerated() {
                Log.rendering.fault(
                    "  #\(depth, privacy: .public) \(frame, privacy: .public)")
            }
            // The next thing to happen may be the guard page, so do not leave
            // this sitting in the buffer.
            FileLog.flushNow()
        }
    }

    /// A fixed-size backtrace. `Thread.callStackSymbols` materialises the whole
    /// stack, which is the one thing not to do when the stack is the problem.
    private static func boundedBacktrace(maxFrames: Int = 96) -> [String] {
        var addresses = [UnsafeMutableRawPointer?](repeating: nil, count: maxFrames)
        let count = Int(backtrace(&addresses, Int32(maxFrames)))
        guard count > 0, let symbols = backtrace_symbols(&addresses, Int32(count)) else {
            return []
        }
        defer { free(symbols) }
        return (0 ..< count).compactMap { index in
            symbols[index].map { String(cString: $0) }
        }
    }
}
