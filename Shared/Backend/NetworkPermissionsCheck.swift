import Foundation
import Network
import os
import OSLog

/// Serialises `start` and `cancel` for a group of Network.framework endpoints.
///
/// Two rules, both of which this file has broken in production:
///
/// 1. **Cancel exactly once.** `nw_browser_cancel` is not safe against itself.
///    1.52 died with a `SIGSEGV` when the task-thread teardown raced the
///    `onCancel` one that ee13c8f2 added.
///
/// 2. **Never cancel an endpoint that was never started.** `start(queue:)` is
///    what hands Network.framework the queue it delivers state changes on. Cancel
///    an endpoint that has a state update handler but no queue and
///    `nw_browser_set_state_locked` calls `dispatch_async` with a NULL queue --
///    a `SIGSEGV` on the near-null address `0x54`. That is a framework bug
///    (Apple r.139710124, https://developer.apple.com/forums/thread/768413) and
///    the only defence is to not make the call.
///
/// 1.54 still died on rule 2, because the claim-once wrapper added in 9d8735db
/// only implemented rule 1: `onCancel` runs the instant the task is cancelled,
/// which can land before the stream closure has reached `start(queue:)` at all.
///
/// The cancel is dispatched onto the endpoints' own queue rather than run
/// inline, because `cancel()` blocks on an internal Network.framework lock and
/// `onCancel` runs on whichever thread cancelled the task -- the main thread,
/// when SwiftUI tears down `.task` work during a scene-phase change. Blocking it
/// there is the 0x8BADF00D watchdog kill ee13c8f2 fixed.
///
/// `CloseOnceFileDescriptor` in `SSDPDiscovery` guards the same shape of bug for
/// raw sockets.
private final class EndpointLifecycle: @unchecked Sendable {
    private enum Phase {
        /// Created, no queue set. Cancelling now is the crash described above.
        case idle
        /// Inside `startEndpoints`; the queue is not yet guaranteed to be set.
        case starting
        /// The queue is set, so cancelling is safe.
        case started
    }

    private struct State {
        var phase: Phase = .idle
        var cancelRequested = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue: DispatchQueue
    private let startEndpoints: @Sendable (DispatchQueue) -> Void
    private let cancelEndpoints: @Sendable () -> Void

    init(
        queue: DispatchQueue,
        start: @escaping @Sendable (DispatchQueue) -> Void,
        cancel: @escaping @Sendable () -> Void
    ) {
        self.queue = queue
        self.startEndpoints = start
        self.cancelEndpoints = cancel
    }

    /// Starts the endpoints unless a cancel got there first.
    ///
    /// Returns `false` when the caller must abandon setup: either the task was
    /// already cancelled, or it was cancelled while the endpoints were starting,
    /// in which case the teardown has already been dispatched here.
    func start() -> Bool {
        let claimed = state.withLock { state -> Bool in
            guard state.phase == .idle, !state.cancelRequested else { return false }
            state.phase = .starting
            return true
        }
        guard claimed else { return false }

        // Deliberately outside the lock: `start(queue:)` reaches into
        // Network.framework's own locks, and a state handler that re-entered
        // this class from there would deadlock on a non-reentrant unfair lock. A
        // cancel arriving meanwhile is handled by the check below instead.
        startEndpoints(queue)

        let cancelDeferred = state.withLock { state -> Bool in
            state.phase = .started
            return state.cancelRequested
        }
        guard !cancelDeferred else {
            // A cancel landed mid-start and left the teardown to us; it could not
            // run it itself without racing the `start(queue:)` above.
            Log.network.notice("Local network check cancelled while starting, tearing down.")
            dispatchCancel()
            return false
        }
        return true
    }

    func cancel() {
        enum Outcome {
            case tearDown
            case neverStarted
            case deferredToStart
            case redundant
        }

        let outcome = state.withLock { state -> Outcome in
            if state.cancelRequested { return .redundant }
            state.cancelRequested = true
            switch state.phase {
            case .idle: return .neverStarted
            case .starting: return .deferredToStart
            case .started: return .tearDown
            }
        }

        switch outcome {
        case .tearDown:
            dispatchCancel()
        case .neverStarted:
            // No queue was ever set, so there is nothing bound to tear down --
            // and cancelling here is exactly the crash in rule 2 above.
            Log.network.notice("Local network check cancelled before start, nothing to tear down.")
        case .deferredToStart:
            Log.network.notice("Local network check cancelled during start, teardown deferred.")
        case .redundant:
            Log.network.notice("Skipping redundant local network check cancel")
        }
    }

    private func dispatchCancel() {
        let cancelEndpoints = self.cancelEndpoints
        queue.async { cancelEndpoints() }
    }
}

#if os(macOS)
func requestLocalNetworkAuthorization() async throws -> Bool {
    let queue = DispatchQueue.makeNetworkQueue()

    let connection = NWConnection(host: NWEndpoint.Host("255.255.255.255"), port: 4567, using: .udp)
    let endpoint = EndpointLifecycle(
        queue: queue,
        start: { queue in connection.start(queue: queue) },
        cancel: { connection.cancel() }
    )

    return try await withTaskCancellationHandler {
        let stream = AsyncThrowingStream(Bool.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            @Sendable func resume(with result: Result<Bool, any Error>) {
                // Teardown the connection. Both handlers are cleared, not just
                // the state one: a later path update would otherwise re-enter
                // here after the stream has already been finished.
                connection.stateUpdateHandler = { _ in }
                connection.pathUpdateHandler = { _ in }
                endpoint.cancel()

                continuation.yield(with: result)
            }

            // Do not setup listener/browser is we're already cancelled, it does work but logs a lot of very ugly errors
            if Task.isCancelled {
                Log.network.notice("Task cancelled before listener & browser started.")
                resume(with: .failure(CancellationError()))
                return
            }
            connection.pathUpdateHandler = { newPath in
                Log.network.notice("Browser path changed to \(String(describing: newPath))")
                if newPath.status == .unsatisfied && newPath.unsatisfiedReason == .localNetworkDenied {
                    resume(with: .success(false))
                }
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .setup:
                    Log.network.notice("Browser performing setup.")
                    return
                case .ready:
                    Log.network.notice("Connection ready to send packets.")
                    resume(with: .success(true))
                    return
                case .cancelled:
                    Log.network.notice("Connection cancelled.")
                    resume(with: .failure(CancellationError()))
                case .failed(let error):
                    Log.network.error("Connection failed, stopping. \(error, privacy: .public)")
                    resume(with: .failure(error))
                case let .waiting(error):
                    Log.network.error("Connection waiting, will update in pathUpdateHandler. \(error, privacy: .public)")
                    queue.asyncAfter(deadline: .now() + 0.1) {
                        switch connection.state {
                        case .waiting: connection.restart()
                        default: break
                        }
                    }
                case .preparing:
                    Log.network.notice("Connection preparing.")
                @unknown default:
                    Log.network.warning("Ignoring unknown Connection state: \(String(describing: newState), privacy: .public)")
                    return
                }
            }

            // Started only once every handler is wired, and only through
            // `endpoint`: `start(queue:)` is what gives Network.framework the
            // queue it needs before any cancel can reach this connection.
            guard endpoint.start() else {
                Log.network.notice("Task cancelled while starting connection.")
                resume(with: .failure(CancellationError()))
                return
            }
        }

        var iterator = stream.makeAsyncIterator()
        guard let first = try await iterator.next() else {
            throw CancellationError()
        }

        return first
    } onCancel: {
        endpoint.cancel()
    }
}
#else
private let type = "_preflight_check._tcp"

func requestLocalNetworkAuthorization() async throws -> Bool {
    let queue = DispatchQueue.makeNetworkQueue()

    Log.network.notice("Setup listener.")
    let listener = try NWListener(using: NWParameters(tls: .none, tcp: NWProtocolTCP.Options()))
    listener.service = NWListener.Service(name: UUID().uuidString, type: type)
    listener.newConnectionHandler = { _ in } // Must be set or else the listener will error with POSIX error 22

    Log.network.notice("Setup browser.")
    let parameters = NWParameters()
    parameters.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: parameters)
    let endpoints = EndpointLifecycle(
        queue: queue,
        start: { queue in
            listener.start(queue: queue)
            browser.start(queue: queue)
        },
        cancel: {
            listener.cancel()
            browser.cancel()
        }
    )

    return try await withTaskCancellationHandler {
        let stream = AsyncThrowingStream(Bool.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            // `resume` is reachable from the listener and browser callbacks on
            // `queue` and from the `Task.isCancelled` checks on the task's own
            // thread, so two threads can enter it at once. Claim it so only one
            // rewrites the handler properties and yields.
            let resumed = OSAllocatedUnfairLock(initialState: false)
            @Sendable func resume(with result: Result<Bool, any Error>) {
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    if alreadyResumed { return false }
                    alreadyResumed = true
                    return true
                }
                guard shouldResume else { return }

                // Teardown listener and browser. The handlers are cleared here
                // rather than in `onCancel` so that a cancel raised from there
                // still reaches this function through the `.cancelled` state and
                // finishes the stream.
                listener.stateUpdateHandler = { _ in }
                browser.stateUpdateHandler = { _ in }
                browser.browseResultsChangedHandler = { _, _ in }
                endpoints.cancel()

                continuation.yield(with: result)
            }

            // Do not setup listener/browser is we're already cancelled, it does work but logs a lot of very ugly errors
            if Task.isCancelled {
                Log.network.notice("Task cancelled before listener & browser started.")
                resume(with: .failure(CancellationError()))
                return
            }

            listener.stateUpdateHandler = { newState in
                switch newState {
                case .setup:
                    Log.network.notice("Listener performing setup.")
                case .ready:
                    Log.network.notice("Listener ready to be discovered.")
                case .cancelled:
                    Log.network.notice("Listener cancelled.")
                    resume(with: .failure(CancellationError()))
                case .failed(let error):
                    Log.network.error("Listener failed, stopping. \(error, privacy: .public)")
                    resume(with: .failure(error))
                case .waiting(let error):
                    Log.network.warning("Listener waiting, stopping. \(error, privacy: .public)")
                    resume(with: .failure(error))
                @unknown default:
                    Log.network.warning("Ignoring unknown listener state: \(String(describing: newState), privacy: .public)")
                }
            }

            browser.stateUpdateHandler = { newState in
                switch newState {
                case .setup:
                    Log.network.notice("Browser performing setup.")
                    return
                case .ready:
                    Log.network.notice("Browser ready to discover listeners.")
                    return
                case .cancelled:
                    Log.network.notice("Browser cancelled.")
                    resume(with: .failure(CancellationError()))
                case .failed(let error):
                    Log.network.error("Browser failed, stopping. \(error, privacy: .public)")
                    resume(with: .failure(error))
                case let .waiting(error):
                    switch error {
                    case .dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)):
                        Log.network.notice("Browser permission denied, reporting failure.")
                        resume(with: .success(false))
                    default:
                        Log.network.error("Browser waiting, stopping. \(error, privacy: .public)")
                        resume(with: .failure(error))
                    }
                @unknown default:
                    Log.network.warning("Ignoring unknown browser state: \(String(describing: newState), privacy: .public)")
                    return
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                if results.isEmpty {
                    Log.network.warning("Got empty result set from browser, ignoring.")
                    return
                }

                Log.network.notice("Discovered \(results.count, privacy: .public) listeners, reporting success.")
                resume(with: .success(true))
            }

            // Both are started here, together, only once every handler is
            // wired, and only through `endpoints`: `start(queue:)` is what gives
            // Network.framework the queue it needs before any cancel can reach
            // these objects.
            guard endpoints.start() else {
                Log.network.notice("Task cancelled while starting listener & browser.")
                resume(with: .failure(CancellationError()))
                return
            }
        }

        var iterator = stream.makeAsyncIterator()
        guard let first = try await iterator.next() else {
            throw CancellationError()
        }

        return first
    } onCancel: {
        // `onCancel` runs synchronously on whichever thread cancels the task, and
        // SwiftUI cancels `.task` work on the main thread while it applies a
        // scene-phase change. `NWBrowser.cancel()` / `NWListener.cancel()` block
        // on an internal Network.framework lock, so when `queue` is busy this
        // stalls the main thread — long enough on app termination to be killed by
        // the watchdog with 0x8BADF00D ("Failed to terminate gracefully after
        // 5.0s"). Tear down on the queue these objects already run on so the
        // cancelling thread is never blocked.
        endpoints.cancel()
    }
}
#endif
