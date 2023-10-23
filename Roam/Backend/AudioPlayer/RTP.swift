//
//  RTP.swift
//  Roam
//
//  Created by Scott Driggers on 10/21/23.
//

import Foundation
import RTP
import Opus

struct RtpPacket {
    let packet: Packet
    let receivedAt: Date
    
    var payload: Data {
        packet.payload
    }
    
    var validOpus: Bool {
        packet.payloadType.rawValue == RTP_PAYLOAD_TYPE
    }
    
    init(data: Data) throws {
        packet = try Packet(from: data)
        receivedAt = Date.now
    }
}
