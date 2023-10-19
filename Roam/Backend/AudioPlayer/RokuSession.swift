import Foundation
import Network

typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>

extension URLSessionWebSocketTask {
    var stream: WebSocketStream {
        return WebSocketStream { continuation in
            Task {
                var isAlive = true

                while isAlive && closeCode == .invalid {
                    do {
                        let value = try await receive()
                        continuation.yield(value)
                    } catch {
                        continuation.finish(throwing: error)
                        isAlive = false
                    }
                }
            }
        }
    }
}


class SocketStream: AsyncSequence {
    typealias AsyncIterator = WebSocketStream.Iterator
    typealias Element = URLSessionWebSocketTask.Message

    private var continuation: WebSocketStream.Continuation?
    private let task: URLSessionWebSocketTask

    private lazy var stream: WebSocketStream = {
        return WebSocketStream { continuation in
            self.continuation = continuation

            Task {
                var isAlive = true

                while isAlive && task.closeCode == .invalid {
                    do {
                        let value = try await task.receive()
                        continuation.yield(value)
                    } catch {
                        continuation.finish(throwing: error)
                        isAlive = false
                    }
                }
            }
        }
    }()

    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }

    deinit {
        continuation?.finish()
    }

    func makeAsyncIterator() -> AsyncIterator {
        return stream.makeAsyncIterator()
    }

    func cancel() async throws {
        task.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
    }
}
