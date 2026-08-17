import Foundation
import Testing

@testable import Roam

/// `processConcurrently` has to run its task group in an unstructured `Task`,
/// because the `AsyncStream` it returns outlives the call that builds it. That
/// detaches the group from the caller's cancellation, so the stream forwards it
/// explicitly via `onTermination`.
///
/// These pin that forwarding down. Without it the work leaked: a cancelled IPv4
/// sweep kept all 37 of its slots busy for the remaining 14 seconds of the
/// process's life, yielding into a buffer nobody was reading, until the
/// scene-create watchdog killed the app (roam 1.50, `0x8BADF00D`).
struct ProcessConcurrentlyTests {
    /// Items are plentiful and each is slow enough that an uncancelled run would
    /// obviously blow past the bounds asserted below.
    private static let itemCount = 400
    private static let maxConcurrent = 4
    private static let workDuration = Duration.milliseconds(5)
    /// Long enough that an unforwarded cancellation would get most of the way
    /// through `itemCount`: ~240 items at these settings.
    private static let settleDuration = Duration.milliseconds(300)

    /// Counts operations that got past their own cancellation check, the way
    /// `scanAddress` does before it opens a connection.
    private actor WorkCounter {
        private(set) var started = 0

        func recordStart() {
            started += 1
        }
    }

    private static func countingStream(
        _ counter: WorkCounter
    ) -> AsyncStream<Int> {
        processConcurrently(
            items: Array(0..<itemCount), maxConcurrent: maxConcurrent
        ) { item in
            if Task.isCancelled { return -1 }
            await counter.recordStart()
            try? await Task.sleep(for: workDuration)
            return item
        }
    }

    /// The production shape: SwiftUI cancels the `.task` that is consuming the
    /// stream, which is what happened when `NWPathMonitor` fired mid-sweep.
    @Test func cancellingTheConsumingTaskStopsTheWork() async throws {
        let counter = WorkCounter()

        let consumer = Task {
            for await _ in Self.countingStream(counter) {
                // Consume one result, then wait to be cancelled rather than
                // draining the stream.
                try? await Task.sleep(for: .seconds(10))
            }
        }

        // Let the first slots land before pulling the rug out.
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()
        _ = await consumer.value

        let atCancellation = await counter.started
        try await Task.sleep(for: Self.settleDuration)
        let afterSettling = await counter.started

        #expect(
            afterSettling == atCancellation,
            "work kept starting after the consumer was cancelled")
        #expect(afterSettling < Self.itemCount)
    }

    /// Breaking out of the loop ends iteration too, and must not leave the
    /// producer running against a buffer nobody reads.
    @Test func breakingOutOfIterationStopsTheWork() async throws {
        let counter = WorkCounter()

        for await _ in Self.countingStream(counter) {
            break
        }

        let atBreak = await counter.started
        try await Task.sleep(for: Self.settleDuration)
        let afterSettling = await counter.started

        // Slots already dispatched may still record a start as cancellation
        // propagates, but the run must not continue feeding new ones.
        #expect(afterSettling <= atBreak + Self.maxConcurrent)
        #expect(afterSettling < Self.itemCount)
    }

    /// The forwarding must not truncate an ordinary run.
    @Test func drainsEveryItemWhenNobodyCancels() async throws {
        let counter = WorkCounter()
        var results: [Int] = []

        for await result in Self.countingStream(counter) {
            results.append(result)
        }

        #expect(results.count == Self.itemCount)
        #expect(await counter.started == Self.itemCount)
        #expect(Set(results) == Set(0..<Self.itemCount))
    }
}
