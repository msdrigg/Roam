import Foundation
import SwiftData

public typealias Message = SchemaV1.Message

@available(*, unavailable)
extension Message: Sendable {}

extension Message {
    convenience init(_ message: MessageModelResponse) {
        self.init(id: message.id, message: message.message, author: message.author)
    }
}
