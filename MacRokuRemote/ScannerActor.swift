//import SwiftData
//import NIO
//import Foundation
//
//final actor BackgroundScanningActor: ModelActor {
//    let modelContainer: ModelContainer
//    let modelExecutor: any ModelExecutor
//    let group: MultiThreadedEventLoopGroup
//    var bootstrap: DatagramBootstrap? = nil
//    var timeout: TimeAmount = .seconds(1)
//
//    
//    init(modelContainer: ModelContainer) {
//        self.modelContainer = modelContainer
//        let context = ModelContext(modelContainer)
//        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
//        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//    }
//    
//    func itemFound(location: String, id: String) async {
//        let modelContext = ModelContext(modelContainer)
//        
//        var matchingIds = FetchDescriptor<Device>(
//            predicate: #Predicate { $0.id == id }
//        )
//        matchingIds.fetchLimit = 1
//        matchingIds.includePendingChanges = true
//        
//        let existingDevices: [Device] = (try? modelContext.fetch(matchingIds)) ?? []
//        
//        
//        if let device = existingDevices.first {
//            device.location = location
//        } else {
//            let newDevice = Device(
//                name: "New device",
//                location: location,
//                id: id
//            )
//            modelContext.insert(newDevice)
//        }
//        
//        try? modelContext.save()
//    }
//    
//    
//    func scanContinually() async {
//        self.bootstrap = DatagramBootstrap(group: group)
//            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_BROADCAST), value: 1)
//            .channelInitializer { channel in
//                channel.pipeline.addHandler(DatagramHandler(scanner: self))
//            }
//        while !Task.isCancelled {
//            try? await Task.sleep(nanoseconds: 1_000_000_000)
//            var channel: Channel? = nil
//            do {
//                channel = try await bootstrap?.bind(host: "0.0.0.0", port: 0).get()
//            } catch {
//                print("Error getting channel: \(error)")
//            }
//            guard let channel = channel else {
//                continue
//            }
//            
//            
//            let message = """
//M-SEARCH * HTTP/1.1
//Host: 239.255.255.250:1900
//Man: "ssdp:discover"
//ST: roku:ecp
//
//"""
//            
//            while !Task.isCancelled {
//                do {
//                    try await channel.writeAndFlush(NIOAny(message)).get()
//                } catch {
//                    print("Error writing and flusing channel: \(error)")
//                    continue
//                }
//                let jitter = Int.random(in: 0..<500) // Random jitter
//                try? await Task.sleep(nanoseconds: UInt64(timeout.nanoseconds) + UInt64(jitter))
//                if timeout < .seconds(30) {
//                    timeout = .seconds(min(30, timeout.nanoseconds * 1_000_000_000 * 2))
//                }
//            }
//        }
//    }
//}
//
//class DatagramHandler: ChannelInboundHandler {
//    typealias InboundIn = AddressedEnvelope<ByteBuffer>
//    let scanner: BackgroundScanningActor
//    
//    init(scanner: BackgroundScanningActor) {
//        self.scanner = scanner
//    }
//    
//    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        let envelope = self.unwrapInboundIn(data)
//        let buffer = envelope.data
//        guard let string = buffer.getString(at: 0, length: buffer.readableBytes) else {
//            return
//        }
//        // We are searching for a packet like this:
//        // HTTP/1.1 200 OK
//        // Cache-Control: max-age=3600
//        // ST: roku:ecp
//        // Location: http://192.168.1.134:8060/
//        // USN: uuid:roku:ecp:P0A070000007
//        
//        
//        
//        let lines = string.split(separator: "\n")
//        var locationValue: String? = nil
//        var idValue: String? = nil
//        
//        for line in lines {
//            if line.starts(with: "Location: ") {
//                locationValue = String(line.dropFirst("Location: ".count))
//            } else if line.starts(with: "USN: ") {
//                idValue = String(line.dropFirst("USN: ".count))
//            }
//        }
//        
//        guard let id = idValue else {
//            return
//        }
//        guard let location = locationValue else {
//            return
//        }
//        Task {
//            await scanner.itemFound(location: location, id: id)
//        }
//    }
//}
