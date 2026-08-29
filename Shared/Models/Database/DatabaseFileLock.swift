import Darwin
import Foundation

/// Keeps the process alive for the duration of a persistent database write.
///
/// Persistent writes hold an exclusive `flock` in the shared app-group
/// container on top of GRDB's SQLite/WAL locks. Suspending the process while
/// any are held gets the app killed with `0xdead10cc`, since a suspended lock
/// holder can block `RoamWidgets` indefinitely.
///
/// A background-task assertion lets the write commit and unlock first. Only
/// taken in the main app; widget and watch targets park a Dispatch worker per
/// assertion, so writes there stay unguarded.
enum DatabaseWriteSuspensionGuard {
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
