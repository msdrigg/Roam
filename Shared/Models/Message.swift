import SwiftData
import Foundation

public typealias Message = SchemaV1.Message

func getTestingMessages() -> [Message] {
    return [
        Message(id: "t1", message: "HI", author: .me),
        Message(id: "t2", message: "BYE BRO", author: .support),
        Message(id: "t3", message: "BYE BRO (part two but this time with a lot more text. Does it wrap? Does it work? IDK???BYE BRO (part two but this time with a lot more text. Does it wrap? Does it work? IDK???", author: .support),
        Message(id: "t4", message: "Resolved! (part two but this time with a lot more text. Does it wrap? Does it work? IDK???", author: .me),
    ]
}
