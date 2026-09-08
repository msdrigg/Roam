import Foundation
import OSLog

/// Fatal-error reports that could not be sent by the process that logged them.
///
/// Widget extensions have no way to authenticate with the backend: App Attest
/// covers Action and SSO extensions only, and an extension bundle carries no
/// App Store receipt either. Rather than give widgets a weaker credential, they
/// write the report into the shared app group and the containing app sends it
/// on its next launch.
public enum DeferredBackendErrors {
    private static let directoryName = "pending-errors"

    /// Enough to survive a burst without letting a widget in a crash loop fill
    /// the shared container.
    private static let maxFiles = 32
    private static let maxAge: TimeInterval = 14 * 24 * 60 * 60

    private struct Entry: Codable {
        let message: String
        let recordedAt: Date
        let source: String
    }

    private static func directory() -> URL? {
        guard let container = roamAppGroupContainerURL() else {
            return nil
        }
        return container.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Records a report for the containing app to deliver later.
    public static func enqueue(_ message: String) {
        guard let directory = directory() else {
            Log.backend.error("No app group container; dropping deferred backend error")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)

            let entry = Entry(
                message: message,
                recordedAt: Date(),
                source: Bundle.main.bundleIdentifier ?? "unknown"
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)

            let name = "error_\(ISO8601DateFormatter().string(from: entry.recordedAt))_\(UUID().uuidString).json"
            try data.write(to: directory.appendingPathComponent(name, isDirectory: false))
            Log.backend.notice("Queued a backend error for the containing app to send")

            prune(in: directory)
        } catch {
            Log.backend.error("Could not queue deferred backend error: \(error, privacy: .public)")
        }
    }

    /// Sends everything queued, oldest first.
    ///
    /// A file is removed only once its report is delivered, so a failed send is
    /// retried on the next launch rather than lost.
    public static func drain() async {
        guard let directory = directory(),
            FileManager.default.fileExists(atPath: directory.path)
        else {
            return
        }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            Log.backend.error("Could not list deferred backend errors: \(error, privacy: .public)")
            return
        }
        if files.isEmpty {
            return
        }

        Log.backend.notice(
            "Sending \(files.count, privacy: .public) deferred backend error(s)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files {
            guard let data = try? Data(contentsOf: file) else {
                continue
            }
            guard let entry = try? decoder.decode(Entry.self, from: data) else {
                // Unreadable and never going to become readable.
                try? FileManager.default.removeItem(at: file)
                continue
            }

            let recorded = ISO8601DateFormatter().string(from: entry.recordedAt)
            let body = ":ninja:\nDeferred report from \(entry.source) at \(recorded)\n\n\(entry.message)"
            switch await sendMessageDirect(message: body, attachment: nil) {
            case .success:
                try? FileManager.default.removeItem(at: file)
            case .failure(let error):
                Log.backend.error(
                    "Could not send deferred backend error, keeping it: \(error, privacy: .public)")
                return
            }
        }
    }

    /// Drops the oldest reports once the queue is too long or too stale.
    private static func prune(in directory: URL) {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.creationDateKey]
            ).filter({ $0.pathExtension == "json" })
        else {
            return
        }

        let cutoff = Date().addingTimeInterval(-maxAge)
        var surviving: [URL] = []
        for file in files {
            let created =
                (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            if created < cutoff {
                try? FileManager.default.removeItem(at: file)
            } else {
                surviving.append(file)
            }
        }

        guard surviving.count > maxFiles else {
            return
        }
        for file in surviving.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .prefix(surviving.count - maxFiles)
        {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
