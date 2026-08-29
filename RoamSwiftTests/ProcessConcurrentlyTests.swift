import Foundation
import Testing

@testable import Roam

/// `processConcurrently` runs its task group in an unstructured `Task`, since
/// the `AsyncStream` outlives the call that builds it. That detaches the group
/// from the caller's cancellation, which the stream forwards via
/// `onTermination`. These tests pin that forwarding down.
struct ProcessConcurrentlyTests {
    private static let itemCount = 400
    private static let maxConcurrent = 4
    private static let workDuration = Duration.milliseconds(5)
    private static let settleDuration = Duration.milliseconds(300)

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

    @Test func cancellingTheConsumingTaskStopsTheWork() async throws {
        let counter = WorkCounter()

        let consumer = Task {
            for await _ in Self.countingStream(counter) {
                try? await Task.sleep(for: .seconds(10))
            }
        }

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

    @Test func breakingOutOfIterationStopsTheWork() async throws {
        let counter = WorkCounter()

        for await _ in Self.countingStream(counter) {
            break
        }

        let atBreak = await counter.started
        try await Task.sleep(for: Self.settleDuration)
        let afterSettling = await counter.started

        #expect(afterSettling <= atBreak + Self.maxConcurrent)
        #expect(afterSettling < Self.itemCount)
    }

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
