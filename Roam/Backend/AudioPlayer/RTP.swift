//
//  RTP.swift
//  Roam
//
//  Created by Scott Driggers on 10/21/23.
//

import Foundation
import RTP
import Opus

struct RtpPacket: Comparable {
    static func < (lhs: RtpPacket, rhs: RtpPacket) -> Bool {
        lhs.packet.sequenceNumber > rhs.packet.sequenceNumber
    }
    
    static func == (lhs: RtpPacket, rhs: RtpPacket) -> Bool {
        lhs.packet.sequenceNumber == rhs.packet.sequenceNumber
    }
    
    let packet: Packet
    let receivedAt: UInt64
    
    var payload: Data {
        packet.payload
    }
    
    var validOpus: Bool {
        packet.payloadType.rawValue == RTP_PAYLOAD_TYPE
    }
    
    init(data: Data) throws {
        packet = try Packet(from: data)
        receivedAt = mach_absolute_time()
    }
}
