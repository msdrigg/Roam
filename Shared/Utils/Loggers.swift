import Darwin
import Foundation
import os
import OSLog

/// A log line, rendered eagerly to a `String`.
///
/// The unified log defers formatting to read time, which is no use once the
/// process dies with its buffer. The interpolation mirrors `OSLogInterpolation`
/// so call sites keep their `privacy:` annotations; every line is `.public`, so
/// the argument is ignored.
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

        /// Non-generic: avoids a specialisation per type across ~800 sites.
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

/// Writes every line to the console and to `FileLog`, so a process that dies
/// without warning still leaves a trace. `OSLogStore` only covers the reading
/// process, which for a crash upload is the launch after the crash.
public struct DualLogger: Sendable {
    private let category: String
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

/// Instrumentation for the macOS main-thread stack overflows, where MetricKit
/// returns zero frames. Records stack headroom, logging a bounded backtrace
/// when a band is first crossed, and per-body evaluation counts summarised on
/// an interval. Both are cheap enough for release builds.
@MainActor
public enum RenderTrace {
    private static let bands: [Double] = [0.4, 0.6, 0.8]
    private static let evaluationReportThreshold = 400
    private static let evaluationReportInterval: TimeInterval = 5

    /// Keyed by the literal's address, since interpolating would allocate on
    /// every body evaluation.
    private static var reportedBands: Set<Int> = []
    private static var evaluations: [UnsafeRawPointer: (site: StaticString, count: Int)] = [:]
    private static var windowStartedAt = Date()
    private static var sinceClockCheck = 0

    public static func body(_ site: StaticString) {
        checkStackHeadroom(site)

        guard site.hasPointerRepresentation else { return }
        let key = UnsafeRawPointer(site.utf8Start)
        evaluations[key, default: (site, 0)].count += 1

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

    public static func stackUsage() -> (used: Int, total: Int) {
        var probe = 0
        return withUnsafeMutablePointer(to: &probe) { pointer in
            let total = pthread_get_stacksize_np(pthread_self())
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
                "Main-thread stack \(Int(fraction * 100), privacy: .public)% used (\(used, privacy: .public) of \(total, privacy: .public) bytes) at \(site, privacy: .public) - recursion suspected"
            )
            for (depth, frame) in frames.enumerated() {
                Log.rendering.fault(
                    "  #\(depth, privacy: .public) \(frame, privacy: .public)")
            }
            FileLog.flushNow()
        }
    }

    /// A fixed-size backtrace; `Thread.callStackSymbols` materialises the whole
    /// stack.
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
