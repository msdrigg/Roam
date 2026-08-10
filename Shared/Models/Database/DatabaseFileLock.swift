import Darwin
import Foundation

/// Keeps the process alive for the duration of a persistent database write.
///
/// Persistent writes take an exclusive `flock` on a lock file inside the shared
/// app-group container (see ``DatabaseFileLock``), on top of the SQLite/WAL locks
/// GRDB holds on `Roam.sqlite` in that same container. If iOS suspends the process
/// while any of those are held, the app is killed with `0xdead10cc` — surfaced
/// through MetricKit as `EXC_CRASH` (10) / `SIGKILL` (9) — because a suspended
/// lock holder can block `RoamWidgets` indefinitely.
///
/// Holding a background-task assertion across the write lets it commit and unlock
/// before the process is allowed to suspend.
enum DatabaseWriteSuspensionGuard {
    /// Runs `body` with a "don't suspend me" assertion held.
    ///
    /// The assertion is only taken in the main app, where `QRunInBackgroundAssertion`
    /// resolves to the cheap `UIApplication.beginBackgroundTask` implementation. The
    /// widget and watch targets get `QActivityRunInBackgroundAssertion`, which parks a
    /// Dispatch worker thread per instance and is documented as unsafe to allocate
    /// freely — writes there stay unguarded rather than risk starving the thread pool.
    /// macOS has no equivalent suspension policy.
    static func protectingFromSuspension<T>(_ body: () async throws -> T) async rethrows -> T {
        #if canImport(UIKit) && !os(watchOS) && !WIDGET
            let assertion = await QRunInBackgroundAssertion(name: "roam-database-write")
            defer {
                Task { @MainActor in
                    assertion.release()
                }
            }
            return try await body()
        #else
            return try await body()
        #endif
    }
}

final class DatabaseFileLock: @unchecked Sendable {
    private let lockURL: URL

    init(lockURL: URL) {
        self.lockURL = lockURL
    }

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        }

        let fd = open(lockURL.path, O_RDWR)
        guard fd >= 0 else {
            throw DataHandlerError.fromPOSIX(errno: errno, fallback: .databaseLocked)
        }

        if flock(fd, LOCK_EX) != 0 {
            let lockErrno = errno
            close(fd)
            throw DataHandlerError.fromPOSIX(errno: lockErrno, fallback: .databaseLocked)
        }

        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }

        return try body()
    }
}
